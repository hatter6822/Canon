// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! Binary entry-point for `canon-faultproof-observer`.
//!
//! Wires the CLI to the library's [`canon_faultproof_observer::observer::Observer`]:
//! parse CLI → initialise logging → load keystore → open
//! persistence → construct the L1 source → construct the
//! observer → run the loop until shutdown.
//!
//! Exit codes follow the
//! [`canon_cli_common::exit::OperatorExitCode`] discipline:
//!
//!   * 0 — clean shutdown (stop signal honoured).
//!   * 1 — general failure (libc default).
//!   * 2 — operator-actionable failure (config, deep re-org,
//!     crypto failure, invariant violation).
//!   * 69 — external service unavailable (L1 RPC permanently
//!     malformed).
//!   * 75 — transient failure (exhausted retries).

use std::process::ExitCode;

use canon_cli_common::exit::OperatorExitCode;
use canon_l1_ingest::key::BridgeActorKey;
use canon_l1_ingest::source::json_rpc::JsonRpcL1Source;
use tracing::{error, info};

use canon_faultproof_observer::config::{self, CliConfig, CliError};
use canon_faultproof_observer::error::ObserverError;
use canon_faultproof_observer::observer::{Observer, ObserverConfig};
use canon_faultproof_observer::persistence::Persistence;
use canon_faultproof_observer::strategy::MemoryTruthOracle;
use canon_faultproof_observer::submitter::mock::MockSubmitter;
use canon_faultproof_observer::watcher::WatcherConfig;

/// Convert an [`OperatorExitCode`] to the `u8` shape `ExitCode`
/// requires.  All defined exit codes fit in `u8` by construction
/// (the largest is 75), so the conversion is total.
fn exit_code_u8(code: OperatorExitCode) -> u8 {
    u8::try_from(code.as_i32()).unwrap_or(1)
}

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().collect();
    match CliConfig::parse_args(argv) {
        Ok(cfg) => match run(&cfg) {
            Ok(()) => ExitCode::from(exit_code_u8(OperatorExitCode::Success)),
            Err(e) => {
                error!(err = %e, "observer exited with error");
                ExitCode::from(exit_code_u8(e.exit_code()))
            }
        },
        Err(CliError::HelpRequested) => {
            config::print_help();
            ExitCode::from(exit_code_u8(OperatorExitCode::Success))
        }
        Err(CliError::VersionRequested) => {
            config::print_version();
            ExitCode::from(exit_code_u8(OperatorExitCode::Success))
        }
        Err(e) => {
            eprintln!("canon-faultproof-observer: CLI error: {e}");
            eprintln!("Run with --help for usage.");
            ExitCode::from(exit_code_u8(OperatorExitCode::OperatorAction))
        }
    }
}

