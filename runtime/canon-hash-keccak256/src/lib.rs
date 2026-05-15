// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! `canon-hash-keccak256` — RH-A.2 skeleton.
//!
//! ## What this crate will become
//!
//! The implementing work unit (`docs/planning/rust_host_runtime_plan.md`
//! §RH-A.2) materialises this crate as a `cdylib` exposing three C
//! symbols that Lean's `@[extern]` swap-points
//! (`LegalKernel/Runtime/Hash.lean`) bind to at runtime:
//!
//!   * `canon_hash_bytes(ByteArray) -> ByteArray` — one-shot
//!     Keccak-256 (Ethereum-flavoured, 0x01-padded; **not** the
//!     FIPS-202 SHA3-256 variant).
//!   * `canon_hash_stream(List<UInt8>) -> ByteArray` — streaming
//!     variant (init/update/finalize); required for hashing large
//!     states without buffering the whole `ByteArray`.
//!   * `canon_hash_identifier() -> String` — returns the 9-byte
//!     string `"keccak256"`.  Lean reads this to distinguish hash
//!     variants in deployment manifests.
//!
//! Per the plan §RH-A.2 decomposition, sub-sub-units are:
//!
//!   * RH-A.2.a — skeleton + `sha3 = "0.10"` (Keccak256, not SHA3).
//!   * RH-A.2.b — `canon_hash_bytes` one-shot implementation.
//!   * RH-A.2.c — `canon_hash_stream` streaming (init/update/
//!     finalize) implementation.
//!   * RH-A.2.d — `canon_hash_identifier` constant + cross-stack
//!     corpus (≥ 30 byte-array fixtures + 30 streamed-chunk
//!     fixtures via `canon-cross-stack`).
//!
//! ## Skeleton posture
//!
//! At the RH-H landing this crate is a placeholder rlib with no
//! C-ABI exports.  The Lean side falls back to FNV-1a-64 (see
//! `runtime/canon-hash-fallback.c`) when this adaptor is not
//! linked — that fallback is `isProductionHash = false` and causes
//! `canon-replay` to refuse to run without `--allow-fallback-hash`,
//! making the missing production adaptor operator-visible.

#![doc(html_root_url = "https://docs.rs/canon-hash-keccak256/0.1.0")]

/// Crate name, mirrored from `Cargo.toml`.
pub const CRATE_NAME: &str = "canon-hash-keccak256";

/// The implementation identifier the production cdylib will return
/// from `canon_hash_identifier`.  Documented here so downstream
/// consumers (Lean side, audit binaries) can reference the constant
/// without hard-coding the string.
pub const IDENTIFIER: &str = "keccak256";

#[cfg(test)]
mod tests {
    use super::{CRATE_NAME, IDENTIFIER};

    #[test]
    fn crate_constants() {
        assert_eq!(CRATE_NAME, "canon-hash-keccak256");
        assert_eq!(IDENTIFIER, "keccak256");
    }
}
