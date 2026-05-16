// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! Cross-stack equivalence tests for RH-B.
//!
//! Walks the `runtime/tests/cross-stack/l1_ingest.cxsf` corpus
//! and asserts that for every record:
//!
//!   1. The fixture's `input` bytes decode to a valid
//!      `FixtureInput` (event + address-book snapshot + nonce).
//!   2. Running `translation::ingest` against the input produces
//!      the `expected` bytes byte-for-byte.
//!
//! This is the load-bearing cross-stack contract: every shipped
//! `Action` translation matches the Lean reference's CBE
//! encoding.

use canon_cross_stack::{FixtureFile, FixtureKind};
use canon_l1_ingest::address_book::AddressBook;
use canon_l1_ingest::encoding::encode_action;
use canon_l1_ingest::fixture::{decode_expected, decode_input, FixtureExpected};
use canon_l1_ingest::translation::ingest;

/// Cross-stack contract for the `FixtureKind::L1Ingest` corpus.
#[test]
fn l1_ingest_corpus_round_trip() {
    let path = format!(
        "{}/../tests/cross-stack/l1_ingest.cxsf",
        env!("CARGO_MANIFEST_DIR")
    );
    let fixture = FixtureFile::load(&path).expect("load fixture file");
    assert!(
        matches!(fixture.kind(), FixtureKind::L1Ingest),
        "fixture kind must be L1Ingest"
    );
    assert!(
        !fixture.records().is_empty(),
        "fixture file must contain records"
    );

    for (i, record) in fixture.records().iter().enumerate() {
        // Decode the input.
        let input = decode_input(&record.input)
            .unwrap_or_else(|e| panic!("record {i}: decode input failed: {e:?}"));
        // Reconstruct the address book.
        let mut book = AddressBook::new();
        for (addr, expected_id) in &input.address_book {
            let (assigned_id, _was_new) = book.assign(addr);
            assert_eq!(
                assigned_id, *expected_id,
                "record {i}: address book replay disagreement at {addr:?}"
            );
        }
        // Run the translation.
        let actual_output = ingest(&mut book, &input.event, input.current_nonce);
        // Decode the expected output.
        let expected = decode_expected(&record.expected)
            .unwrap_or_else(|e| panic!("record {i}: decode expected failed: {e:?}"));
        // Compare.
        match (actual_output, expected) {
            (None, FixtureExpected::None) => {
                // Match: no action emitted.
            }
            (
                Some(actual),
                FixtureExpected::Some {
                    action_bytes,
                    signer,
                    nonce,
                },
            ) => {
                let actual_bytes = encode_action(&actual.action)
                    .unwrap_or_else(|e| panic!("record {i}: encode actual action failed: {e:?}"));
                assert_eq!(
                    actual_bytes, action_bytes,
                    "record {i}: action bytes differ from expected"
                );
                assert_eq!(
                    actual.signer, signer,
                    "record {i}: signer differs from expected"
                );
                assert_eq!(
                    actual.nonce, nonce,
                    "record {i}: nonce differs from expected"
                );
            }
            (None, FixtureExpected::Some { .. }) => {
                panic!("record {i}: ingest returned None but expected Some")
            }
            (Some(_), FixtureExpected::None) => {
                panic!("record {i}: ingest returned Some but expected None")
            }
        }
    }
}

/// The fixture file is non-trivial: at least 10 records covering
/// every variant the translator handles.
#[test]
fn l1_ingest_corpus_coverage() {
    let path = format!(
        "{}/../tests/cross-stack/l1_ingest.cxsf",
        env!("CARGO_MANIFEST_DIR")
    );
    let fixture = FixtureFile::load(&path).expect("load fixture file");
    assert!(
        fixture.records().len() >= 10,
        "fixture file must have at least 10 records, found {}",
        fixture.records().len()
    );
}

/// Re-encoding decoded fixture inputs round-trips.
#[test]
fn l1_ingest_corpus_input_round_trips() {
    use canon_l1_ingest::fixture::encode_input;
    let path = format!(
        "{}/../tests/cross-stack/l1_ingest.cxsf",
        env!("CARGO_MANIFEST_DIR")
    );
    let fixture = FixtureFile::load(&path).expect("load fixture file");
    for (i, record) in fixture.records().iter().enumerate() {
        let input = decode_input(&record.input)
            .unwrap_or_else(|e| panic!("record {i}: decode input failed: {e:?}"));
        let re_encoded = encode_input(&input)
            .unwrap_or_else(|e| panic!("record {i}: re-encode input failed: {e:?}"));
        assert_eq!(
            re_encoded, record.input,
            "record {i}: input does not round-trip"
        );
    }
}
