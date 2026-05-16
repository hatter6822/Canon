// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! L1 event → Canon `Action` translation.
//!
//! Rust mirror of Lean's `LegalKernel.Bridge.Ingest.ingest`.
//! Each L1 event variant maps to either:
//!
//!   * `Some(UnsignedAction)` — the translator emits an
//!     unsigned bridge action that the submitter will sign and
//!     forward to `canon-host`.
//!   * `None` — the L1 event has no Canon-side action effect
//!     (revocations, deposits) in MVP scope.
//!
//! ## The mathematical contract
//!
//! For every `IngestedEvent` `e` and `AddressBook` `b`:
//!
//! ```text
//! let (b', maybe_unsigned) = ingest(&mut b, e, current_nonce);
//! ```
//!
//! must match the Lean side's
//!
//! ```text
//! let (b', maybe_unsigned) := Bridge.Ingest.ingest b current_nonce e
//! ```
//!
//! **byte-by-byte after CBE encoding**.  The cross-stack
//! `FixtureKind::L1Ingest` corpus enforces this contract for the
//! variants the ingestor actually emits (RegisteredECDSA,
//! optional RegisteredEIP1271 contract signer registration).
//!
//! ## The 3 cases
//!
//! Mirrors Lean's `ingest` function:
//!
//!   1. **First-time registration** (event is RegisteredECDSA or
//!      RegisteredEIP1271; address book has no prior mapping):
//!      - Assign a fresh `ActorId` via `AddressBook::assign`.
//!      - Emit `Action::RegisterIdentity { actor: fresh_id, pk }`.
//!   2. **Rotation** (event is RegisteredECDSA or
//!      RegisteredEIP1271; address book has prior mapping):
//!      - Look up existing `ActorId`.
//!      - Emit `Action::ReplaceKey { actor: existing_id, new_key: pk }`.
//!      - Do NOT bump the address book counter.
//!   3. **No-op** (event is Revoked or DepositInitiated):
//!      - Return `None`.
//!      - Address book unchanged.

use crate::action::{Action, ActorId, EthAddress, Nonce, PublicKey};
use crate::address_book::{AddressBook, BRIDGE_ACTOR_ID};
use crate::events::IngestedEvent;

/// The signer / nonce / action triple the translator emits
/// before signing.  Mirrors Lean's `Bridge.UnsignedBridgeAction`
/// structure.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UnsignedAction {
    /// The Canon action to sign.
    pub action: Action,
    /// The signer's `ActorId` — always [`BRIDGE_ACTOR_ID`] for
    /// translated events, pinned by Lean's
    /// `ingest_emits_bridge_actor` theorem.
    pub signer: ActorId,
    /// The signer's next-expected nonce.  Supplied by the
    /// translation caller; the watcher maintains it across
    /// iterations.
    pub nonce: Nonce,
}

impl UnsignedAction {
    /// The bridge actor's id — pinned by Lean's
    /// `ingest_emits_bridge_actor`.
    pub const SIGNER: ActorId = BRIDGE_ACTOR_ID;
}

