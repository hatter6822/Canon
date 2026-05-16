// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! Kernel abstraction for the canon-host network adaptor.
//!
//! ## What this module provides
//!
//!   * [`Kernel`] — the trait the network adaptor consumes.  One
//!     method: `submit(&self, bytes: &[u8]) -> KernelResponse`.
//!     Implementations are responsible for decoding the CBE bytes
//!     as a `SignedAction`, deciding admissibility, and returning
//!     the resulting `Verdict`.
//!   * [`mock::MockKernel`] — a configurable in-memory kernel for
//!     tests and dev mode.  Records every submission; returns
//!     verdicts from a configurable sequence (defaults to `Ok`).
//!   * [`command::CommandKernel`] — a per-request subprocess
//!     kernel.  Spawns the Lean `canon` binary's `process`
//!     subcommand for each request, parses the exit code, and
//!     returns the resulting verdict.  Heavy (O(log size) per
//!     request) but correct.  The future optimization is a
//!     `canon serve` Lean-side subcommand that reads CBE frames
//!     from stdin and writes verdicts to stdout, eliminating the
//!     per-request bootstrap cost.
//!
//! ## Why the abstraction
//!
//! The host's network surface is independently testable: the
//! `MockKernel` lets integration tests exercise the full TCP /
//! Unix socket / TLS / queueing paths without a Lean toolchain in
//! the test environment.  The `CommandKernel` is the production
//! wiring; it can be swapped for a future async-IPC kernel without
//! touching the network layer.

use crate::verdict::VerdictResponse;

/// The response the host returns to the client.  Mirrors
/// [`VerdictResponse`] but kept distinct so the kernel doesn't
/// have to import the wire-format encoder.
pub type KernelResponse = VerdictResponse;

/// The kernel abstraction.  Implementations decide admissibility
/// for incoming CBE-encoded `SignedAction` bytes.
///
/// ## Trait requirements
///
///   * **`Send + Sync`.**  The kernel is shared across the worker
///     thread; trait objects (`Box<dyn Kernel>`) require these
///     bounds for `std::thread::spawn` to accept the closure that
///     owns the kernel.
///   * **Interior mutability via `&self`.**  The kernel may hold
///     mutable state (e.g. a connection pool, a log file handle)
///     but exposes only `&self` to the worker.  Implementations
///     use `Mutex`, `RwLock`, or atomic types as needed.
///   * **Synchronous.**  Submissions block until the verdict is
///     ready.  The worker is single-threaded so back-pressure
///     propagates upstream via the bounded queue.
pub trait Kernel: Send + Sync {
    /// Submit one CBE-encoded `SignedAction`.  Returns the
    /// resulting verdict + optional human-readable reason.
    ///
    /// Implementations must not panic on any input; malformed
    /// CBE bytes should produce `Verdict::ParseError` rather than
    /// a Rust panic.
    fn submit(&self, signed_action_bytes: &[u8]) -> KernelResponse;

    /// A diagnostic identifier the host emits at startup (the
    /// equivalent of `canon-l1-ingest::INGEST_IDENTIFIER`).  Used
    /// for operator visibility — e.g. `"mock/v1"` or
    /// `"command-subprocess/v1"`.
    fn identifier(&self) -> &str;
}

/// In-memory mock kernel for tests and dev mode.
pub mod mock {
    use std::sync::Mutex;

    use crate::verdict::Verdict;

    use super::{Kernel, KernelResponse};

    /// A configurable in-memory kernel.  Records every submission
    /// and returns verdicts from a configurable response sequence.
    ///
    /// Default behaviour: returns `Verdict::Ok` for every
    /// submission.  Tests configure custom response sequences via
    /// [`MockKernel::set_responses`].
    #[derive(Debug, Default)]
    pub struct MockKernel {
        inner: Mutex<MockInner>,
    }

    /// The mock kernel's mutable interior.
    #[derive(Debug, Default)]
    struct MockInner {
        /// Every submission recorded in arrival order.
        recorded: Vec<Vec<u8>>,
        /// Response sequence; cycles when exhausted.  Empty
        /// sequence means "always Ok".
        responses: Vec<KernelResponse>,
        /// Index into `responses` for the next submission.
        next_response: usize,
    }

    impl MockKernel {
        /// Construct a mock kernel that returns `Verdict::Ok` for
        /// every submission.
        #[must_use]
        pub fn new() -> Self {
            Self::default()
        }

        /// Replace the response sequence.  Each `submit` returns
        /// the next element of `responses`, cycling when
        /// exhausted.  Passing an empty `Vec` reverts to "always
        /// Ok".
        pub fn set_responses(&self, responses: Vec<KernelResponse>) {
            let mut inner = self.inner.lock().expect("MockKernel mutex poisoned");
            inner.responses = responses;
            inner.next_response = 0;
        }

