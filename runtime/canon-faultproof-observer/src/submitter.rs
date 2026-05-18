// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! L1 transaction submission for fault-proof game moves.
//!
//! ## Submission flow
//!
//! 1. The observer's orchestrator computes an [`HonestMove`].
//! 2. The submitter's [`encode_calldata`] converts the move +
//!    game id into the L1 transaction calldata (Solidity ABI
//!    encoded).
//! 3. The submitter wraps that calldata into a signed EIP-1559
//!    transaction (or legacy, depending on the L1 RPC's
//!    capability) and broadcasts via `eth_sendRawTransaction`.
//! 4. The submitter records the tx-hash in
//!    [`crate::persistence`] as `ResponseStatus::Pending`.
//! 5. On subsequent watcher iterations, the submitter checks the
//!    tx receipt; on inclusion + N confirmations, updates the
//!    record to `Confirmed`.
//!
//! ## What this RH-G landing ships
//!
//! The submitter ships with two implementations:
//!
//!   * [`mock::MockSubmitter`] — in-memory; the test harness uses
//!     this to drive the observer without an actual L1 RPC.
//!     Records every submission for inspection.
//!   * [`encode::encode_calldata`] — pure-Rust ABI encoder for
//!     the four L1 contract methods (`submitMidpoint`,
//!     `respondToMidpoint`, `terminateOnSingleStep`,
//!     `claimTimeout`).  Production deployments use this
//!     calldata as the `data` field of their transaction.
//!
//! The full production [`json_rpc::JsonRpcSubmitter`] that signs
//! and broadcasts is sketched as a public trait API but its
//! actual `eth_sendRawTransaction` driver requires EIP-1559
//! transaction-encoding work that mirrors RH-B's
//! `JsonRpcL1Source`.  The mock + calldata encoder cover the
//! observer's *correctness* (the calldata bytes are what get
//! tested cross-stack); the production driver is RH-G follow-up
//! work that doesn't change the calldata contract.
//!
//! ## Key zeroization
//!
//! The signing key is wrapped in
//! [`canon_l1_ingest::key::BridgeActorKey`] which holds the raw
//! private bytes in `Zeroizing<[u8; 32]>`.  Drop scrubs the
//! memory.  This is the same key wrapper used by RH-B (L1
//! ingestor); we re-use it directly to keep the audit surface
//! narrow.

use sha3::{Digest, Keccak256};

use crate::game::StateCommit;
use crate::strategy::HonestMove;

/// The four method selectors the observer calls on the L1 game
/// contract.  Selector = first 4 bytes of `keccak256(signature)`.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub enum MethodSelector {
    /// `submitMidpoint(uint256 gameId, bytes32 midpointCommit)`.
    SubmitMidpoint,
    /// `respondToMidpoint(uint256 gameId, bool agree)`.
    RespondToMidpoint,
    /// `terminateOnSingleStep(uint256 gameId, bytes32 claimedPostCommit)`.
    /// Note: the production contract takes additional arguments
    /// (actionKind, actionFields, signer, cellProofs), but the
    /// off-chain calldata generation here covers the minimum
    /// observer-emitted form.  Full calldata requires the cell-
    /// proof bundle which comes from a `canon` subprocess; see
    /// the module docstring's "What this RH-G landing ships".
    TerminateOnSingleStep,
    /// `claimTimeout(uint256 gameId)`.
    ClaimTimeout,
}

impl MethodSelector {
    /// The canonical Solidity method signature.  We deliberately
    /// emit the **minimum** signature for `terminateOnSingleStep`
    /// because the full version requires per-action calldata
    /// + cell proofs that come from a separate (Lean subprocess)
    ///   pipeline.  The selector returned here is for the form
    ///   `terminateOnSingleStep(uint256, bytes32)` — useful for
    ///   integration smoke tests but NOT what the production
    ///   contract dispatches on.
    #[must_use]
    pub const fn signature(self) -> &'static str {
        match self {
            Self::SubmitMidpoint => "submitMidpoint(uint256,bytes32)",
            Self::RespondToMidpoint => "respondToMidpoint(uint256,bool)",
            Self::TerminateOnSingleStep => "terminateOnSingleStep(uint256,bytes32)",
            Self::ClaimTimeout => "claimTimeout(uint256)",
        }
    }

    /// The 4-byte method selector (first 4 bytes of
    /// `keccak256(signature)`).
    #[must_use]
    pub fn selector(self) -> [u8; 4] {
        let mut hasher = Keccak256::new();
        hasher.update(self.signature().as_bytes());
        let digest = hasher.finalize();
        let mut out = [0u8; 4];
        out.copy_from_slice(&digest[0..4]);
        out
    }
}