/// Run the observer loop with the parsed CLI config.
///
/// # Errors
///
/// See [`ObserverError`].
#[allow(clippy::needless_pass_by_value)] // top-level CLI entry
fn run(cfg: &CliConfig) -> Result<(), ObserverError> {
    // Initialise logging.  `canon_cli_common::logging::init`
    // reads RUST_LOG if set; otherwise falls back to the
    // supplied default level.  We map `--log-level` to a
    // `tracing::Level` (info / debug / warn / error / trace).
    let default_level = parse_tracing_level(&cfg.log_level);
    canon_cli_common::logging::init(default_level)
        .map_err(|e| ObserverError::Config(format!("logging init: {e}")))?;

    info!(
        version = canon_faultproof_observer::VERSION,
        identifier = canon_faultproof_observer::OBSERVER_IDENTIFIER,
        protocol_version = canon_faultproof_observer::PROTOCOL_VERSION,
        "canon-faultproof-observer starting",
    );

    // Load the keystore.  We use canon-l1-ingest's
    // BridgeActorKey wrapper (which holds the private bytes in
    // Zeroizing<[u8; 32]>).  The current submitter
    // implementation is the mock (the JSON-RPC submitter is
    // deferred RH-G follow-up work; see lib.rs's "What this
    // RH-G landing ships").
    let _signing_key = BridgeActorKey::from_file(&cfg.keystore_path).map_err(|e| {
        ObserverError::Crypto(format!("loading keystore at {:?}: {e}", cfg.keystore_path))
    })?;
    // Defence-in-depth: don't let the signing key leak via
    // tracing output by including it in any structured logs.
    // The Debug impl on BridgeActorKey redacts the private
    // bytes, but we still keep the binding behind `_`.

    // Open the persistence layer.
    let persistence = Persistence::open(&cfg.storage_path).map_err(|e| {
        ObserverError::Storage(canon_storage::storage::StorageError::Other(format!(
            "opening persistence at {:?}: {e}",
            cfg.storage_path
        )))
    })?;

    // Construct the L1 source.  Uses canon-l1-ingest's
    // hand-rolled HTTP JSON-RPC client (no async runtime).
    let source = JsonRpcL1Source::new(cfg.l1_rpc.clone())
        .map_err(|e| ObserverError::Config(format!("L1 RPC URL parse: {e}")))?;

    // Construct the watcher config from CLI.
    let watcher_cfg = WatcherConfig {
        game_contract: cfg.game_contract,
        state_root_submission_contract: cfg.state_root_contract,
        confirmation_depth: cfg.confirmation_depth,
        reorg_window_capacity: cfg.reorg_window as usize,
        blocks_per_iteration: cfg.blocks_per_iteration,
    };

    // Construct the observer config.
    let observer_cfg = ObserverConfig {
        watcher: watcher_cfg,
        poll_interval: cfg.poll_interval,
        play_as: cfg.play_as,
        deployment_id: cfg.deployment_id,
    };

    // Build the truth oracle.  In the v1 binary landing, this
    // is the empty `MemoryTruthOracle`.  Production deployments
    // wire up a `SubprocessTruthOracle` that shells out to
    // `canon --replay-up-to <idx>` — that subcommand is deferred
    // Lean-side work (mirrors the pattern for RH-D's
    // `extract-events`).  The observer detects an empty oracle
    // via `HonestMoveError::TruthOracleMissed` at move time and
    // logs a clear "deferring move" warning; no incorrect moves
    // are submitted.
    let oracle = MemoryTruthOracle::new();

    // Build the submitter.  Mock submitter for v1; production
    // wire-up is RH-G follow-up.  The mock records every move
    // for inspection and reports them as confirmed; this lets
    // operators observe the observer's intent without
    // committing to an L1 broadcast.
    let submitter = MockSubmitter::new();

    let mut observer = Observer::new(observer_cfg, source, submitter, oracle, persistence)?;

    // The --start-block override is a privileged operation that
    // overrides the persisted-cursor resume point.  Operators
    // use this to catch-up the observer from a specific historic
    // block on a fresh deployment (otherwise the fresh-watcher
    // jumps to the confirmed head and silently skips historic
    // games — see the documented "cold-start" behaviour in
    // lib.rs's "Security properties").
    //
    // The override is documented as advanced operator-only.  An
    // operator that supplies the wrong block number will cause
    // the observer to re-process events (idempotent at the
    // event-dispatch boundary) or to skip events (only if the
    // override is higher than the current cursor).  We log the
    // override loudly so the operator-supervisor sees it.
    if let Some(start) = cfg.start_block {
        observer.set_start_block(start);
        info!(
            start_block = start,
            "watcher cursor overridden via --start-block (operator-supplied resume point)",
        );
    }

    // Note: SIGTERM / SIGINT handling.  The std library doesn't
    // expose POSIX signal handling portably and we intentionally
    // don't take a new `ctrlc` dependency for this binary.  The
    // process responds to SIGTERM via libc's default handler
    // (which terminates the process; canon-storage's WAL mode
    // tolerates abrupt termination).  Operators that need
    // orderly shutdown can use a supervisor that sends a
    // sentinel value via storage cell or via a future
    // `--listen-shutdown <socket>` flag.

    observer.run()
}

/// Map the `--log-level` string to a `tracing::Level`.  Unknown
/// values fall back to `Info` with a stderr warning.
fn parse_tracing_level(s: &str) -> tracing::Level {
    match s.to_ascii_lowercase().as_str() {
        "trace" => tracing::Level::TRACE,
        "debug" => tracing::Level::DEBUG,
        "info" => tracing::Level::INFO,
        "warn" => tracing::Level::WARN,
        "error" => tracing::Level::ERROR,
        other => {
            eprintln!(
                "canon-faultproof-observer: unknown --log-level '{other}'; defaulting to 'info'"
            );
            tracing::Level::INFO
        }
    }
}
