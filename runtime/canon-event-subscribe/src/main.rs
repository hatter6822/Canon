// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! `canon-event-subscribe` — RH-D skeleton entry-point.
//!
//! The implementing work unit (`docs/planning/rust_host_runtime_plan.md`
//! §RH-D) replaces this `main` with the subscription service that
//! tails Canon's `log.jsonl`, delegates event extraction to the Lean
//! `canon` executable, and streams ordered events to subscribers
//! with bounded-lag eviction and resume-from-sequence protocol.

use canon_cli_common::exit::OperatorExitCode;

fn main() {
    eprintln!(
        "canon-event-subscribe: RH-D not yet implemented; see docs/planning/rust_host_runtime_plan.md §RH-D"
    );
    OperatorExitCode::NotImplemented.terminate();
}