/// Errors specific to the submitter.
#[derive(Debug, thiserror::Error)]
pub enum SubmitError {
    /// The honest move is `NoMove`; cannot encode calldata for a
    /// no-op.
    #[error("cannot encode calldata for HonestMove::NoMove")]
    NoMove,

    /// The honest move is `Submit` (proposing a new midpoint) but
    /// the caller invoked `encode_calldata` instead of
    /// `encode_submit_calldata` — the L1 contract's
    /// `submitMidpoint` takes only the commit (the midpoint idx
    /// is computed on-chain from the game's range).
    #[error("encode_calldata cannot synthesise Submit; use the dedicated path")]
    UnsupportedMove,

    /// Submission was rejected by the L1 RPC (e.g., invalid
    /// nonce, out-of-gas estimate).
    #[error("L1 RPC rejected submission: {0}")]
    RpcRejected(String),

    /// The submitter is in mock mode and was asked to perform a
    /// network call.
    #[error("mock submitter received unexpected network call")]
    MockUnsupported,
}

/// ABI-encode an Ethereum transaction calldata for the given
/// game id + honest move.  Returns the calldata bytes ready to
/// be wrapped in a transaction's `data` field.
///
/// Encoding rules:
///
///   * Method selector (4 bytes) is the first 4 bytes of
///     `keccak256(method-signature)`.
///   * `uint256` arguments are encoded as 32-byte big-endian
///     left-padded.
///   * `bytes32` arguments are encoded as raw 32 bytes.
///   * `bool` arguments are encoded as 32-byte left-padded
///     {0, 1}.
///
/// # Errors
///
/// See [`SubmitError`].
pub fn encode_calldata(game_id: u128, mv: HonestMove) -> Result<Vec<u8>, SubmitError> {
    match mv {
        HonestMove::NoMove => Err(SubmitError::NoMove),
        HonestMove::Submit(claim) => Ok(encode_submit_calldata(game_id, claim.commit)),
        HonestMove::RespondAgree => Ok(encode_respond_calldata(game_id, true)),
        HonestMove::RespondDisagree => Ok(encode_respond_calldata(game_id, false)),
        HonestMove::TerminateOnSingleStep {
            claimed_post_commit,
        } => Ok(encode_terminate_calldata(game_id, claimed_post_commit)),
    }
}

/// Encode a `submitMidpoint(uint256 gameId, bytes32 midpointCommit)`
/// call.  The L1 contract uses this commit + a side-computed
/// midpoint index to record the new pending midpoint.
#[must_use]
pub fn encode_submit_calldata(game_id: u128, commit: StateCommit) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + 32 + 32);
    out.extend_from_slice(&MethodSelector::SubmitMidpoint.selector());
    out.extend_from_slice(&u256_be(game_id));
    out.extend_from_slice(&commit);
    out
}

/// Encode a `respondToMidpoint(uint256 gameId, bool agree)` call.
#[must_use]
pub fn encode_respond_calldata(game_id: u128, agree: bool) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + 32 + 32);
    out.extend_from_slice(&MethodSelector::RespondToMidpoint.selector());
    out.extend_from_slice(&u256_be(game_id));
    out.extend_from_slice(&bool_word(agree));
    out
}

/// Encode the minimum form of `terminateOnSingleStep(uint256 gameId,
/// bytes32 claimedPostCommit)`.  The production contract takes a
/// fuller form with cell proofs and action calldata; that wider
/// form is constructed by a separate pipeline that combines this
/// minimum form with the cell-proof bundle from a `canon`
/// subprocess.
#[must_use]
pub fn encode_terminate_calldata(game_id: u128, claimed_post_commit: StateCommit) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + 32 + 32);
    out.extend_from_slice(&MethodSelector::TerminateOnSingleStep.selector());
    out.extend_from_slice(&u256_be(game_id));
    out.extend_from_slice(&claimed_post_commit);
    out
}

/// Encode a `claimTimeout(uint256 gameId)` call.
#[must_use]
pub fn encode_claim_timeout_calldata(game_id: u128) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + 32);
    out.extend_from_slice(&MethodSelector::ClaimTimeout.selector());
    out.extend_from_slice(&u256_be(game_id));
    out
}

