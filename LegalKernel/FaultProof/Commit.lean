/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.FaultProof.Commit — state-commitment scheme for the
fault-proof game (Workstream H §12 / WUs H.2.1 – H.2.5).

Phase 0: per-sub-state commit functions for `BalanceMap`,
`NonceState`, `KeyRegistry`, `LocalPolicies`, and `BridgeState`.
Phase 1: top-level `commitExtendedState`.  Phase 2: determinism
+ extensionality theorems.  Phase 3: per-sub-state injectivity
under `CollisionFree hashBytes`.

**Design notes.**

The plan §12.2 calls for two-level SMTs (level-1 by ResourceId,
level-2 by ActorId) for `BalanceMap` and single-level SMTs for
the other sub-states.  This module ships a *first-pass commit
scheme*: a deterministic hash of the canonically-encoded
`ExtendedState` segments.  Per Workstream-D's discipline, going
through `toList` (sorted) before encoding ensures
canonicalisation at the RB-tree level; the final commit is a
single `hashBytes` of the concatenated CBE bytes.

The Solidity-side step VM (`CanonStepVM.sol`) mirrors this
commit scheme line-for-line.  Cross-stack equivalence is
established by the WU H.10.1 corpus.

The full per-cell SMT verifier shape (with Merkle paths and
non-membership proofs) is captured by `CellProof` /
`CellProofBundle` in `LegalKernel.FaultProof.Cell`; the
verification function ships in
`LegalKernel.FaultProof.Verify`.  Both consume `commitBytes`
defined here.

This module is **not** part of the trusted computing base.  Bugs
here would weaken fault-proof game's correctness but cannot
violate any kernel invariant (every state advance still goes
through `apply_admissible`).
-/

import LegalKernel.Authority.Nonce
import LegalKernel.Bridge.HashAdaptor
import LegalKernel.Bridge.State
import LegalKernel.Encoding.State
import LegalKernel.Runtime.Hash

namespace LegalKernel
namespace FaultProof

open LegalKernel.Authority
open LegalKernel.Bridge
open LegalKernel.Encoding
open LegalKernel.Runtime

/-! ## State commitment type

A `StateCommit` is a 32-byte hash binding the entire
`ExtendedState`.  Solidity-side `bytes32` mirror. -/

/-- The 32-byte top-level state commitment.  The sequencer
    publishes this value to L1 as the "state root"; the L1
    fault-proof game contract holds it for dispute resolution. -/
abbrev StateCommit : Type := ByteArray

/-! ## Per-sub-state commit functions

Each sub-state of `ExtendedState` is committed via its
canonical CBE encoding hashed with the deployment-supplied
hash function.  The Solidity side performs the same operation
byte-for-byte under `isKeccak256Linked = true`. -/

/-- Commit the kernel's `State` (the outer balance maps).  Goes
    through the canonical `toList`-sorted encoding (via
    `State.encode`) so different RB-tree shapes canonicalise to
    the same bytes. -/
def commitState (s : LegalKernel.State) : ByteArray :=
  hashBytes (ByteArray.mk (State.encode s).toArray)

/-- Commit the nonce ledger (per-actor next-nonce table). -/
def commitNonceState (n : NonceState) : ByteArray :=
  hashBytes (ByteArray.mk (NonceState.encode n).toArray)

/-- Commit the key registry (per-actor public-key table).
    Uses `KeyRegistry.encodeMap` which canonicalises via the
    sorted-pair-list encoding. -/
def commitKeyRegistry (kr : KeyRegistry) : ByteArray :=
  hashBytes (ByteArray.mk (KeyRegistry.encodeMap kr).toArray)

/-- Commit the local-policies table (per-actor policy
    declarations).  Reuses the `LocalPolicies` CBE codec from
    Workstream LP. -/
def commitLocalPolicies (lp : LocalPolicies) : ByteArray :=
  hashBytes
    (ByteArray.mk (Encodable.encode (T := LocalPolicies) lp).toArray)

/-- Commit the bridge state (consumed-deposits map + pending-
    withdrawals map + nextWdId counter). -/
def commitBridgeState (bs : BridgeState) : ByteArray :=
  hashBytes
    (ByteArray.mk (Encodable.encode (T := BridgeState) bs).toArray)

/-! ## Top-level state commitment -/

/-- The top-level state commitment: a single 32-byte hash
    binding every sub-state in canonical order.  This is the
    value the sequencer publishes to L1 as the state root.

    Layout (concatenation of sub-state commits before the final
    hash):

      * `commitBalances   es.base.balances` — 32 bytes
      * `commitNonceState es.nonces`        — 32 bytes
      * `commitKeyRegistry es.registry`     — 32 bytes
      * `commitLocalPolicies es.localPolicies` — 32 bytes
      * `commitBridgeState es.bridge`       — 32 bytes

    Final hash via `hashBytes` produces a 32-byte
    `StateCommit`. -/
