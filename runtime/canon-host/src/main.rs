// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! `canon-host` — RH-C skeleton entry-point.
//!
//! The implementing work unit (`docs/planning/rust_host_runtime_plan.md`
//! §RH-C) replaces this `main` with the production listener that:
//!
//!   * Accepts length-prefixed CBE `SignedAction` requests over TCP
//!     (optional TLS via `rustls`) or Unix socket.
//!   * Spawns and supervises the Lean `canon` subprocess; relays
//!     each request over the existing Lean-side Unix-socket
//!     interface (`LegalKernel/Runtime/Loop.lean`).
//!   * Maintains a bounded mpsc queue with `busy` backpressure
//!     verdict (wire-format extension documented in `docs/abi.md`
//!     §10 by RH-C.5).
//!
//! RH-H ships the binary as a skeleton that prints the work-unit
//! status on stderr and exits with [`OperatorExitCode::NotImplemented`]
//! so deployments cannot mistake the skeleton for a running host.

use canon_cli_common::exit::OperatorExitCode;

fn main() {
    eprintln!(
        "canon-host: RH-C not yet implemented; see docs/planning/rust_host_runtime_plan.md §RH-C"
    );
    OperatorExitCode::NotImplemented.terminate();
}
