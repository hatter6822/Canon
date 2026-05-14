<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

# Chain-Level Bridge Accounting (§7.6.4 / §7.6.5) — Engineering Plan

This document plans the work that closes audit finding **m-16**
(the only "Defer / n/a" entry in the AR triage table): promoting
the per-action bridge accounting deltas to a single inductive
theorem over a custom `BridgeReachable` predicate, mechanising
the §7.6.4 and §7.6.5 chain-level identities currently ratified
by the cross-stack fixture corpus only.

This is the smallest of the major Lean-proof workstreams: it
requires defining one new reachability predicate, proving one
structural induction theorem, and lifting two chain-level
identities.  It does **not** touch the TCB.

## Status

  * **Workstream prefix:** `CA` (Chain Accounting).  Three
    sub-units:
    - **CA.1** `BridgeReachable` predicate + induction principle.
    - **CA.2** Chain-level supply-preservation theorem.
    - **CA.3** Chain-level escrow-equation theorem.
  * **Effort estimate:** 5–8 engineer-days for one Lean
    contributor.
  * **Build-posture target:** Lean side passes all existing
    gates; two new theorems land in `LegalKernel/Bridge/`.
  * **TCB delta:** zero.  New theorems live under `Bridge/`,
    which is non-TCB.
  * **Trust-assumption delta:** zero.  Theorems depend only on
    the existing per-action bridge deltas (E-C); no new opaques
    or axioms.

## Table of contents

  * §1 Goals and non-goals
  * §2 Mathematical background
  * §3 Work-unit dependencies
  * §4 Work-unit specifications (CA.1 – CA.3)
  * §5 Sequencing and PR structure
  * §6 Quality gates
  * §7 Risk register
  * §8 Acceptance criteria
  * §9 Out-of-scope items
  * §10 References

## §1 Goals and non-goals

### §1.1 Goals

  1. **Ship `BridgeReachable`**, a reachability predicate
    restricted to admissible kernel transitions and to bridge-
    relevant actions (`deposit`, `withdraw`,
    `bridgeRegisterIdentity`, etc.).  Inductive structure with
    `refl` and `trans` constructors mirroring `Reachable`.
  2. **Ship `bridge_chain_supply_preserved`**: across any
    `BridgeReachable` chain, the sum of L1-locked balances
    plus L2-issued balances is conserved (modulo any explicit
    mint/burn allowed by the deployment law set, captured as a
    delta term).
  3. **Ship `bridge_chain_escrow_invariant`**: across any
    `BridgeReachable` chain, the L1-side escrow ledger and the
    L2-side bridge pending/consumed sets satisfy the
    §7.6.5 identity.
  4. **Retire m-16.**  Update the AR plan, the audit synthesis
    doc, and the bridge module's comment at
    `LegalKernel/Bridge/Accounting.lean:255`.

### §1.2 Non-goals

  1. **No change to the kernel TCB.**  All work is in
    `Bridge/`.
  2. **No change to per-action bridge deltas.**  E-C already
    ships these (`deposit_delta_*`, `withdraw_delta_*`,
    etc.).  CA composes them.
  3. **No new wire format.**  `BridgeReachable` is a Lean-level
    proof artefact; nothing serialises.
  4. **No off-chain replication of the cross-stack corpus.**
    The corpus continues to ratify operationally; CA adds the
    inductive theorem alongside it.
  5. **No encoder injectivity for `BridgeState` sub-trees.**
    EI.6 / EI.7 (see `docs/encoder_injectivity_plan.md`)
    own the injectivity lemmas for `BridgeState.consumed` and
    `BridgeState.pending`.  CA *consumes* those lemmas
    indirectly via its `l1EscrowMatchesL2` invariant and via
    the composition theorem of EI.8; CA does not re-prove them.
    CA may land before, after, or in parallel with EI; the
    only sub-unit dependency is that CA.3's strongest-form
    statement (extensional equality of bridge sub-states across
    a chain) presumes EI.8.  Pre-EI, CA.3 ships with the
    weaker bytes-equality form (still sound, just less
    propagating-friendly).