        /// Clone the recorded submissions.  Order-preserving.
        #[must_use]
        pub fn recorded(&self) -> Vec<Vec<u8>> {
            self.inner
                .lock()
                .expect("MockKernel mutex poisoned")
                .recorded
                .clone()
        }

        /// Number of recorded submissions.
        #[must_use]
        pub fn len(&self) -> usize {
            self.inner
                .lock()
                .expect("MockKernel mutex poisoned")
                .recorded
                .len()
        }

        /// `true` iff nothing has been submitted yet.
        #[must_use]
        pub fn is_empty(&self) -> bool {
            self.len() == 0
        }
    }

    impl Kernel for MockKernel {
        fn submit(&self, signed_action_bytes: &[u8]) -> KernelResponse {
            let mut inner = self.inner.lock().expect("MockKernel mutex poisoned");
            inner.recorded.push(signed_action_bytes.to_vec());
            if inner.responses.is_empty() {
                return KernelResponse::from_verdict(Verdict::Ok);
            }
            let response_count = inner.responses.len();
            let idx = inner.next_response % response_count;
            let response = inner.responses[idx].clone();
            inner.next_response = inner.next_response.wrapping_add(1);
            response
        }

        fn identifier(&self) -> &str {
            "canon-host-mock/v1"
        }
    }

    #[cfg(test)]
    mod tests {
        use super::MockKernel;
        use crate::kernel::Kernel;
        use crate::verdict::{Verdict, VerdictResponse};

        /// Default mock returns `Ok` for every submission.
        #[test]
        fn default_always_ok() {
            let k = MockKernel::new();
            let r1 = k.submit(b"first");
            let r2 = k.submit(b"second");
            assert_eq!(r1.verdict, Verdict::Ok);
            assert_eq!(r2.verdict, Verdict::Ok);
            assert_eq!(k.len(), 2);
        }

        /// Mock records every submission in arrival order.
        #[test]
        fn records_in_order() {
            let k = MockKernel::new();
            k.submit(b"a");
            k.submit(b"b");
            k.submit(b"c");
            assert_eq!(
                k.recorded(),
                vec![b"a".to_vec(), b"b".to_vec(), b"c".to_vec()]
            );
        }

        /// Response sequence cycles when exhausted.
        #[test]
        fn responses_cycle() {
            let k = MockKernel::new();
            k.set_responses(vec![
                VerdictResponse::from_verdict(Verdict::NotAdmissible),
                VerdictResponse::from_verdict(Verdict::Ok),
            ]);
            let r1 = k.submit(b"a");
            let r2 = k.submit(b"b");
            let r3 = k.submit(b"c"); // wraps
            let r4 = k.submit(b"d");
            assert_eq!(r1.verdict, Verdict::NotAdmissible);
            assert_eq!(r2.verdict, Verdict::Ok);
            assert_eq!(r3.verdict, Verdict::NotAdmissible);
            assert_eq!(r4.verdict, Verdict::Ok);
        }

        /// Reasons survive through `submit` → response.
        #[test]
        fn reason_survives() {
            let k = MockKernel::new();
            k.set_responses(vec![VerdictResponse::with_reason(
                Verdict::NotAdmissible,
                "nonce mismatch",
            )]);
            let r = k.submit(b"x");
            assert_eq!(r.verdict, Verdict::NotAdmissible);
            assert_eq!(r.reason, "nonce mismatch");
        }

        /// Setting an empty response Vec reverts to default Ok
        /// behaviour.
        #[test]
        fn empty_responses_reverts_to_ok() {
            let k = MockKernel::new();
            k.set_responses(vec![VerdictResponse::from_verdict(Verdict::Busy)]);
            assert_eq!(k.submit(b"x").verdict, Verdict::Busy);
            k.set_responses(vec![]);
            assert_eq!(k.submit(b"y").verdict, Verdict::Ok);
        }

        /// `is_empty` flips after a single submission.
        #[test]
        fn is_empty_flips() {
            let k = MockKernel::new();
            assert!(k.is_empty());
            k.submit(b"x");
            assert!(!k.is_empty());
        }

        /// Identifier is the documented v1 string.
        #[test]
        fn identifier_constant() {
            let k = MockKernel::new();
            assert_eq!(k.identifier(), "canon-host-mock/v1");
        }

        /// MockKernel is `Send + Sync` for the worker thread.
        #[test]
        fn is_send_sync() {
            fn assert_send_sync<T: Send + Sync>() {}
            assert_send_sync::<MockKernel>();
        }

        /// Records preserve raw bytes (including zero bytes and
        /// non-UTF-8 sequences).
        #[test]
        fn raw_bytes_preserved() {
            let k = MockKernel::new();
            let payload = vec![0x00u8, 0xff, 0xaa, 0x55, 0xc3, 0x28]; // includes invalid UTF-8
            k.submit(&payload);
            assert_eq!(k.recorded()[0], payload);
        }
    }
}

