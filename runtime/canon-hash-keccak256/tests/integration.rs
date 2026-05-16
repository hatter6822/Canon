// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! Integration tests for `canon-hash-keccak256`.
//!
//! Covers cross-file consistency invariants that aren't reachable
//! from a pure-Rust unit test alone — e.g., the IDENTIFIER string
//! is declared in both `src/lib.rs` (the public `IDENTIFIER`
//! constant) and `src/hash.rs` (the internal `IDENTIFIER_BYTES`
//! constant used by the `canon_hash_identifier` Lean ABI entry
//! point).  The two MUST agree byte-for-byte; CI surfaces a
//! mismatch here.

use canon_hash_keccak256::IDENTIFIER;

/// The IDENTIFIER constant in `lib.rs` matches the
/// `IDENTIFIER_BYTES` slice in `hash.rs` (used by the
/// `canon_hash_identifier` Lean ABI entry point).
///
/// We re-read `hash.rs` and grep for the literal so the test
/// catches any drift between the two declarations.  The Lean
/// fallback identifier in `LegalKernel/Runtime/Hash.lean`
/// (`fallbackHashIdentifier = "fnv1a64-padded-32"`) is the
/// counterpart — operators compare against IDENTIFIER to
/// confirm the adaptor is wired.
#[test]
fn identifier_constant_matches_hash_module() {
    use std::path::PathBuf;
    let mut p = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    p.push("src");
    p.push("hash.rs");
    let contents = std::fs::read_to_string(&p).unwrap_or_else(|e| {
        panic!("failed to read hash.rs at {}: {e}", p.display());
    });
    let needle = format!("b\"{IDENTIFIER}\"");
    assert!(
        contents.contains(&needle),
        "IDENTIFIER {IDENTIFIER:?} not found in {} as a byte string literal {needle:?}.  \
         The Lean ABI entry point `canon_hash_identifier` returns the IDENTIFIER_BYTES \
         slice in hash.rs, which must match the IDENTIFIER constant in lib.rs.",
        p.display()
    );
}