### §1.3 Reading guide

  * **Implementer:** read §2 then §4.  CA.1 is the structural
    setup; CA.2 and CA.3 instantiate it.
  * **Reviewer:** check the `BridgeReachable` definition
    against the existing `Reachable` shape; check the per-action
    deltas are correctly composed.

### §1.4 Glossary

  * **`Reachable s s'`.**  Kernel's existing predicate: `s'` is
    reachable from `s` via a sequence of admissible kernel
    transitions.  Reflexive-transitive closure of
    `∃ t hpre, step_impl t hpre s = .ok s'`.  Lives in
    `LegalKernel/Kernel.lean`.
  * **`BridgeReachable s s'`.**  CA's new predicate: same as
    `Reachable` but restricted to bridge-relevant transitions
    (a finite set of `Action` constructors).
  * **Per-action delta.**  A lemma asserting how a single action
    application changes the relevant accounting sums.  Already
    shipped in `LegalKernel/Bridge/Accounting.lean` for each
    bridge action.

## §2 Mathematical background

### §2.1 What §7.6.4 and §7.6.5 say

GENESIS_PLAN.md §7.6.4 (supply preservation under bridge):

> The sum of L1-locked balances plus L2-issued balances is
> preserved across any sequence of bridge transitions, modulo
> the explicit mint / burn rebates allowed by the deployment law
> set.

GENESIS_PLAN.md §7.6.5 (escrow consistency):

> For every withdrawal w pending on L2, the corresponding L1
> escrow entry exists and has not been consumed.  For every
> withdrawal w consumed on L2, the corresponding L1 escrow
> entry has been claimed.

Both identities are *chain-level*: they quantify over a sequence
of states linked by admissible bridge transitions.  Today, the
per-action deltas hold (verified per-step) but the chain-level
identity is ratified by the cross-stack corpus (which exhibits
the identity holding across recorded chains, not by Lean
theorem).

### §2.2 Why this needs a custom reachability predicate

The kernel's existing `Reachable` predicate quantifies over
*any* admissible transition.  A `Reachable s s'` chain may
include actions that are not bridge-relevant (e.g. pure
intra-L2 transfers) and which do not affect L1 escrow.  The
supply/escrow identities still hold for arbitrary `Reachable`
chains, but the proof would require case-splitting on every
action constructor (~30 cases including all the kernel laws).

`BridgeReachable` restricts to the bridge-relevant subset (~6
constructors).  Case-splits are tractable; reviewers can audit
each arm; the resulting theorem is structurally clean.

### §2.3 The induction principle

```lean
inductive BridgeReachable : ExtendedState → ExtendedState → Prop where
  | refl : ∀ s, BridgeReachable s s
  | step : ∀ {s s' s''} (action : BridgeAction)
              (hpre : action.pre s) (hstep : step_impl action.toTransition hpre s = .ok s'),
              BridgeReachable s' s'' → BridgeReachable s s''
```

where `BridgeAction` is an inductive enumeration of bridge-
relevant `Action` constructors (a Lean-level type, not a wire
extension):

```lean
inductive BridgeAction where
  | deposit (params : DepositParams)
  | withdraw (params : WithdrawParams)
  | bridgeRegisterIdentity (params : RegisterParams)
  | bridgeReplaceKey (params : ReplaceParams)
  | bridgeReward (params : RewardParams)
  | bridgeRefund (params : RefundParams)
```

(Exact list depends on the action set; CA.1 enumerates by
reading `LegalKernel/Authority/Action.lean` and selecting
every constructor whose admissibility predicate touches
`BridgeState`.)

The standard induction principle is generated by Lean's `derive`
machinery.  Inversion lemmas:
  - `bridge_reachable_inv_refl : BridgeReachable s s → True`
    (trivial; `refl` is one constructor).
  - `bridge_reachable_inv_step : BridgeReachable s s'' →
    s = s'' ∨ ∃ s' action hpre hstep r, …`.