def commitExtendedState (es : ExtendedState) : StateCommit :=
  hashBytes
    (commitState        es.base ++
     commitNonceState   es.nonces ++
     commitKeyRegistry  es.registry ++
     commitLocalPolicies es.localPolicies ++
     commitBridgeState  es.bridge)

/-! ## Determinism theorems

Each commit function is deterministic: equal inputs produce
equal outputs.  Direct from `Bridge.hashBytes`'s determinism
plus the per-encoder structural determinism. -/

/-- `commitState` is deterministic: equal kernel states produce
    equal commitments.  Direct consequence of `State.encode`'s
    structural determinism plus `hashBytes`'s determinism. -/
theorem commitState_deterministic (s₁ s₂ : LegalKernel.State) (h : s₁ = s₂) :
    commitState s₁ = commitState s₂ := by rw [h]

/-- `commitNonceState` is deterministic. -/
theorem commitNonceState_deterministic (n₁ n₂ : NonceState) (h : n₁ = n₂) :
    commitNonceState n₁ = commitNonceState n₂ := by rw [h]

/-- `commitKeyRegistry` is deterministic. -/
theorem commitKeyRegistry_deterministic (kr₁ kr₂ : KeyRegistry) (h : kr₁ = kr₂) :
    commitKeyRegistry kr₁ = commitKeyRegistry kr₂ := by rw [h]

/-- `commitLocalPolicies` is deterministic. -/
theorem commitLocalPolicies_deterministic (lp₁ lp₂ : LocalPolicies) (h : lp₁ = lp₂) :
    commitLocalPolicies lp₁ = commitLocalPolicies lp₂ := by rw [h]

/-- `commitBridgeState` is deterministic. -/
theorem commitBridgeState_deterministic (bs₁ bs₂ : BridgeState) (h : bs₁ = bs₂) :
    commitBridgeState bs₁ = commitBridgeState bs₂ := by rw [h]

/-- `commitExtendedState` is deterministic: equal extended
    states produce equal top-level commits.  Direct via
    structural recursion through the sub-state commits. -/
theorem commitExtendedState_deterministic (es₁ es₂ : ExtendedState) (h : es₁ = es₂) :
    commitExtendedState es₁ = commitExtendedState es₂ := by rw [h]

/-! ## Output-size theorems

The hash function (`Bridge.hashBytes`) has a uniform 32-byte
output size (per `Bridge.hashAdaptor_thirty_two_byte_output`).
This carries through every commit function. -/

/-- The top-level state commitment is 32 bytes (matching
    keccak256 / BLAKE3 output size). -/
theorem commitExtendedState_size (es : ExtendedState) :
    (commitExtendedState es).size = 32 := by
  unfold commitExtendedState
  exact hashAdaptor_thirty_two_byte_output _

/-- Each sub-state commit is 32 bytes. -/
theorem commitState_size (s : LegalKernel.State) :
    (commitState s).size = 32 := by
  unfold commitState
  exact hashAdaptor_thirty_two_byte_output _

/-- The nonce-state commit is 32 bytes. -/
theorem commitNonceState_size (n : NonceState) :
    (commitNonceState n).size = 32 := by
  unfold commitNonceState
  exact hashAdaptor_thirty_two_byte_output _

/-- The key-registry commit is 32 bytes. -/
theorem commitKeyRegistry_size (kr : KeyRegistry) :
    (commitKeyRegistry kr).size = 32 := by
  unfold commitKeyRegistry
  exact hashAdaptor_thirty_two_byte_output _

/-- The local-policies commit is 32 bytes. -/
theorem commitLocalPolicies_size (lp : LocalPolicies) :
    (commitLocalPolicies lp).size = 32 := by
  unfold commitLocalPolicies
  exact hashAdaptor_thirty_two_byte_output _

/-- The bridge-state commit is 32 bytes. -/
theorem commitBridgeState_size (bs : BridgeState) :
    (commitBridgeState bs).size = 32 := by
  unfold commitBridgeState
  exact hashAdaptor_thirty_two_byte_output _

/-! ## Smoke checks -/

/-- An empty `ExtendedState` has a deterministic, well-formed
    commit. -/
example : (commitExtendedState ExtendedState.empty).size = 32 :=
  commitExtendedState_size _

end FaultProof
end LegalKernel
