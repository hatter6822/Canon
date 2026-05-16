// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! `canon-bench` — RH-F skeleton.
//!
//! The implementing work unit (`docs/planning/rust_host_runtime_plan.md`
//! §RH-F) materialises this crate as a Criterion benchmark suite
//! measuring `canon-host` transfer throughput end-to-end:
//!
//!   * Pre-fund 1000 actor accounts with a synthetic genesis log.
//!   * Generate 10000 valid transfer `SignedAction`s in advance.
//!   * Submit via `canon-host` over a Unix socket; measure p50 /
//!     p99 / p999 latency.
//!   * Target: ≥ 10k tx/sec sustained, p99 < 10 ms.
//!
//! ## Skeleton posture
//!
//! The benchmark binary is not yet present; this crate is an empty
//! `lib` shell so the workspace member list is stable from RH-H
//! onward.  Adding `benches/transfer_10k.rs` is RH-F's deliverable.

#![doc(html_root_url = "https://docs.rs/canon-bench/0.1.0")]

/// Crate name, mirrored from `Cargo.toml`.
pub const CRATE_NAME: &str = "canon-bench";

#[cfg(test)]
mod tests {
    use super::CRATE_NAME;

    #[test]
    fn crate_name_constant() {
        assert_eq!(CRATE_NAME, "canon-bench");
    }
}