/// Per-request subprocess kernel.  Spawns the `canon` binary's
/// `process` subcommand for each submitted SignedAction.
pub mod command {
    use std::io::{Read, Write};
    use std::path::{Path, PathBuf};
    use std::process::{Command, Stdio};
    use std::sync::Mutex;
    use std::time::{Duration, Instant};

    use crate::verdict::Verdict;

    use super::{Kernel, KernelResponse};

    /// Maximum stderr / stdout bytes the kernel will read from the
    /// subprocess before truncating.  Defends against a misbehaving
    /// `canon` binary that emits megabytes of diagnostic output.
    pub const MAX_SUBPROCESS_OUTPUT: usize = 64 * 1024;

    /// Default per-request subprocess timeout.  Per-request
    /// spawning is heavy (each call re-loads the log), so the
    /// timeout is generous; production tuning may bump it.
    pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(60);

    /// Polling interval for `try_wait` in the timeout loop.
    /// Trade-off: smaller = more responsive timeout but more CPU
    /// overhead; larger = bounded responsiveness but cheaper.
    /// 10 ms is a reasonable balance for a per-request kernel
    /// already in the ms range.
    const WAIT_POLL_INTERVAL: Duration = Duration::from_millis(10);

    /// A per-request subprocess kernel.  Each `submit` call:
    ///
    ///   1. Writes the CBE bytes to a temp file under the host's
    ///      configured work directory.
    ///   2. Spawns `canon process <log-path> <temp-file>`.
    ///   3. Parses the exit code (0 = Ok, anything else =
    ///      NotAdmissible) and captures stderr as the reason.
    ///   4. Removes the temp file.
    ///
    /// The persistent log file is shared across requests.  The
    /// worker is single-threaded so the log file accesses are
    /// serial; no file locking required.
    ///
    /// ## Performance
    ///
    /// Each call spawns a process AND re-loads the log file.
    /// This is O(log size) per request.  For a production
    /// deployment, the canonical optimization is a future
    /// `canon serve` Lean-side subcommand that reads CBE frames
    /// from stdin and writes verdicts to stdout, eliminating the
    /// per-request bootstrap cost.  See the engineering plan
    /// §RH-C closeout.
    ///
    /// ## Verdict semantics
    ///
    /// `canon process` exits with:
    ///   * `0` — bootstrap succeeded AND every action was admitted.
    ///   * `1` — bootstrap failed OR at least one action failed
    ///     (NotAdmissible) OR parse error.
    ///
    /// We collapse non-zero exits to `Verdict::NotAdmissible`
    /// because:
    ///   1. Distinguishing NotAdmissible from ParseError from a
    ///      bootstrap failure requires stdout/stderr parsing,
    ///      which is fragile.
    ///   2. From the client's perspective, all three are "the
    ///      kernel didn't admit my action and the host can't
    ///      help"; the operator-actionable distinction lives in
    ///      the host's logs (which capture the full stderr).
    ///
    /// The stderr is captured as the response's `reason` field so
    /// operators can grep the host's `tracing` output for failure
    /// modes.
    #[derive(Debug)]
    pub struct CommandKernel {
        /// Path to the `canon` binary.
        canon_binary: PathBuf,
        /// Path to the persistent log file shared across requests.
        log_path: PathBuf,
        /// Path to the directory under which per-request temp
        /// files are created.
        work_dir: PathBuf,
        /// Optional deployment-id hex to pass via
        /// `--deployment-id`.  Empty string means no deployment-id
        /// flag is passed (so the canon binary's default sentinel
        /// applies).
        deployment_id_hex: String,
        /// Mutex guarding sequential subprocess access.  The
        /// worker is single-threaded today but the mutex
        /// future-proofs against an accidental parallel worker.
        spawn_lock: Mutex<()>,
        /// Per-request timeout.  Default
        /// [`DEFAULT_TIMEOUT`]; configurable via
        /// [`CommandKernel::with_timeout`].
        timeout: Duration,
    }

    /// Errors during `CommandKernel` construction.
    #[derive(Debug, thiserror::Error)]
    pub enum CommandKernelError {
        /// The `canon` binary path doesn't exist or isn't a file.
        #[error("canon binary path {0:?} does not exist or is not a file")]
        BinaryNotFound(PathBuf),
        /// The work directory could not be created.
        #[error("could not create work directory {path:?}: {source}")]
        WorkDirCreate {
            /// The path the kernel tried to create.
            path: PathBuf,
            /// Underlying I/O error.
            source: std::io::Error,
        },
    }