### §2.4 The chain-supply identity

```lean
def bridgeSupplySum (s : ExtendedState) : Nat :=
  s.bridge.l1Escrow.totalLocked + s.state.balances.totalSupply

theorem bridge_chain_supply_preserved
    (h : BridgeReachable s s') :
  bridgeSupplySum s = bridgeSupplySum s' + bridgeRebates s s'
```

where `bridgeRebates s s'` is the cumulative mint/burn delta
from the deployment law set's explicit rebate machinery
(zero if the deployment has no rebate laws).

Proof: induction on `BridgeReachable`.
  - Base case (`refl`): `bridgeRebates s s = 0` (also a small
    lemma); LHS = RHS.
  - Inductive step: by `bridge_action_delta_supply` (the per-
    action lemma for the specific `BridgeAction`), the supply
    changes by exactly the rebate delta for that action; sum
    accumulates across the chain.

### §2.5 The escrow-consistency identity

```lean
def l1EscrowMatchesL2 (s : ExtendedState) : Prop :=
  (∀ w ∈ s.bridge.pending,
     ∃ e ∈ s.bridge.l1Escrow.entries,
       e.withdrawalId = w.id ∧ ¬ e.claimed) ∧
  (∀ d ∈ s.bridge.consumed,
     ∃ e ∈ s.bridge.l1Escrow.entries,
       e.depositId = d ∧ e.claimed)

theorem bridge_chain_escrow_invariant
    (h_init : l1EscrowMatchesL2 s)
    (h_chain : BridgeReachable s s') :
  l1EscrowMatchesL2 s'
```

Read: the L1-L2 escrow invariant is preserved across any
`BridgeReachable` chain.  Initial assumption `h_init` requires
the genesis state satisfy the invariant; deployment-level
proof obligation.

Proof: induction on `BridgeReachable`.  Each per-action delta
lemma either:
  - Adds a `pending` entry and a corresponding non-claimed
    `l1Escrow` entry (the deposit-/withdraw-initiate cases).
  - Moves a `pending` entry to `consumed` and marks the
    `l1Escrow` entry claimed (the deposit-/withdraw-finalise
    cases).
  - Leaves both unchanged (the register-identity / replace-key
    cases).

The invariant is preserved arm-by-arm.

## §3 Work-unit dependencies

```
CA.1 (BridgeReachable + BridgeAction)
   │
   ├──► CA.2 (supply-preservation theorem)
   │
   └──► CA.3 (escrow-consistency theorem)
```

CA.1 is the structural setup; CA.2 and CA.3 may land in either
order or in parallel after CA.1.

## §4 Work-unit specifications

---

### CA.1 — `BridgeReachable` predicate and `BridgeAction` enumeration

**Finding map.**  m-16 prerequisite.

**Scope.**  `LegalKernel/Bridge/Reachable.lean` (new).

**Implementation steps.**

  1. Create `LegalKernel/Bridge/Reachable.lean`.
  2. Define `BridgeAction` inductive (enumerate bridge-relevant
    constructors).
  3. Define `BridgeAction.toAction : BridgeAction → Action`
    (the injection back into the full action type).
  4. Define `BridgeAction.pre : BridgeAction → ExtendedState → Prop`
    (the precondition; delegate to the underlying action's
    pre).
  5. Define `BridgeReachable` inductive.
  6. Prove the induction principle (Lean generates it
    automatically; ensure no `relaxedAutoImplicit` warnings).
  7. Prove `BridgeReachable.refl`, `BridgeReachable.trans` as
    lemmas (for ergonomic use).
  8. Prove `BridgeReachable_implies_Reachable`:
    `BridgeReachable s s' → Reachable s s'`.  This is the
    *embedding* lemma; it asserts that every BridgeReachable
    chain is a sub-chain of an arbitrary Reachable chain.