/// Translate an `IngestedEvent` against the current
/// `AddressBook`.  Updates the book in place where necessary
/// (only first-time `RegisteredECDSA` / `RegisteredEIP1271`
/// triggers a book mutation); returns `Some(UnsignedAction)` if
/// the event has a Canon-side effect, `None` otherwise.
///
/// Matches Lean's `Bridge.Ingest.ingest` byte-for-byte under CBE
/// encoding (verified by the cross-stack fixture corpus).
pub fn ingest(
    book: &mut AddressBook,
    event: &IngestedEvent,
    current_nonce: Nonce,
) -> Option<UnsignedAction> {
    match event {
        IngestedEvent::RegisteredEcdsa { actor, pubkey, .. } => {
            let pk = PublicKey::from_bytes(pubkey);
            Some(translate_registration(book, actor, pk, current_nonce))
        }
        IngestedEvent::RegisteredEip1271 {
            actor,
            contract_signer,
            ..
        } => {
            // The Lean side's `Bridge.Ingest.ingest` MVP scope
            // does not distinguish contract signers from EOAs at
            // the translation layer — both map to
            // `RegisterIdentity` / `ReplaceKey` with the
            // signer's address-as-pubkey encoding.  We use the
            // 20-byte contract address as the "pubkey" payload.
            // Downstream deployment-side `AuthorityPolicy`
            // predicates classify the signer kind via the
            // `KeyRegistry`'s `SignerKind` enum.
            let pk = PublicKey::from_bytes(contract_signer.as_bytes());
            Some(translate_registration(book, actor, pk, current_nonce))
        }
        IngestedEvent::Revoked { .. } => {
            // `Bridge.Ingest.ingest` returns `none` for revocations
            // in MVP scope.
            None
        }
        IngestedEvent::DepositInitiated { .. } => {
            // `Bridge.Ingest.ingest` returns `none` for deposits
            // in MVP scope; deposit handling goes through
            // `applyActionToBridgeState` at the kernel level.
            None
        }
    }
}

/// Common path for registration events (RegisteredECDSA and
/// RegisteredEIP1271).  Looks up the address; if unknown, assigns
/// a fresh id and emits `RegisterIdentity`.  If known, emits
/// `ReplaceKey` and leaves the book unchanged.
fn translate_registration(
    book: &mut AddressBook,
    actor_address: &EthAddress,
    pk: PublicKey,
    current_nonce: Nonce,
) -> UnsignedAction {
    match book.lookup(actor_address) {
        None => {
            // First-time registration: assign fresh id and emit
            // RegisterIdentity.
            let (fresh_id, _) = book.assign(actor_address);
            UnsignedAction {
                action: Action::RegisterIdentity {
                    actor: fresh_id,
                    pk,
                },
                signer: UnsignedAction::SIGNER,
                nonce: current_nonce,
            }
        }
        Some(existing_id) => {
            // Key rotation: emit ReplaceKey, leave book unchanged.
            UnsignedAction {
                action: Action::ReplaceKey {
                    actor: existing_id,
                    new_key: pk,
                },
                signer: UnsignedAction::SIGNER,
                nonce: current_nonce,
            }
        }
    }
}

/// Errors surfaced by the higher-level translation pipeline.
/// `ingest` itself is total; this enum is reserved for the
/// downstream `sign + submit` pipeline that consumes
/// `UnsignedAction`.
#[derive(Debug, thiserror::Error)]
pub enum TranslationError {
    /// The translator received an event variant it can't handle.
    /// Reserved for future event types not yet wired through.
    #[error("unsupported event variant: {0}")]
    UnsupportedEvent(&'static str),
}

#[cfg(test)]
mod tests {
    use super::{ingest, UnsignedAction};
    use crate::action::{Action, EthAddress};
    use crate::address_book::{AddressBook, BRIDGE_ACTOR_ID};
    use crate::events::IngestedEvent;

    /// First-time `RegisteredECDSA` emits `RegisterIdentity` with
    /// a fresh actor id.
    #[test]
    fn first_time_registration_emits_register_identity() {
        let mut book = AddressBook::new();
        let actor = EthAddress::from_bytes(&[1u8; 20]).unwrap();
        let pubkey = vec![0xab, 0xcd];
        let event = IngestedEvent::RegisteredEcdsa {
            actor,
            pubkey: pubkey.clone(),
            block_number: 1,
            tx_hash: [0; 32],
            log_index: 0,
        };
        let unsigned = ingest(&mut book, &event, 0).unwrap();
        match &unsigned.action {
            Action::RegisterIdentity { actor: id, pk } => {
                assert_eq!(*id, 1, "first assignment yields id 1");
                assert_eq!(pk.as_bytes(), pubkey.as_slice());
            }
            _ => panic!("expected RegisterIdentity"),
        }
        assert_eq!(unsigned.signer, BRIDGE_ACTOR_ID);
        assert_eq!(unsigned.nonce, 0);
        // Address book was mutated.
        assert_eq!(book.lookup(&actor), Some(1));
    }