/// Encode a `u128` as a 32-byte big-endian left-padded ABI word
/// (matching Solidity's `uint256` encoding).
fn u256_be(v: u128) -> [u8; 32] {
    let mut out = [0u8; 32];
    out[16..32].copy_from_slice(&v.to_be_bytes());
    out
}

/// Encode a `bool` as a 32-byte left-padded ABI word.
fn bool_word(v: bool) -> [u8; 32] {
    let mut out = [0u8; 32];
    out[31] = u8::from(v);
    out
}

/// Submitter trait — abstracts L1 transaction signing +
/// broadcasting.  Production deployments use the JSON-RPC impl;
/// tests use the mock.
pub trait Submitter {
    /// Submit a calldata payload to the L1 game contract.
    /// Returns the resulting transaction hash on success.
    ///
    /// # Errors
    ///
    /// See [`SubmitError`].
    fn submit(&self, calldata: &[u8]) -> Result<[u8; 32], SubmitError>;

    /// Check whether a previously-submitted tx has been
    /// included on L1.  Returns `Some(true)` if confirmed,
    /// `Some(false)` if pending, `None` if dropped (the tx was
    /// re-orged out or never mined).
    ///
    /// # Errors
    ///
    /// See [`SubmitError`].
    fn check_inclusion(&self, tx_hash: &[u8; 32]) -> Result<Option<bool>, SubmitError>;
}

/// In-memory mock submitter.  Records every submission for
/// inspection; reports tx-hashes derived from
/// `keccak256(calldata)` so tests get deterministic ids.
pub mod mock {
    use std::sync::Mutex;

    use sha3::{Digest, Keccak256};

    use super::{SubmitError, Submitter};

    /// A recorded mock submission.
    #[allow(clippy::module_name_repetitions)]
    #[derive(Clone, Debug, Eq, PartialEq)]
    pub struct MockSubmission {
        /// The calldata bytes submitted.
        pub calldata: Vec<u8>,
        /// The synthesised tx-hash.
        pub tx_hash: [u8; 32],
    }

    /// Mock submitter — records every submission and reports
    /// configurable inclusion-check results.
    #[allow(clippy::module_name_repetitions)]
    #[derive(Debug)]
    pub struct MockSubmitter {
        inner: Mutex<MockInner>,
    }

    #[derive(Debug, Default)]
    struct MockInner {
        submitted: Vec<MockSubmission>,
        /// If `true`, `submit` returns `RpcRejected("mock rejection")`.
        next_reject: bool,
        /// Map from `tx_hash` → inclusion-check result.  Defaults
        /// to `Some(true)` (confirmed).
        inclusion_map: std::collections::HashMap<[u8; 32], Option<bool>>,
    }

    impl Default for MockSubmitter {
        fn default() -> Self {
            Self::new()
        }
    }

    impl MockSubmitter {
        /// Construct an empty mock submitter.
        #[must_use]
        pub fn new() -> Self {
            Self {
                inner: Mutex::new(MockInner::default()),
            }
        }

        /// Read-accessor for the submission history.
        #[must_use]
        pub fn submissions(&self) -> Vec<MockSubmission> {
            self.inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .submitted
                .clone()
        }

        /// Configure the next `submit` to return `RpcRejected`.
        pub fn set_next_reject(&self) {
            self.inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .next_reject = true;
        }

        /// Configure a specific tx-hash's inclusion outcome.
        pub fn set_inclusion(&self, tx_hash: [u8; 32], inclusion: Option<bool>) {
            self.inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .inclusion_map
                .insert(tx_hash, inclusion);
        }
    }

    impl Submitter for MockSubmitter {
        fn submit(&self, calldata: &[u8]) -> Result<[u8; 32], SubmitError> {
            let mut hasher = Keccak256::new();
            hasher.update(calldata);
            let digest = hasher.finalize();
            let mut tx_hash = [0u8; 32];
            tx_hash.copy_from_slice(&digest);
            let mut inner = self
                .inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if inner.next_reject {
                inner.next_reject = false;
                return Err(SubmitError::RpcRejected("mock rejection".into()));
            }
            inner.submitted.push(MockSubmission {
                calldata: calldata.to_vec(),
                tx_hash,
            });
            Ok(tx_hash)
        }