**Acceptance criteria.**

  * `BridgeReachable.refl`, `.trans`, embedding lemma all land.
  * `BridgeAction.toAction` is injective (one-line proof).
  * `count_sorries` clean.

**Test plan.**

  * Value-level: build a 3-step BridgeReachable chain by hand
    (deposit → register → withdraw) and confirm it elaborates.
  * Term-level API tests for the new predicate and lemmas.

**Reviewer checklist.**

  * Enumeration matches every bridge-touching `Action`
    constructor in `Authority/Action.lean` (no omissions).
  * `pre` predicates exactly match the corresponding `Action`
    `pre`s.

**Risk.**  Low.

**Effort.**  ~2 engineer-days.

---

### CA.2 — `bridge_chain_supply_preserved`

**Finding map.**  Closes §7.6.4 chain-level identity (m-16).

**Scope.**  `LegalKernel/Bridge/Accounting.lean`.

**Implementation steps.**

  1. State the theorem (signature in §2.4).
  2. Define `bridgeRebates` and prove a small lemma
    `bridgeRebates_refl : bridgeRebates s s = 0`.
  3. Prove the theorem by induction on `BridgeReachable`.
    The inductive step case-splits on `BridgeAction`; each arm
    discharges via the existing per-action delta lemma.
  4. Update the docstring of `Accounting.lean` to cite the
    new theorem.
  5. Remove the comment at
    `LegalKernel/Bridge/Accounting.lean:255` (`"plan's
    existing 'deferred' provisions for cross-stack
    verification"`) and replace with a content-describing line
    referencing the new theorem.

**Acceptance criteria.**

  * Theorem ships; `#print axioms` clean.
  * `Accounting.lean:255` deferral comment removed.

**Test plan.**

  * Value-level: a 3-step chain (deposit + transfer + withdraw)
    where the supply should be preserved modulo a known rebate.
  * Term-level API test.

**Reviewer checklist.**

  * Inductive case-split is exhaustive (every `BridgeAction`
    constructor handled).
  * Per-action delta lemmas cited by name in each arm.
  * Rebate handling matches the deployment-law-set semantics
    (no spurious rebate terms in zero-rebate deployments).

**Risk.**  Low-medium.  Standard structural induction.

**Effort.**  ~2 engineer-days.

---

### CA.3 — `bridge_chain_escrow_invariant`

**Finding map.**  Closes §7.6.5 chain-level identity (m-16).

**Scope.**  `LegalKernel/Bridge/Accounting.lean`.

**Implementation steps.**

  1. State `l1EscrowMatchesL2 : ExtendedState → Prop`.
  2. State the theorem (signature in §2.5).
  3. Prove by induction on `BridgeReachable`.  Inductive step
    case-split on `BridgeAction`, discharge per arm.
  4. Add a deployment-level lemma `genesis_satisfies_escrow`
    that asserts the genesis state has an empty escrow ledger
    and trivially satisfies `l1EscrowMatchesL2`.

**Acceptance criteria.**

  * Theorem ships; `#print axioms` clean.
  * `genesis_satisfies_escrow` lemma lands.

**Test plan.**

  * Value-level: a deposit-then-withdraw chain; assert
    `l1EscrowMatchesL2` holds at every prefix.
  * Term-level API test.

**Reviewer checklist.**

  * Definition of `l1EscrowMatchesL2` uses the `entries` field
    of the deployment-supplied `L1EscrowLedger` shape (consult
    `Bridge/L1Escrow.lean` for the exact type; if absent,
    introduce a small structural witness shape under CA.3 —
    deployment-supplied semantics, not a new opaque).
  * Per-action arm discharges use the bridge `Accounting.lean`
    delta lemmas.

**Risk.**  Low-medium.

**Effort.**  ~3 engineer-days.

---

## §5 Sequencing and PR structure

```
PR-1: CA.1     BridgeReachable predicate + embedding lemma
PR-2: CA.2     Supply-preservation theorem
PR-3: CA.3     Escrow-consistency theorem + m-16 closure
```