    /// Second `RegisteredECDSA` for the same address emits
    /// `ReplaceKey` with the existing id.
    #[test]
    fn rotation_emits_replace_key() {
        let mut book = AddressBook::new();
        let actor = EthAddress::from_bytes(&[1u8; 20]).unwrap();
        // First registration.
        let e1 = IngestedEvent::RegisteredEcdsa {
            actor,
            pubkey: vec![0xaa],
            block_number: 1,
            tx_hash: [0; 32],
            log_index: 0,
        };
        let _ = ingest(&mut book, &e1, 0);
        let next_id_before = book.next_actor_id();
        // Rotation.
        let new_pk = vec![0xbb, 0xcc];
        let e2 = IngestedEvent::RegisteredEcdsa {
            actor,
            pubkey: new_pk.clone(),
            block_number: 2,
            tx_hash: [0; 32],
            log_index: 1,
        };
        let unsigned = ingest(&mut book, &e2, 1).unwrap();
        match &unsigned.action {
            Action::ReplaceKey { actor: id, new_key } => {
                assert_eq!(*id, 1, "rotation uses existing id");
                assert_eq!(new_key.as_bytes(), new_pk.as_slice());
            }
            _ => panic!("expected ReplaceKey"),
        }
        assert_eq!(unsigned.nonce, 1);
        // Address book did NOT mutate (no fresh id assigned).
        assert_eq!(book.next_actor_id(), next_id_before);
    }

    /// `Revoked` emits no Action and does not mutate the book.
    #[test]
    fn revoked_emits_no_action() {
        let mut book = AddressBook::new();
        let actor = EthAddress::from_bytes(&[2u8; 20]).unwrap();
        let event = IngestedEvent::Revoked {
            actor,
            block_number: 1,
            tx_hash: [0; 32],
            log_index: 0,
        };
        let result = ingest(&mut book, &event, 0);
        assert!(result.is_none());
        assert!(book.is_empty());
    }

    /// `DepositInitiated` emits no Action and does not mutate
    /// the book.  Deposit translation is reserved for
    /// `applyActionToBridgeState` at the kernel layer (per
    /// Lean's MVP-scope behaviour pin).
    #[test]
    fn deposit_emits_no_action() {
        let mut book = AddressBook::new();
        let depositor = EthAddress::from_bytes(&[3u8; 20]).unwrap();
        let event = IngestedEvent::DepositInitiated {
            depositor,
            resource_id: 7,
            token: EthAddress::ZERO,
            amount: [0; 32],
            depositor_nonce: 0,
            receipt_hash: [0; 32],
            block_number: 1,
            tx_hash: [0; 32],
            log_index: 0,
        };
        let result = ingest(&mut book, &event, 0);
        assert!(result.is_none());
        assert!(book.is_empty());
    }

    /// `RegisteredEIP1271` translates analogously to
    /// `RegisteredECDSA` but with the contract address as the
    /// public key.
    #[test]
    fn eip1271_translates_via_contract_signer() {
        let mut book = AddressBook::new();
        let actor = EthAddress::from_bytes(&[4u8; 20]).unwrap();
        let contract = EthAddress::from_bytes(&[5u8; 20]).unwrap();
        let event = IngestedEvent::RegisteredEip1271 {
            actor,
            contract_signer: contract,
            block_number: 1,
            tx_hash: [0; 32],
            log_index: 0,
        };
        let unsigned = ingest(&mut book, &event, 0).unwrap();
        match &unsigned.action {
            Action::RegisterIdentity { pk, .. } => {
                // The pubkey payload is the 20-byte contract address.
                assert_eq!(pk.as_bytes(), contract.as_bytes());
            }
            _ => panic!("expected RegisterIdentity"),
        }
    }