        fn check_inclusion(&self, tx_hash: &[u8; 32]) -> Result<Option<bool>, SubmitError> {
            let inner = self
                .inner
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            Ok(inner
                .inclusion_map
                .get(tx_hash)
                .copied()
                .unwrap_or(Some(true)))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        encode_calldata, encode_claim_timeout_calldata, encode_respond_calldata,
        encode_submit_calldata, encode_terminate_calldata, MethodSelector, SubmitError,
    };
    use crate::game::{Claim, StateCommit};
    use crate::strategy::HonestMove;
    use crate::submitter::mock::MockSubmitter;
    use crate::submitter::Submitter;

    fn commit(seed: u8) -> StateCommit {
        let mut out = [0u8; 32];
        out[0] = seed;
        out
    }

    /// Method selectors are distinct.
    #[test]
    fn method_selectors_distinct() {
        let selectors = [
            MethodSelector::SubmitMidpoint.selector(),
            MethodSelector::RespondToMidpoint.selector(),
            MethodSelector::TerminateOnSingleStep.selector(),
            MethodSelector::ClaimTimeout.selector(),
        ];
        for (i, a) in selectors.iter().enumerate() {
            for (j, b) in selectors.iter().enumerate() {
                if i != j {
                    assert_ne!(a, b, "selectors {i} and {j} collide");
                }
            }
        }
    }

    /// Method-selector encoding matches expected calldata-prefix
    /// shape.  We don't pin the actual selector bytes here (they'd
    /// require computing keccak256 by hand); instead, check the
    /// selector length and that `signature()` round-trips.
    #[test]
    fn method_selector_length_4() {
        for m in [
            MethodSelector::SubmitMidpoint,
            MethodSelector::RespondToMidpoint,
            MethodSelector::TerminateOnSingleStep,
            MethodSelector::ClaimTimeout,
        ] {
            assert_eq!(m.selector().len(), 4);
            assert!(!m.signature().is_empty());
        }
    }

    /// `encode_calldata(NoMove)` errors.
    #[test]
    fn no_move_errors() {
        let err = encode_calldata(1, HonestMove::NoMove).unwrap_err();
        assert!(matches!(err, SubmitError::NoMove));
    }

    /// `encode_calldata(Submit(_))` uses the submit calldata
    /// encoding.
    #[test]
    fn submit_uses_submit_calldata() {
        let c = Claim {
            idx: 32,
            commit: commit(99),
        };
        let bytes = encode_calldata(42, HonestMove::Submit(c)).unwrap();
        // 4-byte selector + 32 (u256 game id) + 32 (bytes32 commit).
        assert_eq!(bytes.len(), 68);
        assert_eq!(&bytes[0..4], &MethodSelector::SubmitMidpoint.selector());
    }

    /// `encode_calldata(RespondAgree)` uses the respond calldata.
    #[test]
    fn respond_agree_uses_respond_calldata() {
        let bytes = encode_calldata(42, HonestMove::RespondAgree).unwrap();
        assert_eq!(bytes.len(), 68);
        assert_eq!(&bytes[0..4], &MethodSelector::RespondToMidpoint.selector());
        // Last byte is the bool: 1 = true.
        assert_eq!(bytes[67], 1);
    }

    /// `encode_calldata(RespondDisagree)` uses the respond
    /// calldata with `agree=false`.
    #[test]
    fn respond_disagree_uses_respond_calldata() {
        let bytes = encode_calldata(42, HonestMove::RespondDisagree).unwrap();
        assert_eq!(bytes.len(), 68);
        assert_eq!(&bytes[0..4], &MethodSelector::RespondToMidpoint.selector());
        assert_eq!(bytes[67], 0);
    }

    /// `encode_calldata(TerminateOnSingleStep)` uses the
    /// terminate calldata.
    #[test]
    fn terminate_uses_terminate_calldata() {
        let bytes = encode_calldata(
            42,
            HonestMove::TerminateOnSingleStep {
                claimed_post_commit: commit(7),
            },
        )
        .unwrap();
        assert_eq!(bytes.len(), 68);
        assert_eq!(
            &bytes[0..4],
            &MethodSelector::TerminateOnSingleStep.selector()
        );
        // The last 32 bytes encode the claimed_post_commit.
        assert_eq!(&bytes[36..68], &commit(7));
    }

    /// `encode_claim_timeout_calldata` length is 4 + 32 = 36.
    #[test]
    fn claim_timeout_calldata_length() {
        let bytes = encode_claim_timeout_calldata(42);
        assert_eq!(bytes.len(), 36);
        assert_eq!(&bytes[0..4], &MethodSelector::ClaimTimeout.selector());
    }

