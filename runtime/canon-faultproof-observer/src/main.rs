// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! Binary entry-point for the RH-G skeleton.
//!
//! Replaced by the implementing work unit; the skeleton aborts with
//! [`OperatorExitCode::NotImplemented`] so a deployment that wires
//! up the daemon today gets a loud, supervisor-visible refusal
//! rather than an incorrect bisection response.

use canon_cli_common::exit::OperatorExitCode;
use canon_storage as _;

fn main() {
    eprintln!(
        "canon-faultproof-observer: RH-G not yet implemented; see docs/planning/rust_host_runtime_plan.md §RH-G"
    );
    OperatorExitCode::NotImplemented.terminate();
}
