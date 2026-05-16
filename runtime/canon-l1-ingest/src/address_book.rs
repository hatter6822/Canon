// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! Rust mirror of Lean's `LegalKernel.Bridge.AddressBook`.
//!
//! Maps Ethereum 20-byte addresses (`EthAddress`) to Canon
//! `ActorId`s.  The discipline:
//!
//!   * Forward map: `EthAddress → ActorId`.
//!   * Reverse map: `ActorId → EthAddress`.
//!   * Monotone counter: `next_actor_id`.
//!
//! Operations:
//!
//!   * [`AddressBook::lookup`] — read-only `O(log n)` forward
//!     lookup.  Returns `None` for unknown addresses.
//!   * [`AddressBook::assign`] — assigns `next_actor_id` to a
//!     previously-unknown address, bumping the counter.
//!     `O(log n)` insertion.
//!
//! The `assign` semantics match Lean's
//! `Bridge.AddressBook.assign`: passing an *already-known*
//! address is a no-op that returns the existing actor id.  The
//! reverse direction never overwrites — once an `ActorId` is
//! issued, it points at the same `EthAddress` forever.
//!
//! ## Consistency invariant
//!
//! Lean's `Consistent` invariant pairs the forward / reverse
//! maps: `forward[addr] = id ↔ reverse[id] = addr`.  This Rust
//! mirror preserves the invariant by construction — every
//! `assign` updates both directions atomically (within a single
//! method call; the type is not thread-safe by design, mirroring
//! the Lean side's purely-functional `AddressBook`).
//!
//! ## Where this is used
//!
//! `translation::ingest` consumes an `AddressBook` to decide
//! between `RegisterIdentity` (fresh) and `ReplaceKey` (rotation).
//! The watcher loop maintains the book across iterations, with
//! state persisted to disk by `state.rs`.

use std::collections::BTreeMap;

use crate::action::{ActorId, EthAddress};

/// Maps Ethereum addresses to Canon `ActorId`s.  Mirrors Lean's
/// `Bridge.AddressBook` structure.
///
/// `BTreeMap` is the chosen Rust equivalent of Lean's
/// `Std.TreeMap`: deterministic iteration order, `O(log n)`
/// lookups, and no allocation churn under monotone inserts.
#[derive(Clone, Debug)]
pub struct AddressBook {
    /// Forward map (address → id).
    forward: BTreeMap<EthAddress, ActorId>,
    /// Reverse map (id → address).
    reverse: BTreeMap<ActorId, EthAddress>,
    /// Monotone counter for fresh-id allocation.  Starts at 1
    /// (mirroring Lean's `Bridge.AddressBook` default; actor id 0
    /// is reserved for the bridge actor itself).
    next_actor_id: ActorId,
}

impl Default for AddressBook {
    /// Default impl identical to [`Self::new`].  We hand-roll
    /// rather than `#[derive(Default)]` because the derived
    /// default would set `next_actor_id` to `0` (the bridge
    /// actor's reserved id) — leading to a silent reuse of the
    /// bridge id at the first `assign` call.
    fn default() -> Self {
        Self::new()
    }
}

/// The reserved bridge-actor `ActorId`.  Matches Lean's
/// `Bridge.bridgeActor` constant.
pub const BRIDGE_ACTOR_ID: ActorId = 0;

/// The initial `next_actor_id` value in a fresh AddressBook.
/// `1` is the first non-reserved id; `0` is the bridge actor's.
pub const INITIAL_NEXT_ACTOR_ID: ActorId = 1;

impl AddressBook {
    /// Construct an empty AddressBook with `next_actor_id = 1`.
    /// Mirrors Lean's `Bridge.AddressBook.empty`.
    #[must_use]
    pub fn new() -> Self {
        Self {
            forward: BTreeMap::new(),
            reverse: BTreeMap::new(),
            next_actor_id: INITIAL_NEXT_ACTOR_ID,
        }
    }

    /// Forward lookup.  Returns the `ActorId` mapped to `addr`,
    /// or `None` if `addr` has not been assigned.  Mirrors Lean's
    /// `AddressBook.lookup`.
    #[must_use]
    pub fn lookup(&self, addr: &EthAddress) -> Option<ActorId> {
        self.forward.get(addr).copied()
    }

    /// Reverse lookup.  Returns the `EthAddress` an `ActorId` was
    /// originally assigned to, or `None` if the id has never been
    /// issued.  Mirrors Lean's `AddressBook.lookupRev`.
    #[must_use]
    pub fn lookup_reverse(&self, id: ActorId) -> Option<EthAddress> {
        self.reverse.get(&id).copied()
    }

    /// Assign a fresh `ActorId` to `addr` (or return the existing
    /// id if `addr` is already known).  Returns the resulting
    /// `ActorId` plus a `bool` flag — `true` iff a new assignment
    /// occurred.  Mirrors Lean's `AddressBook.assign` (modulo the
    /// `(book, id)` return shape — here we mutate in place and
    /// return `(id, is_new)`).
    pub fn assign(&mut self, addr: &EthAddress) -> (ActorId, bool) {
        if let Some(existing) = self.forward.get(addr).copied() {
            return (existing, false);
        }
        let fresh = self.next_actor_id;
        self.forward.insert(*addr, fresh);
        self.reverse.insert(fresh, *addr);
        // Monotone bump; overflow on `u64::MAX` is unreachable on
        // any realistic workload (2^64 addresses).
        self.next_actor_id = self.next_actor_id.checked_add(1).unwrap_or(ActorId::MAX);
        (fresh, true)
    }