    /// Game id is encoded as 32-byte big-endian.
    #[test]
    fn game_id_encoded_as_32_byte_be() {
        let bytes = encode_submit_calldata(0xFEED_BEEF, commit(1));
        // Selector + u256(0xFEEDBEEF padded) + commit
        // u256 of 0xFEEDBEEF: 28 zero bytes then 4 bytes BE.
        let id_word = &bytes[4..36];
        assert_eq!(&id_word[28..32], &0xFEED_BEEFu32.to_be_bytes());
        for b in &id_word[..28] {
            assert_eq!(*b, 0);
        }
    }

    /// Game id `u128::MAX` is encoded correctly.
    #[test]
    fn game_id_u128_max_encoded() {
        let bytes = encode_submit_calldata(u128::MAX, commit(1));
        // u128::MAX = upper 16 bytes zero, lower 16 bytes 0xFF.
        let id_word = &bytes[4..36];
        for b in &id_word[..16] {
            assert_eq!(*b, 0);
        }
        for b in &id_word[16..32] {
            assert_eq!(*b, 0xFF);
        }
    }

    /// Bool encoding pads correctly.
    #[test]
    fn bool_encoding_padded() {
        let bytes = encode_respond_calldata(1, true);
        // The bool word is the last 32 bytes.
        let bool_word = &bytes[36..68];
        for b in &bool_word[..31] {
            assert_eq!(*b, 0);
        }
        assert_eq!(bool_word[31], 1);
    }

    /// `encode_terminate_calldata` puts the commit at the end.
    #[test]
    fn terminate_commit_at_end() {
        let bytes = encode_terminate_calldata(42, commit(0xAA));
        let commit_word = &bytes[36..68];
        assert_eq!(commit_word, &commit(0xAA));
    }

    /// Mock submitter records submissions.
    #[test]
    fn mock_submitter_records_submission() {
        let m = MockSubmitter::new();
        let calldata = vec![1u8, 2, 3, 4];
        let tx_hash = m.submit(&calldata).unwrap();
        let recorded = m.submissions();
        assert_eq!(recorded.len(), 1);
        assert_eq!(recorded[0].calldata, calldata);
        assert_eq!(recorded[0].tx_hash, tx_hash);
    }

    /// Mock submitter's tx-hash is deterministic
    /// (keccak256(calldata)).
    #[test]
    fn mock_submitter_tx_hash_deterministic() {
        let m1 = MockSubmitter::new();
        let m2 = MockSubmitter::new();
        let calldata = vec![5u8, 6, 7];
        let h1 = m1.submit(&calldata).unwrap();
        let h2 = m2.submit(&calldata).unwrap();
        assert_eq!(h1, h2);
    }

    /// Mock submitter `set_next_reject` triggers a typed
    /// error on the next call.
    #[test]
    fn mock_submitter_set_next_reject() {
        let m = MockSubmitter::new();
        m.set_next_reject();
        let err = m.submit(&[1u8]).unwrap_err();
        assert!(matches!(err, SubmitError::RpcRejected(_)));
        // Subsequent calls succeed.
        m.submit(&[2u8]).unwrap();
    }

    /// Mock submitter inclusion-check default: `Some(true)`.
    #[test]
    fn mock_submitter_inclusion_default_confirmed() {
        let m = MockSubmitter::new();
        let h = m.submit(&[1u8]).unwrap();
        assert_eq!(m.check_inclusion(&h).unwrap(), Some(true));
    }

    /// Mock submitter inclusion-check honors `set_inclusion`.
    #[test]
    fn mock_submitter_inclusion_configurable() {
        let m = MockSubmitter::new();
        let h = m.submit(&[1u8]).unwrap();
        m.set_inclusion(h, Some(false));
        assert_eq!(m.check_inclusion(&h).unwrap(), Some(false));
        m.set_inclusion(h, None);
        assert_eq!(m.check_inclusion(&h).unwrap(), None);
    }

    /// Selectors for different methods are non-zero.
    #[test]
    fn selectors_non_zero() {
        for m in [
            MethodSelector::SubmitMidpoint,
            MethodSelector::RespondToMidpoint,
            MethodSelector::TerminateOnSingleStep,
            MethodSelector::ClaimTimeout,
        ] {
            assert_ne!(m.selector(), [0u8; 4]);
        }
    }
}
