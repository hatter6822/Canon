/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.FaultProof.Cell — `CellTag`, `CellProof`,
`CellProofBundle` (Workstream H §12 / WU H.3.1).

The L1 step VM (`CanonStepVM`) doesn't have access to the full
`ExtendedState`; it only holds the 32-byte top-level state
commitment.  When the bisection game narrows to a single disputed
step, the responding party supplies Merkle proofs (`CellProof`s)
for every cell the step reads or writes; the L1 contract verifies
the proofs against the committed root and uses the cell values as
inputs to the step function.

This module defines the per-cell proof shapes consumed by both
the Lean-side `kernelStepApply` (WU H.1.2) and the Solidity-side
`CanonStepVM.executeStep`.

**Granularity rationale (WU H.3 design notes).**  Cells are tagged
by their logical sub-state + key:

  * `balance r a`   — the actor `a`'s balance at resource `r`
                      (inner BalanceMap leaf).
  * `nonce a`       — actor `a`'s next-expected nonce.
  * `registry a`    — actor `a`'s registered public key (CBE bytes).
  * `localPolicy a` — actor `a`'s declared local policy.
  * `bridgeConsumed d` — whether L1 deposit `d` has been credited.
  * `bridgePending wd` — pending L2→L1 withdrawal `wd`'s payload.
  * `bridgeNextWdId`  — the next-withdrawal-id counter.

This module is **not** part of the trusted computing base.  Bugs
here would only affect the deployment-side fault-proof tooling;
the kernel's invariant proofs are unaffected.  All theorems hold
without any new axioms.
-/

import LegalKernel.Authority.Crypto
import LegalKernel.Bridge.State
import LegalKernel.Encoding.Encodable

namespace LegalKernel
namespace FaultProof

open LegalKernel.Authority
open LegalKernel.Bridge

/-! ## `CellTag` (§12.1.4) -/

/-- The tag identifying which sub-state + cell key a `CellProof`
    references.  Each variant maps to exactly one of the five
    sub-state SMTs (the kernel's inner `BalanceMap` tree, the
    nonce ledger, the key registry, the local-policies table,
    the bridge consumed-deposit map) or to the standalone
    `bridgeNextWdId` counter (which has no SMT — it's a single
    `Nat`).

    The ordering here is the canonical CBE-encoder order; the
    Solidity-side `CellTag` enum mirrors this byte-for-byte.

    `DecidableEq` is required for cell-bundle bookkeeping (e.g.
    detecting duplicate cells in a bundle); `Repr` is for test-
    suite failure messages. -/
inductive CellTag
  /-- A `(resource, actor)` balance cell.  Frozen tag 0. -/
  | balance        (resource : ResourceId) (actor : ActorId)
  /-- An actor's next-expected nonce.  Frozen tag 1. -/
  | nonce          (actor : ActorId)
  /-- An actor's registry entry (public key).  Frozen tag 2. -/
  | registry       (actor : ActorId)
  /-- An actor's declared local policy.  Frozen tag 3. -/
  | localPolicy    (actor : ActorId)
  /-- A bridge `consumed` map entry indexed by `DepositId`.
      Frozen tag 4. -/
  | bridgeConsumed (depositId : DepositId)
  /-- A bridge `pending` map entry indexed by `WithdrawalId`.
      Frozen tag 5. -/
  | bridgePending  (withdrawalId : WithdrawalId)
  /-- The bridge `nextWdId` counter (no key needed; singleton).
      Frozen tag 6. -/
  | bridgeNextWdId
  deriving Repr, DecidableEq

/-- Project a `CellTag` to its discriminator index, for canonical
    encoding and equality dispatch.  Aligns with the Solidity-side
    enum.  The frozen tag indices are:
    0 = balance, 1 = nonce, 2 = registry, 3 = localPolicy,
    4 = bridgeConsumed, 5 = bridgePending, 6 = bridgeNextWdId. -/
def CellTag.kindIndex : CellTag → Nat
  | .balance _ _      => 0
  | .nonce _          => 1
  | .registry _       => 2
  | .localPolicy _    => 3
  | .bridgeConsumed _ => 4
  | .bridgePending _  => 5
  | .bridgeNextWdId   => 6

