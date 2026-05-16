// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! `canon-storage` — RH-E.0 skeleton.
//!
//! The implementing work unit (`docs/planning/rust_host_runtime_plan.md`
//! §RH-E.0) materialises this crate as:
//!
//!   * **RH-E.0.a** — `pub trait Storage` (`get` / `put` / `delete` /
//!     `scan` / `snapshot` / `transaction`) with a documented
//!     byte-array-key, lexicographic-scan-order contract.
//!   * **RH-E.0.b** — A SQLite-backed `SqliteStorage` implementing
//!     `Storage` against a `kv(key BLOB PRIMARY KEY, value BLOB NOT
//!     NULL)` schema with WAL mode.
//!   * **RH-E.0.c** — `Snapshot` API for consistent reads under
//!     concurrent writers (used by `canon-faultproof-observer`'s
//!     game-open consistency requirement).
//!   * **RH-E.0.d** — Append-only migration scaffolding.
//!   * **RH-E.0.e** — Property tests (random KV-op sequences vs.
//!     `BTreeMap` reference), concurrency tests (`N` readers + 1
//!     writer, no torn writes).
//!
//! ## Skeleton posture
//!
//! No trait is exposed yet — committing to a stable trait surface
//! here would prefigure RH-E.0.a's design discussion.  The skeleton
//! is a `cargo`-buildable shell that downstream skeletons (RH-E.1,
//! RH-G) can already dep on so their own dependency lists don't
//! churn when RH-E.0 lands.

#![doc(html_root_url = "https://docs.rs/canon-storage/0.1.0")]

/// Crate name, mirrored from `Cargo.toml`.
pub const CRATE_NAME: &str = "canon-storage";

#[cfg(test)]
mod tests {
    use super::CRATE_NAME;

    #[test]
    fn crate_name_constant() {
        assert_eq!(CRATE_NAME, "canon-storage");
    }
}
