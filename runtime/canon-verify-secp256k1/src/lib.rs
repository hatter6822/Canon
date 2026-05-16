// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! `canon-verify-secp256k1` — RH-A.1 skeleton.
//!
//! ## What this crate will become
//!
//! The implementing work unit (`docs/planning/rust_host_runtime_plan.md`
//! §RH-A.1) materialises this crate as a `cdylib` exposing the C
//! symbol `canon_verify_ecdsa`, which Lean's
//! `Authority.Crypto.Verify` opaque (`LegalKernel/Authority/Crypto.lean`)
//! links to at runtime.  The full sub-sub-unit breakdown is:
//!
//!   * **RH-A.1.a** — `Cargo.toml` cdylib + staticlib + rlib
//!     crate-type set, `k256 = { version = "0.13", features =
//!     ["ecdsa"], default-features = false }` dependency, `build.rs`
//!     for the C header.
//!   * **RH-A.1.b** — `#[no_mangle] pub unsafe extern "C" fn
//!     canon_verify_ecdsa` with rigorous input validation
//!     (`pk_len == 33`, `msg_len == 32`, `sig_len == 64`, compressed
//!     pubkey prefix check, `(r, s)` parse + bounds check).
//!   * **RH-A.1.c** — Low-s canonicalisation (the load-bearing
//!     malleability defence per Ethereum's convention; reject any
//!     signature with `s > n / 2`).
//!   * **RH-A.1.d** — Cross-stack ECDSA corpus (≥ 50 fixture
//!     vectors, valid + invalid) via `canon-cross-stack`; proptest
//!     fuzzing (30k+ cases); negative-input corpus.
//!
//! ## Skeleton posture
//!
//! At the RH-H landing this crate is a placeholder rlib with no
//! C-ABI exports.  No `#[no_mangle]` symbol is emitted: linking a
//! deployment against this crate today would yield "undefined
//! reference to `canon_verify_ecdsa`" at link time, which is the
//! intended fail-loud posture — there is **no** silently-incorrect
//! fallback verifier.  The Lean kernel's `opaque Verify` body
//! already returns `false` if no production binding is supplied, so
//! a deployment that link-edits without RH-A.1's implementation
//! gets the conservative "every signature invalid" verdict rather
//! than a false positive.
//!
//! ## Audit posture
//!
//! `unsafe_code = "forbid"` (see `Cargo.toml`'s
//! `[lints.rust]`).  RH-A.1.b will relax this to
//! `unsafe_code = "deny"` and limit `unsafe` blocks to the
//! pointer-deref + slice-construction lines required by the C ABI
//! shim.

#![doc(html_root_url = "https://docs.rs/canon-verify-secp256k1/0.1.0")]

/// Crate name, mirrored from `Cargo.toml`.
///
/// Future binaries that link this adaptor surface it via `--version`
/// / diagnostic output; the constant keeps the surface stable across
/// the skeleton → implementation transition.
pub const CRATE_NAME: &str = "canon-verify-secp256k1";

#[cfg(test)]
mod tests {
    use super::CRATE_NAME;

    #[test]
    fn crate_name_constant() {
        assert_eq!(CRATE_NAME, "canon-verify-secp256k1");
    }
}