/-! ## `CellProof` and `CellProofBundle` (§12.1.4) -/

/-- A Merkle proof witnessing that a single cell of the
    `ExtendedState` has a particular value at the committed
    root.  The L1 step VM verifies these proofs against the
    pre-state commit before consuming the cell values.

    `cellTag` identifies the cell.  `cellValue` is the cell's
    canonical CBE-encoded value (32 zero bytes for absent
    balance / nonce; empty bytes for absent registry /
    localPolicy / bridgeConsumed / bridgePending; CBE-encoded
    `0` for absent `bridgeNextWdId`).  `siblings` is the per-
    level Merkle path from leaf to root, mirroring Workstream-D's
    `WithdrawalProof.siblings` shape.

    The proof's verifier (`verifyCellProof`) hashes the leaf,
    walks the siblings, and compares against the committed root.
    See `LegalKernel.FaultProof.Verify` for the verifier. -/
structure CellProof where
  /-- Which cell is being witnessed. -/
  cellTag    : CellTag
  /-- The cell's value at the committed root.  CBE-encoded
      bytes; the canonical "absent" markers are documented in
      the module docstring. -/
  cellValue  : ByteArray
  /-- The Merkle path siblings from leaf to root.  Length
      bounded by the SMT height (64 for the standard cell
      types). -/
  siblings   : List ByteArray
  deriving Repr

instance : DecidableEq CellProof := fun p₁ p₂ => by
  cases p₁ with
  | mk t₁ v₁ s₁ =>
    cases p₂ with
    | mk t₂ v₂ s₂ =>
      by_cases h₁ : t₁ = t₂
      · by_cases h₂ : v₁ = v₂
        · by_cases h₃ : s₁ = s₂
          · exact isTrue (by simp_all)
          · exact isFalse (fun h => h₃ (by injection h))
        · exact isFalse (fun h => h₂ (by injection h))
      · exact isFalse (fun h => h₁ (by injection h))

/-- A bundle of cell proofs covering every cell read/written by
    one step.  The bundle's contents are a function of the
    action variant (per WU H.1.4): each constructor declares
    which cells it touches, and the bundle includes a
    `CellProof` for each.  The L1 step VM consumes the bundle
    in order, verifying every proof against the pre-state
    commit. -/
structure CellProofBundle where
  /-- The proofs in canonical order (per the action variant's
      `Action.requiredCells` declaration in WU H.1.4). -/
  proofs : List CellProof
  deriving Repr

instance : DecidableEq CellProofBundle := fun b₁ b₂ => by
  cases b₁ with
  | mk p₁ =>
    cases b₂ with
    | mk p₂ =>
      by_cases h : p₁ = p₂
      · exact isTrue (by simp_all)
      · exact isFalse (fun heq => h (by injection heq))

/-! ## Helpers -/

/-- The empty cell-proof bundle.  Returned by `buildCellProofs`
    on actions whose required-cell list is empty (none of the
    current 19 Action constructors qualifies, but the empty
    bundle is a useful base case for inductive arguments). -/
def CellProofBundle.empty : CellProofBundle := { proofs := [] }

/-- Append a cell proof to a bundle.  Used by the bundle
    constructor when iterating over an action's
    `Action.requiredCells` list. -/
def CellProofBundle.push (b : CellProofBundle) (p : CellProof) :
    CellProofBundle :=
  { proofs := b.proofs ++ [p] }

/-- The size of a cell-proof bundle.  Used by gas-budget
    arguments at the Solidity-side step VM. -/
def CellProofBundle.size (b : CellProofBundle) : Nat :=
  b.proofs.length

/-! ## `Repr` smoke checks -/

/-- Spot-check: an `empty` bundle has zero proofs. -/
example : CellProofBundle.empty.size = 0 := rfl

/-- Spot-check: pushing a proof grows the bundle by one. -/
example (p : CellProof) :
    (CellProofBundle.empty.push p).size = 1 := rfl

end FaultProof
end LegalKernel