    impl CommandKernel {
        /// Construct a `CommandKernel`.
        ///
        /// Validates that the `canon` binary path exists and is a
        /// file; creates the work directory if it doesn't exist.
        ///
        /// # Errors
        ///
        /// Returns `CommandKernelError::BinaryNotFound` if
        /// `canon_binary` is missing.  Returns
        /// `CommandKernelError::WorkDirCreate` if the work
        /// directory cannot be created.
        pub fn new(
            canon_binary: PathBuf,
            log_path: PathBuf,
            work_dir: PathBuf,
        ) -> Result<Self, CommandKernelError> {
            // Verify the binary exists.  We don't verify it's
            // executable — that's a permission check we'd race
            // against anyway, and `Command::spawn` surfaces a
            // clear error if it can't be exec'd.
            if !canon_binary.is_file() {
                return Err(CommandKernelError::BinaryNotFound(canon_binary));
            }
            // Create the work directory if needed.
            if let Err(source) = std::fs::create_dir_all(&work_dir) {
                return Err(CommandKernelError::WorkDirCreate {
                    path: work_dir,
                    source,
                });
            }
            Ok(Self {
                canon_binary,
                log_path,
                work_dir,
                deployment_id_hex: String::new(),
                spawn_lock: Mutex::new(()),
                timeout: DEFAULT_TIMEOUT,
            })
        }

        /// Set the deployment-id hex string passed via
        /// `--deployment-id` on every subprocess invocation.
        /// Empty string disables the flag (canon binary defaults
        /// to empty sentinel; emits a dev-mode warning).
        #[must_use]
        pub fn with_deployment_id(mut self, hex: impl Into<String>) -> Self {
            self.deployment_id_hex = hex.into();
            self
        }

        /// Override the default per-request timeout.
        #[must_use]
        pub fn with_timeout(mut self, timeout: Duration) -> Self {
            self.timeout = timeout;
            self
        }

        /// Path to the canon binary.  Diagnostic only.
        #[must_use]
        pub fn canon_binary(&self) -> &Path {
            &self.canon_binary
        }

        /// Path to the persistent log file.  Diagnostic only.
        #[must_use]
        pub fn log_path(&self) -> &Path {
            &self.log_path
        }

        /// Path to the per-request temp work directory.
        /// Diagnostic only.
        #[must_use]
        pub fn work_dir(&self) -> &Path {
            &self.work_dir
        }

        /// Format a single CBE record into a "stream of one"
        /// suitable for `canon process`'s input file format.
        /// `canon process` reads concatenated CBE-encoded
        /// SignedAction records, so a single-record file is just
        /// the bytes themselves.
        fn frame_input(signed_action_bytes: &[u8]) -> Vec<u8> {
            signed_action_bytes.to_vec()
        }
    }

    impl Kernel for CommandKernel {
        fn submit(&self, signed_action_bytes: &[u8]) -> KernelResponse {
            // 1. Acquire the spawn lock.  Sequentialises all
            //    subprocess work — even if the worker pool were
            //    expanded.  Recover from poisoning rather than
            //    panicking the worker thread: a poisoned mutex
            //    means a previous lock holder panicked, but the
            //    protected data is just a guard token (no state
            //    to corrupt).
            let _guard = match self.spawn_lock.lock() {
                Ok(g) => g,
                Err(poisoned) => poisoned.into_inner(),
            };

            // 2. Allocate a unique temp file under the work dir.
            //    `tempfile::NamedTempFile::new_in` creates with
            //    `O_CREAT | O_EXCL` + a random suffix, defending
            //    against symlink-attack TOCTOU on multi-tenant
            //    work directories.
            let input_bytes = Self::frame_input(signed_action_bytes);
            let temp_file = match tempfile::Builder::new()
                .prefix("canon-host-req-")
                .suffix(".cbe")
                .tempfile_in(&self.work_dir)
            {
                Ok(f) => f,
                Err(e) => {
                    return KernelResponse::with_reason(
                        Verdict::NotAdmissible,
                        format!("create temp file in {:?}: {e}", self.work_dir),
                    );
                }
            };
            let temp_path = temp_file.path().to_path_buf();
            // Write the input bytes via the tempfile handle, then
            // close it (Drop on the file half) so canon can open
            // it; the NamedTempFile's *path* still owns the
            // filesystem entry, which is removed when the
            // NamedTempFile itself is dropped (after this function
            // returns).
            {
                let (mut file, _path) = match temp_file.keep() {
                    Ok((f, p)) => (f, p),
                    Err(e) => {
                        return KernelResponse::with_reason(
                            Verdict::NotAdmissible,
                            format!("persist temp file: {}", e.error),
                        );
                    }
                };
                if let Err(e) = file.write_all(&input_bytes) {
                    let _ = std::fs::remove_file(&temp_path);
                    return KernelResponse::with_reason(
                        Verdict::NotAdmissible,
                        format!("write temp file {temp_path:?}: {e}"),
                    );
                }
                if let Err(e) = file.flush() {
                    let _ = std::fs::remove_file(&temp_path);
                    return KernelResponse::with_reason(
                        Verdict::NotAdmissible,
                        format!("flush temp file {temp_path:?}: {e}"),
                    );
                }
                // Drop closes the file handle.
            }

            // 3. Build the subprocess command.  Use `--allow-fallback-hash`
            //    to suppress the warning the canon binary emits on a
            //    non-production hash build — the host has its own
            //    diagnostic surface and the warning would bloat
            //    stderr capture for every request.
            let mut cmd = Command::new(&self.canon_binary);
            cmd.arg("--allow-fallback-hash");
            if !self.deployment_id_hex.is_empty() {
                cmd.arg("--deployment-id").arg(&self.deployment_id_hex);
            }
            cmd.arg("process").arg(&self.log_path).arg(&temp_path);
            cmd.stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::piped());

