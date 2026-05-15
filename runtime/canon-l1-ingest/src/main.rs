// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! `canon-l1-ingest` — RH-B skeleton entry-point.
//!
//! The implementing work unit (`docs/planning/rust_host_runtime_plan.md`
//! §RH-B) replaces this `main` with the L1 event-watcher daemon
//! that translates Ethereum `Deposit` / `IdentityRegistered` /
//! `WithdrawalFinalized` events into `SignedAction`s via the
//! bridge-actor signing flow and forwards them to `canon-host` for
//! admission.

use canon_cli_common::exit::OperatorExitCode;

fn main() {
    eprintln!(
        "canon-l1-ingest: RH-B not yet implemented; see docs/planning/rust_host_runtime_plan.md §RH-B"
    );
    OperatorExitCode::NotImplemented.terminate();
}