CA.1 first.  CA.2 and CA.3 parallel.  The last PR to land
should also:
  - Update `docs/audit_remediation_plan.md` §2 to mark m-16
    "Remediated under workstream CA".
  - Update `docs/audits/19-findings-and-followups.md` "Open
    follow-ups" to remove m-16.
  - Update CLAUDE.md status note for Workstream E-C from
    "chain-level §7.6.4 / §7.6.5 follow-up" to "Complete".

## §6 Quality gates

  * `lake build LegalKernel.Bridge.*`
  * `lake test`
  * `lake exe count_sorries`
  * `lake exe tcb_audit`
  * `lake exe deferral_audit` (the
    `Accounting.lean:255` comment removal must not introduce
    a new forbidden phrase)

## §7 Risk register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Bridge action set incomplete in CA.1 | Medium | High | Read every `Action` constructor; add a one-line comment per skipped non-bridge action documenting why it's skipped |
| `bridgeRebates` definition admits unsoundness if the deployment law set has unexpected rebate semantics | Low | High | Default zero-rebate; document the deployment-level proof obligation |
| `L1EscrowLedger` shape not yet defined as a Lean type | Medium | Medium | CA.3 introduces a deployment-supplied witness shape under `Bridge/L1Escrow.lean`; cross-stack corpus validates the shape |
| Theorem statements drift from the GENESIS_PLAN §7.6.4 / §7.6.5 wording | Medium | Low | Reviewer cross-checks the statement against the GENESIS_PLAN section text |

## §8 Acceptance criteria

CA is **complete** when:

  1. `BridgeReachable`, `BridgeAction`, and the embedding
    lemma ship in `Bridge/Reachable.lean`.
  2. `bridge_chain_supply_preserved` ships in
    `Bridge/Accounting.lean`.
  3. `bridge_chain_escrow_invariant` ships in
    `Bridge/Accounting.lean`.
  4. m-16 retired across:
     - `docs/audit_remediation_plan.md` §2 triage table
     - `docs/audits/19-findings-and-followups.md` open follow-
       ups list
     - `LegalKernel/Bridge/Accounting.lean:255` comment
     - CLAUDE.md "Workstream E-C" status (drop the "chain-level
       §7.6.4 / §7.6.5 follow-up" note)
  5. `#print axioms` on each new theorem prints a subset of
    `[propext, Classical.choice, Quot.sound]`.
  6. CLAUDE.md "Headline theorems" table adds two rows
    for the new theorems.

## §9 Out-of-scope items

  * **Cross-actor escrow accounting** (multiple withdrawing
    actors sharing a single L1 escrow entry).  v2 concern;
    current MVP is one-actor-per-entry.
  * **Multi-resource escrow accounting** (a single L1 escrow
    locking multiple ResourceIds).  MVP is one resource per
    entry.
  * **L1-side proof of the escrow identity.**  CA proves the
    Lean side; the Solidity bridge contract is responsible
    for the L1 side and is validated by the cross-stack corpus.
  * **`Reachable`-level theorem variants** (i.e. the same
    identities for arbitrary `Reachable` chains).  CA's
    `BridgeReachable_implies_Reachable` lift is sufficient
    for any downstream consumer that wants the broader
    quantification.

## §10 References

  * `docs/GENESIS_PLAN.md` §7.6.4 and §7.6.5 (the identities
    CA mechanises).
  * `docs/ethereum_integration_plan.md` §C (per-action bridge
    deltas).
  * `docs/audit_remediation_plan.md` §2 (m-16 triage).
  * `docs/audits/19-findings-and-followups.md` (m-16 description).
  * `LegalKernel/Bridge/Accounting.lean` — current per-action
    deltas.
  * `LegalKernel/Bridge/Admissible.lean` — per-action
    admissibility lemmas.
  * `LegalKernel/Kernel.lean` §4.9 — existing `Reachable`
    predicate.

---

**End of plan.**  Landing CA retires the only "Defer / n/a"
entry in the AR triage table.