    /// The next actor id this book will issue.  Diagnostic only.
    #[must_use]
    pub fn next_actor_id(&self) -> ActorId {
        self.next_actor_id
    }

    /// Number of address↔id pairs in the book.  Diagnostic only.
    #[must_use]
    pub fn len(&self) -> usize {
        self.forward.len()
    }

    /// `true` iff the book contains no pairs.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.forward.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::{AddressBook, BRIDGE_ACTOR_ID, INITIAL_NEXT_ACTOR_ID};
    use crate::action::EthAddress;

    /// Fresh AddressBook is empty and starts at `next = 1`.
    #[test]
    fn new_book_is_empty() {
        let book = AddressBook::new();
        assert_eq!(book.len(), 0);
        assert!(book.is_empty());
        assert_eq!(book.next_actor_id(), INITIAL_NEXT_ACTOR_ID);
    }

    /// `lookup` on an unknown address is `None`.
    #[test]
    fn lookup_unknown_is_none() {
        let book = AddressBook::new();
        let addr = EthAddress::from_bytes(&[1u8; 20]).unwrap();
        assert!(book.lookup(&addr).is_none());
    }

    /// First `assign` returns `(1, true)`.  Mirrors Lean's
    /// `assign_fresh_actorId` (the actor id is `nextActorId` at
    /// call time).
    #[test]
    fn first_assign_is_fresh() {
        let mut book = AddressBook::new();
        let addr = EthAddress::from_bytes(&[1u8; 20]).unwrap();
        let (id, is_new) = book.assign(&addr);
        assert_eq!(id, 1);
        assert!(is_new);
        assert_eq!(book.len(), 1);
        assert_eq!(book.next_actor_id(), 2);
    }

    /// `assign` on a known address is idempotent: returns the same
    /// id without bumping `next_actor_id`.  Mirrors Lean's
    /// `assign_idempotent_for_known`.
    #[test]
    fn second_assign_is_idempotent() {
        let mut book = AddressBook::new();
        let addr = EthAddress::from_bytes(&[1u8; 20]).unwrap();
        let (id1, _) = book.assign(&addr);
        let (id2, is_new) = book.assign(&addr);
        assert_eq!(id1, id2);
        assert!(!is_new);
        assert_eq!(book.len(), 1);
        assert_eq!(book.next_actor_id(), 2);
    }

    /// Distinct addresses get distinct ids in arrival order.
    #[test]
    fn distinct_addresses_get_distinct_ids() {
        let mut book = AddressBook::new();
        let a = EthAddress::from_bytes(&[1u8; 20]).unwrap();
        let b = EthAddress::from_bytes(&[2u8; 20]).unwrap();
        let c = EthAddress::from_bytes(&[3u8; 20]).unwrap();
        let (id_a, _) = book.assign(&a);
        let (id_b, _) = book.assign(&b);
        let (id_c, _) = book.assign(&c);
        assert_eq!(id_a, 1);
        assert_eq!(id_b, 2);
        assert_eq!(id_c, 3);
        assert_eq!(book.next_actor_id(), 4);
    }

    /// `lookup` returns the assigned id after `assign`.
    #[test]
    fn lookup_after_assign() {
        let mut book = AddressBook::new();
        let addr = EthAddress::from_bytes(&[0xabu8; 20]).unwrap();
        let (id, _) = book.assign(&addr);
        assert_eq!(book.lookup(&addr), Some(id));
    }

    /// `lookup_reverse` returns the assigned address.
    #[test]
    fn reverse_after_assign() {
        let mut book = AddressBook::new();
        let addr = EthAddress::from_bytes(&[0xab; 20]).unwrap();
        let (id, _) = book.assign(&addr);
        assert_eq!(book.lookup_reverse(id), Some(addr));
    }

    /// `BRIDGE_ACTOR_ID` is reserved and never assigned by
    /// `assign`.  Mirrors Lean: `bridgeActor` is `ActorId 0`,
    /// and `assign` starts allocating at `1`.
    #[test]
    fn bridge_actor_id_is_reserved() {
        assert_eq!(BRIDGE_ACTOR_ID, 0);
        let mut book = AddressBook::new();
        let addr = EthAddress::from_bytes(&[0u8; 20]).unwrap();
        let (id, _) = book.assign(&addr);
        assert_ne!(
            id, BRIDGE_ACTOR_ID,
            "assign must never issue the bridge actor id"
        );
    }

    /// Inserts at non-overlapping addresses preserve previously-
    /// assigned ids — the locality invariant of Lean's
    /// `assign_other_address_untouched`.
    #[test]
    fn assign_preserves_other_addresses() {
        let mut book = AddressBook::new();
        let a = EthAddress::from_bytes(&[1u8; 20]).unwrap();
        let b = EthAddress::from_bytes(&[2u8; 20]).unwrap();
        let (id_a, _) = book.assign(&a);
        assert_eq!(book.lookup(&a), Some(id_a));
        let (id_b, _) = book.assign(&b);
        // `a`'s id is unchanged.
        assert_eq!(book.lookup(&a), Some(id_a));
        // `b`'s id is fresh.
        assert_ne!(id_a, id_b);
    }
}