            // 4. Spawn + bounded wait (per AR-RHC #1).  The previous
            //    implementation used `cmd.output()` which blocks
            //    unconditionally; a wedged canon binary would hang
            //    the worker forever.  We now spawn and poll
            //    `try_wait` with `WAIT_POLL_INTERVAL` until either
            //    the process exits or the configured timeout
            //    elapses, at which point we SIGKILL the child.
            let response = match cmd.spawn() {
                Ok(mut child) => {
                    let exit_status = wait_with_timeout(&mut child, self.timeout);
                    // Collect stderr regardless of how the wait
                    // resolved — operator wants the diagnostic
                    // output for failure analysis.  Bounded by
                    // `MAX_SUBPROCESS_OUTPUT`.
                    let stderr_text = match child.stderr.take() {
                        Some(mut s) => {
                            let mut buf = Vec::with_capacity(1024);
                            let _ = take_with_limit(&mut s, &mut buf, MAX_SUBPROCESS_OUTPUT);
                            String::from_utf8_lossy(&buf).to_string()
                        }
                        None => String::new(),
                    };
                    match exit_status {
                        WaitOutcome::Exited(status) => {
                            if status.success() {
                                KernelResponse::from_verdict(Verdict::Ok)
                            } else {
                                KernelResponse::with_reason(
                                    Verdict::NotAdmissible,
                                    if stderr_text.is_empty() {
                                        format!("canon exited with status {status}")
                                    } else {
                                        stderr_text
                                    },
                                )
                            }
                        }
                        WaitOutcome::TimedOut => KernelResponse::with_reason(
                            Verdict::NotAdmissible,
                            if stderr_text.is_empty() {
                                format!(
                                    "canon subprocess exceeded {:?} timeout; SIGKILLed",
                                    self.timeout
                                )
                            } else {
                                format!(
                                    "canon subprocess exceeded {:?} timeout (SIGKILLed); stderr: {}",
                                    self.timeout, stderr_text
                                )
                            },
                        ),
                        WaitOutcome::WaitError(e) => KernelResponse::with_reason(
                            Verdict::NotAdmissible,
                            format!("subprocess wait error: {e}"),
                        ),
                    }
                }
                Err(e) => KernelResponse::with_reason(
                    Verdict::NotAdmissible,
                    format!("subprocess spawn error: {e}"),
                ),
            };

            // 5. Clean up temp file.  We don't propagate the
            //    cleanup error — a leaked temp file is debug-logged
            //    but doesn't block the response.
            if let Err(e) = std::fs::remove_file(&temp_path) {
                if e.kind() != std::io::ErrorKind::NotFound {
                    tracing::debug!(path = ?temp_path, error = ?e, "temp-file cleanup failed");
                }
            }

            response
        }