    /// The signer of every emitted UnsignedAction is the bridge
    /// actor id (mirrors Lean's `ingest_emits_bridge_actor`).
    #[test]
    fn signer_is_always_bridge_actor() {
        let mut book = AddressBook::new();
        let addr1 = EthAddress::from_bytes(&[1u8; 20]).unwrap();
        let addr2 = EthAddress::from_bytes(&[2u8; 20]).unwrap();
        let events = [
            IngestedEvent::RegisteredEcdsa {
                actor: addr1,
                pubkey: vec![0x01],
                block_number: 0,
                tx_hash: [0; 32],
                log_index: 0,
            },
            IngestedEvent::RegisteredEcdsa {
                actor: addr2,
                pubkey: vec![0x02],
                block_number: 0,
                tx_hash: [0; 32],
                log_index: 1,
            },
            IngestedEvent::RegisteredEcdsa {
                actor: addr1, // rotation
                pubkey: vec![0x03],
                block_number: 0,
                tx_hash: [0; 32],
                log_index: 2,
            },
        ];
        for (i, e) in events.iter().enumerate() {
            let u = ingest(&mut book, e, i as u128).unwrap();
            assert_eq!(u.signer, BRIDGE_ACTOR_ID);
            assert_eq!(u.signer, UnsignedAction::SIGNER);
        }
    }

    /// Locality: ingesting an event for a different address
    /// preserves the lookup of the original.
    #[test]
    fn other_address_lookup_preserved() {
        let mut book = AddressBook::new();
        let addr1 = EthAddress::from_bytes(&[1u8; 20]).unwrap();
        let addr2 = EthAddress::from_bytes(&[2u8; 20]).unwrap();
        let e1 = IngestedEvent::RegisteredEcdsa {
            actor: addr1,
            pubkey: vec![0x01],
            block_number: 0,
            tx_hash: [0; 32],
            log_index: 0,
        };
        let _ = ingest(&mut book, &e1, 0);
        let id1 = book.lookup(&addr1).unwrap();
        let e2 = IngestedEvent::RegisteredEcdsa {
            actor: addr2,
            pubkey: vec![0x02],
            block_number: 0,
            tx_hash: [0; 32],
            log_index: 1,
        };
        let _ = ingest(&mut book, &e2, 1);
        // Originals unchanged after second ingestion.
        assert_eq!(book.lookup(&addr1), Some(id1));
    }

    /// Distinct registrations get distinct ids; rotations do
    /// not.
    #[test]
    fn distinct_registrations_distinct_ids() {
        let mut book = AddressBook::new();
        let addr1 = EthAddress::from_bytes(&[1u8; 20]).unwrap();
        let addr2 = EthAddress::from_bytes(&[2u8; 20]).unwrap();
        let _ = ingest(
            &mut book,
            &IngestedEvent::RegisteredEcdsa {
                actor: addr1,
                pubkey: vec![0x01],
                block_number: 0,
                tx_hash: [0; 32],
                log_index: 0,
            },
            0,
        );
        let _ = ingest(
            &mut book,
            &IngestedEvent::RegisteredEcdsa {
                actor: addr2,
                pubkey: vec![0x02],
                block_number: 0,
                tx_hash: [0; 32],
                log_index: 1,
            },
            1,
        );
        let id1 = book.lookup(&addr1).unwrap();
        let id2 = book.lookup(&addr2).unwrap();
        assert_ne!(id1, id2);
    }

    /// The translation function honours the `current_nonce`
    /// passed in.
    #[test]
    fn nonce_passes_through() {
        let mut book = AddressBook::new();
        let addr = EthAddress::from_bytes(&[1u8; 20]).unwrap();
        let event = IngestedEvent::RegisteredEcdsa {
            actor: addr,
            pubkey: vec![0x01],
            block_number: 0,
            tx_hash: [0; 32],
            log_index: 0,
        };
        let u = ingest(&mut book, &event, 42).unwrap();
        assert_eq!(u.nonce, 42);
    }
}
