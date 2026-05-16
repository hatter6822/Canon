// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! `canon-faultproof-observer` — RH-G skeleton.
//!
//! The implementing work unit (`docs/planning/rust_host_runtime_plan.md`
//! §RH-G) materialises this crate as a daemon that:
//!
//!   * **RH-G.2** — Watches L1 for fault-proof-game events with
//!     re-org handling (sliding-window block-hash check).
//!   * **RH-G.3** — Mirrors the Lean game-state machine
//!     (`LegalKernel/FaultProof/Game.lean`) in Rust under
//!     byte-equality property tests against the Lean reference.
//!   * **RH-G.4** — Computes the honest bisection response via a
//!     `canon` subprocess; emits witness-state or SMT-path cell
//!     proofs.
//!   * **RH-G.5** — Signs and submits responses with gas-bump and
//!     deadline-escalation strategies.
//!   * **RH-G.6** — Persists watcher + game state in `canon-storage`
//!     for crash-recovery; idempotent restart.
//!   * **RH-G.7** — Cross-stack equivalence corpus + chaos suite
//!     (anvil-based + property-tested).
//!
//! ## Skeleton posture
//!
//! At RH-H landing this crate exposes no public surface beyond the
//! crate-version constant.  The binary's `main` exits with
//! [`canon_cli_common::exit::OperatorExitCode::NotImplemented`] so a
//! deployment that wires up the daemon today gets a loud,
//! supervisor-visible refusal rather than an incorrect bisection
//! response.

#![doc(html_root_url = "https://docs.rs/canon-faultproof-observer/0.1.0")]

/// Crate name, mirrored from `Cargo.toml`.
pub const CRATE_NAME: &str = "canon-faultproof-observer";

#[cfg(test)]
mod tests {
    use super::CRATE_NAME;

    #[test]
    fn crate_name_constant() {
        assert_eq!(CRATE_NAME, "canon-faultproof-observer");
    }
}