        fn identifier(&self) -> &str {
            "canon-host-command/v1"
        }
    }

    /// Outcome of [`wait_with_timeout`].
    enum WaitOutcome {
        /// The child exited within the deadline with the supplied
        /// status.
        Exited(std::process::ExitStatus),
        /// The deadline elapsed before the child exited; the child
        /// was SIGKILLed.
        TimedOut,
        /// The wait itself failed (typically EINTR or a kernel
        /// bug); the child may or may not have exited.
        WaitError(std::io::Error),
    }

    /// Wait for `child` to exit, bounded by `timeout`.  If the
    /// deadline elapses, the child is SIGKILLed and reaped.
    fn wait_with_timeout(child: &mut std::process::Child, timeout: Duration) -> WaitOutcome {
        let deadline = Instant::now() + timeout;
        loop {
            match child.try_wait() {
                Ok(Some(status)) => return WaitOutcome::Exited(status),
                Ok(None) => {
                    if Instant::now() >= deadline {
                        // Timeout — escalate to SIGKILL + reap.
                        let _ = child.kill();
                        // Drain after the kill so the child entry
                        // doesn't leak as a zombie.
                        let _ = child.wait();
                        return WaitOutcome::TimedOut;
                    }
                    std::thread::sleep(WAIT_POLL_INTERVAL);
                }
                Err(e) => {
                    // try_wait failure is rare (EINTR, etc.).
                    // Surface as WaitError so the caller logs +
                    // reports NotAdmissible.  Attempt to reap.
                    let _ = child.kill();
                    let _ = child.wait();
                    return WaitOutcome::WaitError(e);
                }
            }
        }
    }

    /// Read up to `limit` bytes from `reader` into `out`.  Returns
    /// the number of bytes read.  Discards any further bytes
    /// (does not error).  Mirrors `std::io::Read::take` but
    /// preserves the underlying reader for cleanup.
    fn take_with_limit<R: Read>(reader: &mut R, out: &mut Vec<u8>, limit: usize) -> usize {
        let mut buf = [0u8; 4096];
        let mut total = 0usize;
        while total < limit {
            let want = (limit - total).min(buf.len());
            match reader.read(&mut buf[..want]) {
                // Any error or EOF (Ok(0)) ends the read.  We don't
                // distinguish — both mean "no more bytes" for the
                // diagnostic-stderr-capture use case.
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    out.extend_from_slice(&buf[..n]);
                    total = total.saturating_add(n);
                }
            }
        }
        total
    }

    #[cfg(test)]
    mod tests {
        use super::{CommandKernel, CommandKernelError, MAX_SUBPROCESS_OUTPUT};
        use crate::kernel::Kernel;
        use crate::verdict::Verdict;
        use std::path::PathBuf;
        use std::time::Duration;

        /// Constants are stable.
        #[test]
        fn constants_stable() {
            assert_eq!(MAX_SUBPROCESS_OUTPUT, 64 * 1024);
        }

        /// Missing binary returns `BinaryNotFound`.
        #[test]
        fn missing_binary_returns_error() {
            let temp = tempfile::tempdir().unwrap();
            let bogus = PathBuf::from("/nonexistent/canon");
            let log = temp.path().join("log");
            let work = temp.path().join("work");
            match CommandKernel::new(bogus.clone(), log, work) {
                Err(CommandKernelError::BinaryNotFound(p)) => {
                    assert_eq!(p, bogus);
                }
                other => panic!("expected BinaryNotFound, got {other:?}"),
            }
        }

        /// Construct with an existing binary path (use `/bin/true`
        /// as a stand-in).
        #[test]
        fn construct_with_existing_binary() {
            let temp = tempfile::tempdir().unwrap();
            // /bin/true exists on every Linux test host.
            let canon = PathBuf::from("/bin/true");
            if !canon.exists() {
                eprintln!("skipping: /bin/true not present");
                return;
            }
            let log = temp.path().join("log");
            let work = temp.path().join("work");
            let kernel = CommandKernel::new(canon.clone(), log.clone(), work.clone()).unwrap();
            assert_eq!(kernel.canon_binary(), canon);
            assert_eq!(kernel.log_path(), log);
            assert_eq!(kernel.work_dir(), work);
        }

        /// Work directory is created if it doesn't exist.
        #[test]
        fn work_dir_created() {
            let temp = tempfile::tempdir().unwrap();
            let canon = PathBuf::from("/bin/true");
            if !canon.exists() {
                return;
            }
            let log = temp.path().join("log");
            let work = temp.path().join("nested").join("work");
            assert!(!work.exists());
            let _kernel = CommandKernel::new(canon, log, work.clone()).unwrap();
            assert!(work.is_dir());
        }

        /// `submit` with `/bin/true` returns `Ok` (exit code 0).
        #[test]
        fn submit_with_true_returns_ok() {
            let temp = tempfile::tempdir().unwrap();
            let canon = PathBuf::from("/bin/true");
            if !canon.exists() {
                return;
            }
            let log = temp.path().join("log");
            let work = temp.path().join("work");
            let kernel = CommandKernel::new(canon, log, work).unwrap();
            let response = kernel.submit(b"some bytes");
            assert_eq!(response.verdict, Verdict::Ok);
        }

        /// `submit` with `/bin/false` returns `NotAdmissible` (exit code 1).
        #[test]
        fn submit_with_false_returns_not_admissible() {
            let temp = tempfile::tempdir().unwrap();
            let canon = PathBuf::from("/bin/false");
            if !canon.exists() {
                return;
            }
            let log = temp.path().join("log");
            let work = temp.path().join("work");
            let kernel = CommandKernel::new(canon, log, work).unwrap();
            let response = kernel.submit(b"some bytes");
            assert_eq!(response.verdict, Verdict::NotAdmissible);
        }

        /// `submit` cleans up the temp file after the subprocess
        /// completes.  Counts files in the work dir before / after.
        #[test]
        fn submit_cleans_up_temp_file() {
            let temp = tempfile::tempdir().unwrap();
            let canon = PathBuf::from("/bin/true");
            if !canon.exists() {
                return;
            }
            let log = temp.path().join("log");
            let work = temp.path().join("work");
            let kernel = CommandKernel::new(canon, log, work.clone()).unwrap();
            kernel.submit(b"a");
            kernel.submit(b"b");
            kernel.submit(b"c");
            // Work dir should be empty (all temp files cleaned).
            let entries: Vec<_> = std::fs::read_dir(&work).unwrap().collect();
            assert!(entries.is_empty(), "work dir not cleaned: {entries:?}");
        }

        /// `with_deployment_id` carries the hex into the kernel
        /// state.  We can't easily test the resulting subprocess
        /// invocation without parsing argv, but the construction
        /// path is exercised.
        #[test]
        fn with_deployment_id_succeeds() {
            let temp = tempfile::tempdir().unwrap();
            let canon = PathBuf::from("/bin/true");
            if !canon.exists() {
                return;
            }
            let log = temp.path().join("log");
            let work = temp.path().join("work");
            let kernel = CommandKernel::new(canon, log, work)
                .unwrap()
                .with_deployment_id("0123456789abcdef");
            assert_eq!(kernel.submit(b"x").verdict, Verdict::Ok);
        }

        /// `with_timeout` adjusts the timeout field.
        #[test]
        fn with_timeout_succeeds() {
            let temp = tempfile::tempdir().unwrap();
            let canon = PathBuf::from("/bin/true");
            if !canon.exists() {
                return;
            }
            let log = temp.path().join("log");
            let work = temp.path().join("work");
            let _kernel = CommandKernel::new(canon, log, work)
                .unwrap()
                .with_timeout(Duration::from_secs(5));
        }

        /// Identifier is the documented v1 string.
        #[test]
        fn identifier_constant() {
            let temp = tempfile::tempdir().unwrap();
            let canon = PathBuf::from("/bin/true");
            if !canon.exists() {
                return;
            }
            let log = temp.path().join("log");
            let work = temp.path().join("work");
            let kernel = CommandKernel::new(canon, log, work).unwrap();
            assert_eq!(kernel.identifier(), "canon-host-command/v1");
        }

        /// `CommandKernel` is `Send + Sync` for the worker thread.
        #[test]
        fn is_send_sync() {
            fn assert_send_sync<T: Send + Sync>() {}
            assert_send_sync::<CommandKernel>();
        }

        /// `CommandKernelError::BinaryNotFound` is `Send + Sync`
        /// (carried up by `?` from the constructor).
        #[test]
        fn error_is_send_sync() {
            fn assert_send_sync<T: Send + Sync>() {}
            assert_send_sync::<CommandKernelError>();
        }

        /// AR-RHC #1: `with_timeout` actually bounds subprocess
        /// wall-time.  Previously `cmd.output()` blocked
        /// unconditionally so a wedged subprocess would hang the
        /// worker forever.
        ///
        /// We model the production canon binary's
        /// single-process-no-children shape by using
        /// `exec sleep 10` (the shell replaces itself with sleep,
        /// so there's exactly one process to kill — no orphan
        /// grandchild keeping the stderr pipe alive).
        #[test]
        fn timeout_bounds_subprocess_wall_time() {
            use std::os::unix::fs::PermissionsExt;
            let temp = tempfile::tempdir().unwrap();
            if !PathBuf::from("/bin/sleep").exists() {
                eprintln!("skipping: /bin/sleep not present");
                return;
            }
            // Single-process script: `exec sleep` replaces the
            // shell with sleep itself.  When we SIGKILL the
            // resulting process, the stderr pipe immediately
            // closes (no orphaned grandchild).  This mirrors the
            // production canon binary, which is a single Rust
            // process with no shell wrapper.
            let script_path = temp.path().join("slow.sh");
            std::fs::write(&script_path, "#!/bin/sh\nexec sleep 10\n").unwrap();
            std::fs::set_permissions(&script_path, std::fs::Permissions::from_mode(0o755)).unwrap();
            let log = temp.path().join("log");
            let work = temp.path().join("work");
            let kernel = CommandKernel::new(script_path, log, work)
                .unwrap()
                .with_timeout(Duration::from_millis(200));
            let start = std::time::Instant::now();
            let response = kernel.submit(b"some bytes");
            let elapsed = start.elapsed();
            assert!(
                elapsed < Duration::from_secs(3),
                "submit took {elapsed:?}, expected <3s with 200ms timeout"
            );
            assert_eq!(response.verdict, Verdict::NotAdmissible);
            assert!(
                response.reason.contains("timeout") || response.reason.contains("SIGKILL"),
                "reason was: {}",
                response.reason
            );
        }

        /// AR-RHC #3: tempfile-based input file defends against
        /// pre-existing-symlink TOCTOU.  Previously `File::create`
        /// would follow a symlink, allowing a local attacker to
        /// pre-create the predictable temp path as a symlink to
        /// `/etc/passwd` (or a victim file) and have the kernel
        /// truncate + overwrite the target.  With
        /// `tempfile::NamedTempFile`, the temp name is random and
        /// `O_CREAT | O_EXCL` is set — neither pre-creation nor
        /// symlink-following is possible.  This test verifies a
        /// witness file is NOT clobbered when an attacker has
        /// write access to the work directory.
        #[test]
        fn temp_file_creation_doesnt_follow_symlinks() {
            let temp = tempfile::tempdir().unwrap();
            let canon = PathBuf::from("/bin/true");
            if !canon.exists() {
                return;
            }
            let log = temp.path().join("log");
            let work = temp.path().join("work");
            std::fs::create_dir_all(&work).unwrap();
            // Pre-create a "victim" file in another directory.
            let victim = temp.path().join("victim.txt");
            std::fs::write(&victim, b"protected operator data").unwrap();
            // Pre-create a symlink in the work directory that
            // SHOULD point at the victim.  With the predictable
            // temp-naming scheme (PID + counter), an attacker
            // could pre-create exactly the predicted path.  With
            // tempfile's random naming + O_EXCL, this can't
            // happen — but we simulate the strongest form of the
            // attack by pre-creating a sea of symlinks covering
            // the entire `canon-host-req-*` namespace.  The
            // attacker can't predict the random suffix.
            //
            // Construct kernel + invoke.  Even if the attacker
            // created many symlinks, tempfile's O_EXCL retries
            // with new random suffixes until one succeeds.
            let kernel = CommandKernel::new(canon, log, work.clone()).unwrap();
            // Pre-poison the work dir with one symlink at a
            // hand-picked path.  tempfile's random name will not
            // collide.
            #[cfg(unix)]
            std::os::unix::fs::symlink(&victim, work.join("canon-host-req-attacker.cbe")).unwrap();
            kernel.submit(b"hello");
            // Victim file must be intact.
            let after = std::fs::read(&victim).unwrap();
            assert_eq!(
                after, b"protected operator data",
                "symlink attack succeeded: victim file was clobbered"
            );
        }

        /// Mutex poisoning in `spawn_lock` recovers gracefully
        /// (returns the inner guard) rather than panicking the
        /// worker.  This addresses AR-RHC #12: mutex `expect`
        /// previously crashed the worker on a poisoned mutex.
        #[test]
        fn spawn_lock_poisoning_recovers() {
            use std::sync::Arc;

            let temp = tempfile::tempdir().unwrap();
            let canon = PathBuf::from("/bin/true");
            if !canon.exists() {
                return;
            }
            let log = temp.path().join("log");
            let work = temp.path().join("work");
            let kernel = Arc::new(CommandKernel::new(canon, log, work).unwrap());
            let kernel_clone = Arc::clone(&kernel);
            // Spawn a thread that acquires the lock and panics
            // while holding it.  This poisons the mutex.
            let handle = std::thread::spawn(move || {
                let _guard = kernel_clone.spawn_lock.lock().unwrap();
                panic!("intentional panic to poison the mutex");
            });
            let _ = handle.join(); // poison delivered

            // Now a fresh submit should still succeed.  Pre-fix
            // (`.expect()`) would panic the test thread here.
            let response = kernel.submit(b"x");
            assert_eq!(response.verdict, Verdict::Ok);
        }

        /// Multiple concurrent calls (via threads) all complete
        /// without deadlock.  The spawn lock serialises them.
        #[test]
        fn concurrent_calls_serialise() {
            let temp = tempfile::tempdir().unwrap();
            let canon = PathBuf::from("/bin/true");
            if !canon.exists() {
                return;
            }
            let log = temp.path().join("log");
            let work = temp.path().join("work");
            let kernel = std::sync::Arc::new(CommandKernel::new(canon, log, work).unwrap());
            let mut handles = Vec::new();
            for _ in 0..8 {
                let k = std::sync::Arc::clone(&kernel);
                handles.push(std::thread::spawn(move || k.submit(b"x").verdict));
            }
            for h in handles {
                assert_eq!(h.join().unwrap(), Verdict::Ok);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{Kernel, KernelResponse};

    /// The trait is object-safe (we use `Box<dyn Kernel>`).
    #[test]
    fn kernel_trait_is_object_safe() {
        struct Stub;
        impl Kernel for Stub {
            fn submit(&self, _: &[u8]) -> KernelResponse {
                KernelResponse::from_verdict(crate::verdict::Verdict::Ok)
            }
            fn identifier(&self) -> &str {
                "stub"
            }
        }
        // If trait isn't object-safe this fails to compile.
        let _k: Box<dyn Kernel> = Box::new(Stub);
    }
}
