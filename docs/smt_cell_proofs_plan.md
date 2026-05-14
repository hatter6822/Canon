<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

# SMT-Form Cell Proofs — Engineering Plan

This document plans the cross-stack soundness work needed to
replace witness-state cell proofs in Workstream H's fault-proof
chain with sparse-Merkle-tree (SMT) cell proofs.  Closing this
work retires the documented mitigation note in
`docs/GENESIS_PLAN.md` §15B (lines 5170–5187) and the
`solidity/src/lib/StepVMMerkle.sol:35` deferral marker.

The Lean side currently proves byte-equality of state commitments
under collision-freedom; the Solidity side cannot afford to
re-hash the full witness state on L1 (gas-prohibitive).  Today's
mitigation: cross-stack fixture corpus ratifies the honest case
operationally, and "Production deployments MUST audit cellProof
submissions off-chain until the SMT path is shipped"
(GENESIS_PLAN §15B).  This plan ships the SMT path.

## Status

  * **Workstream prefix:** `SC` (SMT Cells).  Three sub-units:
    - **SC.1** Lean SMT spec + per-cell proof scheme.
    - **SC.2** Solidity SMT verifier (gas-efficient).
    - **SC.3** Cross-stack soundness theorem + corpus widening.
  * **Effort estimate:** 6–9 calendar weeks for one Lean-Solidity
    engineer.  Parallelisable into 4–6 weeks if Lean and Solidity
    are split between two engineers after SC.1.
  * **Build-posture target:** Lean side passes all existing gates
    plus a new theorem `cellProof_sound_under_collision_free`;
    Solidity side adds an `SmtVerifier` library and updates
    `StepVMMerkle.sol` to call it; cross-stack corpus extends
    with adversarial cell-proof attempts.
  * **TCB delta:** zero.  The new theorem lives in
    `LegalKernel/FaultProof/Cell.lean` (non-TCB).
  * **Trust-assumption delta:** zero.  Same `CollisionFree
    hashBytes` hypothesis as the existing chain.

## Table of contents

  * §1 Goals and non-goals
  * §2 Mathematical background
    * §2.1 The cell-proof concept
    * §2.2 Why witness-state cell proofs are gas-prohibitive
    * §2.3 The sparse-Merkle-tree structure
    * §2.4 The soundness theorem we ship
  * §3 Work-unit dependencies
  * §4 Work-unit specifications (SC.1 – SC.3)
  * §5 Sequencing and PR structure
  * §6 Quality gates
  * §7 Risk register
  * §8 Acceptance criteria
  * §9 Out-of-scope items
  * §10 References

## §1 Goals and non-goals

### §1.1 Goals

  1. **Replace the witness-state cell-proof scheme with SMT cell
    proofs.**  The fault-proof game's bisection step currently
    submits the full witness sub-state at each cell read; the
    SMT scheme submits only an O(log n) Merkle path.
  2. **Ship the Lean theorem `cellProof_sound_under_collision_free`.**
    The theorem certifies that a valid SMT cell proof witnesses
    the cell's value uniquely under `CollisionFree hashBytes`.
  3. **Ship the Solidity `SmtVerifier` library** that verifies
    cell proofs in ≤ 50k gas per cell (target).
  4. **Extend the cross-stack fixture corpus** with adversarial
    cell-proof attempts to mechanically ratify cross-stack
    soundness.
  5. **Retire the deferral markers** in
    `solidity/src/lib/StepVMMerkle.sol:35`, GENESIS_PLAN §15B
    lines 5170–5187, and `LegalKernel/FaultProof/Cell.lean:52`.

### §1.2 Non-goals

  1. **No change to the bisection-game state machine.**  The
    convergence theorem (`bisection_converges_after_enough_rounds`)
    and the honesty theorem
    (`honest_challenger_wins_against_invalid_state_root`) are
    unchanged.
  2. **No change to the state-commitment scheme at the top
    level.**  `commitExtendedState` continues to return a
    single 32-byte root; SMT is a *cell-proof shape* change, not
    a top-level commit change.
  3. **No change to `step_impl`.**  Lean kernel transitions are
    untouched.
  4. **No proof of optimality.**  We do not prove that SMT is
    the minimum-gas cell-proof scheme.  We prove it is sound and
    show it is gas-affordable.

### §1.3 Reading guide

  * **Lean implementer:** read §2.3 + §2.4 + SC.1.
  * **Solidity implementer:** read §2.2 + §2.3 + SC.2.
  * **Cross-stack reviewer:** read §2.4 + SC.3 + §8 (acceptance).

### §1.4 Glossary

  * **Cell.**  A logical state slot: e.g. `balances[a, r]`,
    `nonces[a]`, `keys[a]`.  The fault-proof bisection identifies
    a single cell whose value the disputing parties disagree
    about.
  * **Cell proof.**  A piece of data submitted to L1 that
    establishes the value of one cell relative to a state root
    commitment.
  * **Witness-state cell proof.**  The current scheme: submit
    the *entire* sub-state (e.g. all balances), re-hash on L1,
    confirm it matches the root, then read out the cell value.
    Sound (modulo collision-resistance); expensive (linear in
    the sub-state size).
  * **SMT cell proof.**  The proposed scheme: submit a Merkle
    path from the cell to the root.  Sound (modulo collision-
    resistance); cheap (log in the sub-state size).
  * **Sparse Merkle Tree.**  A complete binary tree of depth
    256 (one leaf per 256-bit key); empty subtrees compress to
    a canonical zero hash.

## §2 Mathematical background

### §2.1 The cell-proof concept

The fault-proof bisection narrows disagreement to a single
kernel step `s ↦ s'` and a single cell read within that step's
witness state.  For example: "the disputing parties agree on
`s` and on the action being applied, but disagree on whether
`balances[a, r] = 100` or `= 200` after the step".

To resolve this, the L1 contract requires the *responder* to
submit:
  1. A claimed cell value `v`.
  2. A *cell proof* that `v` is the value of the cell relative
    to a state-commitment root agreed by both parties.

The L1 contract verifies the cell proof against the root; if it
verifies, `v` is the canonical value of the cell and the
adjudication can proceed.

### §2.2 Why witness-state cell proofs are gas-prohibitive

The current cell-proof scheme submits the *entire* relevant
sub-state (e.g. the `BalanceMap`) plus an opening of the state
commitment.  The L1 verifier then:

  1. Re-hashes the sub-state using `keccak256`.
  2. Confirms the result matches the agreed sub-state root.
  3. Reads the cell directly from the submitted sub-state.

This is sound but costs O(|sub-state|) gas.  For a `BalanceMap`
with 10k actors × 5 resources = 50k entries, the re-hash alone
exceeds the L1 block gas limit.  Today's mitigation: the
responder is the sequencer (which knows the full state), and
deployments audit cell-proof submissions off-chain.  This works
for the honest case but does not have a *mechanical* L1-side
defence against an adversarial responder submitting a wrong
cell-value with a sub-state that happens to re-hash correctly
(which, under collision-resistance, is infeasible — but the L1
side cannot verify collision-resistance, so the property is
"honest-case only" today).

### §2.3 The sparse-Merkle-tree structure

A sparse Merkle tree (SMT) over a 256-bit key space:

  * Depth 256, complete binary tree.
  * Each leaf is `hash(key, value)` if the key is set, or the
    canonical zero `H_0 = hash("EMPTY_LEAF")` if unset.
  * Each internal node is `hash(left_child, right_child)`.
  * Empty sub-trees at depth `d` have a fixed `H_d` value
    pre-computed off-chain (256 constants, one per depth, each
    a 32-byte hash).

A cell proof for a key `k` consists of:
  - The claimed value `v`.
  - The sibling hash at each of the 256 levels along the path
    from leaf to root.

L1 verification:
  1. Hash the leaf: `leaf = hash(k, v)` (or `H_0` if claiming
    `v = ⊥`).
  2. For each level from 0 to 255: combine `leaf` with the
    sibling according to the corresponding bit of `k`, producing
    the next-level hash.
  3. After 256 iterations, the result should equal the agreed
    root.

Gas: 256 `keccak256` calls × ~30 gas + minor overhead ≈ 10k gas
(well within budget).

**Optimisation: sparse-path compression.**  A typical SMT has
many empty siblings (the canonical zero per depth).  The proof
can omit them and use a 256-bit bitmask indicating which
siblings are non-zero.  Verification reads each bit; when set,
the next sibling comes from the proof bytes; when unset, the
canonical `H_d` is used.  This reduces typical proof size from
8192 bytes to ~200 bytes for a non-empty path.

### §2.4 The soundness theorem we ship

```
theorem cellProof_sound_under_collision_free
    (h_cr : CollisionFree hashBytes)
    (root : ByteArray) (key : Key) (v : Val)
    (proof : CellProof) :
  verifyCellProof root key v proof = true →
  ∃ (m : TreeMap Key Val compare),
    smtRoot m = root ∧ m[key]? = some v
```

Read: if the L1 verifier accepts a cell proof for `(root, key, v)`,
then there exists a unique map `m` whose SMT root is `root`
and whose value at `key` is `v`.  Uniqueness follows from
collision-resistance: two distinct maps cannot share an SMT
root.

The companion *adversarial* statement is:

```
theorem cellProof_no_value_substitution
    (h_cr : CollisionFree hashBytes)
    (root : ByteArray) (key : Key) (v₁ v₂ : Val)
    (proof₁ proof₂ : CellProof) :
  verifyCellProof root key v₁ proof₁ = true →
  verifyCellProof root key v₂ proof₂ = true →
  v₁ = v₂
```

Read: under collision-resistance, no two distinct cell-values
can be witnessed for the same `(root, key)`.  This is the
load-bearing property: an adversarial responder cannot use a
forged SMT proof to substitute a wrong cell value.

## §3 Work-unit dependencies

```
SC.1 (Lean spec + soundness)
   │
   ▼
SC.2 (Solidity verifier)  ◄── implements SC.1's spec
   │
   ▼
SC.3 (cross-stack corpus + retirement)
```

SC.1 must land first (the Lean theorem is the contract the
Solidity implementation conforms to).  SC.2 and SC.3 may overlap.

## §4 Work-unit specifications

---

### SC.1 — Lean SMT spec + soundness theorem

**Finding map.**  Closes the "SMT cell proofs (deferred follow-up)"
note in GENESIS_PLAN §15B and the deferral marker in
`Cell.lean:52`.

**Scope.**  `LegalKernel/FaultProof/Cell.lean`,
`LegalKernel/FaultProof/Smt.lean` (new), and the test fixtures
in `LegalKernel/Test/FaultProof/Smt.lean` (new).

**Math / proof outline.**

Three building blocks:

  1. **SMT root computation.**  Define `smtRoot : TreeMap Key Val
    compare → ByteArray` recursively over the tree.  For a
    256-bit `Key` namespace and 32-byte hash output:
     ```lean
     def smtRoot (m : TreeMap Key Val compare) : ByteArray :=
       smtRootAux m 256
     where smtRootAux : TreeMap Key Val compare → Nat → ByteArray
       | _, 0     => leafHash key val   -- fully resolved key path
       | m, d + 1 => hashBytes (smtRootAux (m.filter (·.bit d = 0)) d ++
                                smtRootAux (m.filter (·.bit d = 1)) d)
     ```
    (Pseudocode; the real definition uses `decide` on the bit
    of the key plus the canonical empty-subtree constants `H_d`
    for empty sub-maps.)
  2. **Cell-proof verification.**  Define `verifyCellProof :
    ByteArray → Key → Val → CellProof → Bool`:
     ```lean
     structure CellProof where
       siblings : List ByteArray  -- length ≤ 256
       bitmask  : ByteArray       -- 256-bit; 1 = non-empty sibling
     ```
    Verifier walks 256 levels, reconstructing each ancestor hash.
  3. **Soundness theorem.**  As §2.4.  Proof structure:
     - Induction on the 256-deep path.
     - Base case: at depth 0, the leaf hash uniquely determines
       `(key, val)` under collision-resistance.
     - Inductive step: at depth `d + 1`, the parent hash uniquely
       determines `(left, right)` under collision-resistance;
       one of those is the next path node, the other is the
       sibling.

The collision-resistance hypothesis is the same `CollisionFree
hashBytes` predicate the existing chain uses
(`LegalKernel/Runtime/Hash.lean`).

**Implementation steps.**

  1. Create `LegalKernel/FaultProof/Smt.lean`.  Define
    `CellProof`, `smtRoot`, `verifyCellProof`.
  2. Add 256 canonical empty-subtree constants `emptySubtreeHash
    : Fin 256 → ByteArray` (computed at file load via a small
    `IO` initialiser, or hard-coded).
  3. State and prove `cellProof_sound_under_collision_free` and
    `cellProof_no_value_substitution`.
  4. Update `Cell.lean` to expose the SMT-form alongside the
    existing witness-state form.  Both schemes ship; the SMT
    form becomes the recommended one.
  5. Add test fixtures: `LegalKernel/Test/FaultProof/Smt.lean`
    with value-level coverage of:
     - Empty map: smtRoot returns the canonical depth-256 empty
       hash.
     - Single-cell map: verifyCellProof accepts the correct
       value, rejects every other value.
     - Two-cell map: both cell proofs verify; mutual exclusion.

**Acceptance criteria.**

  * Theorems land; `#print axioms` clean.
  * All test fixtures pass.
  * `count_sorries`, `tcb_audit`, etc. all green.
  * `deferral_audit` passes (cell-proof deferral marker removed
    from `Cell.lean`).

**Test plan.**

  * Value-level: fixtures above.
  * Term-level API stability for both new theorems.
  * Property test (via Lex codegen if available): 100 random
    maps × 10 random cell proofs each.

**DoD.**

  * [ ] `Smt.lean` shipped with `smtRoot`, `verifyCellProof`,
    soundness theorem.
  * [ ] `cellProof_no_value_substitution` shipped.
  * [ ] Test fixtures land.
  * [ ] `Cell.lean:52` deferral marker removed.

**Verification.**

```bash
lake build LegalKernel.FaultProof.Smt
lake build LegalKernel.Test.FaultProof.Smt
lake test
lake exe count_sorries
lake exe deferral_audit
```

**Reviewer checklist.**

  * `smtRoot` definition matches the §2.3 structure exactly
    (depth 256, canonical empty hashes).
  * Soundness theorem hypothesis is exactly `CollisionFree
    hashBytes`, not a stronger / weaker variant.
  * No new opaque or axiom.
  * Empty-subtree constants are computed deterministically; if
    hard-coded, a comment explains the derivation.

**Risk.**  Medium.  The inductive soundness proof has a subtle
sibling-resolution step; the collision-resistance argument must
discharge both the "left child unique" and "right child unique"
sub-obligations.

**Effort.**  ~10–15 engineer-days.

---

### SC.2 — Solidity `SmtVerifier` library

**Finding map.**  Closes the deferral marker in
`solidity/src/lib/StepVMMerkle.sol:35`.

**Scope.**  `solidity/src/lib/SmtVerifier.sol` (new),
`solidity/src/lib/StepVMMerkle.sol` (refactor),
`solidity/test/SmtVerifier.t.sol` (new).

**Math / soundness.**

Solidity port of the §2.3 verifier.  The library exposes:

```solidity
library SmtVerifier {
    /// 256 canonical empty-subtree hashes, pre-computed.
    bytes32[256] internal constant EMPTY_HASHES = [
        // hashBytes("EMPTY_LEAF"),
        // hashBytes(EMPTY_HASHES[0], EMPTY_HASHES[0]),
        // ...
    ];

    function verifyCellProof(
        bytes32 root,
        bytes32 key,
        bytes32 value,
        bytes calldata proofData
    ) external pure returns (bool);

    function recomputeRoot(
        bytes32 key,
        bytes32 value,
        bytes calldata proofData
    ) external pure returns (bytes32);
}
```

`proofData` layout:
  - Bytes 0–31: 256-bit `bitmask` (1 = non-empty sibling at
    that depth).
  - Bytes 32 onwards: concatenation of non-empty sibling
    hashes, one 32-byte hash per set bit in the bitmask.

The verifier:
  1. Compute the leaf hash: `keccak256(abi.encodePacked(key,
    value))`.
  2. Walk the 256-bit key from LSB to MSB.  At each level `d`:
     - If `bitmask[d] = 1`: read the next 32-byte sibling from
       `proofData`.  Otherwise: use `EMPTY_HASHES[d]`.
     - If `key`'s bit `d` is 0: `current = hash(current, sibling)`.
     - If `key`'s bit `d` is 1: `current = hash(sibling, current)`.
  3. After 256 iterations: return `current == root`.

**Implementation steps.**

  1. Pre-compute `EMPTY_HASHES` off-chain via a small Foundry
    script.  Hard-code the 256 constants in
    `SmtVerifier.sol` with a one-line comment explaining the
    derivation.
  2. Implement `recomputeRoot` and `verifyCellProof` per the
    algorithm.  Use `assembly` blocks for the keccak256 calls
    to save gas.
  3. Refactor `StepVMMerkle.sol` to delegate to `SmtVerifier`.
    Remove the deferral marker at line 35.
  4. Add `solidity/test/SmtVerifier.t.sol` with:
     - Round-trip: build a map, compute root, generate proof,
       verify.
     - Negative: tamper with the value; verify fails.
     - Negative: tamper with a sibling hash; verify fails.
     - Gas: measure `verifyCellProof` for representative paths
       (full-empty, full-non-empty, mixed).

**Acceptance criteria.**

  * `forge build` succeeds.
  * `forge test` passes for `SmtVerifier.t.sol`.
  * `verifyCellProof` costs ≤ 50k gas for a typical proof (≥1
    non-empty sibling).
  * `forge fmt --check` clean.

**Test plan.**

  * Round-trip: 50+ test maps with random keys / values.
  * Adversarial: tampered value, tampered sibling, tampered
    bitmask.
  * Gas: gas-snapshot regression test.

**Risk.**  Medium.  Assembly blocks for keccak256 calls are
gas-critical but error-prone; review carefully.

**Effort.**  ~7 engineer-days.

---

### SC.3 — Cross-stack soundness + corpus + retirement

**Finding map.**  Closes the GENESIS_PLAN §15B note "Production
deployments MUST audit cellProof submissions off-chain until
the SMT path is shipped".

**Scope.**  `solidity/test/CrossStack/SmtCorpus.t.sol` (new),
cross-stack fixture corpus extension, documentation updates.

**Implementation steps.**

  1. Extend cross-stack fixture corpus with SMT cell proofs:
     - 50+ honest proofs: each `(map, key, value, proof)` tuple
       generated by the Lean reference, verified by both sides.
     - 50+ adversarial proofs: tampered values / siblings;
       both sides must reject.
  2. Add `solidity/test/CrossStack/SmtCorpus.t.sol` that loads
    fixtures from a CBE-encoded golden file and runs each
    through `SmtVerifier`.
  3. Add Lean-side counterpart at
    `LegalKernel/Test/CrossStack/Smt.lean` (or extend the
    existing CrossStack suite).
  4. Update `docs/GENESIS_PLAN.md` §15B: replace the deferral
    note with a forward-reference to this plan's completion.
  5. Update `solidity/src/lib/StepVMMerkle.sol:35`: remove the
    `"Production SMT-optimised version (deferred)"` comment.
  6. Update `CLAUDE.md` headline-theorem table: add a row for
    `cellProof_sound_under_collision_free` and
    `cellProof_no_value_substitution`.

**Acceptance criteria.**

  * Cross-stack corpus runs in CI on both Lean and Solidity
    sides; every fixture passes on both.
  * Adversarial corpus rejected uniformly.
  * Documentation references the new theorems.
  * The "audit cellProof submissions off-chain" mitigation note
    is retired.

**Test plan.**

  * Run the cross-stack corpus on both sides; CI passes.
  * Adversarial fuzzer: generate 1000 random tamper patterns;
    both sides reject.

**DoD.**

  * [ ] Cross-stack corpus extended.
  * [ ] Both sides pass.
  * [ ] Documentation updated.
  * [ ] Deferral markers retired.

**Verification.**

```bash
lake test                                        # Lean side
forge test --match-test SmtCorpus                # Solidity side
lake exe deferral_audit                          # marker removal
```

**Reviewer checklist.**

  * Honest fixtures cover edge cases: empty map, single cell,
    full map, max-depth path.
  * Adversarial fixtures cover the load-bearing attack: forged
    sibling.
  * Documentation updates land in the same PR as the corpus
    landing.

**Risk.**  Low.  The hard work is in SC.1 / SC.2; SC.3 is
integration.

**Effort.**  ~4 engineer-days.

---

## §5 Sequencing and PR structure

```
PR-1: SC.1   (~2 weeks)        Lean spec + soundness
PR-2: SC.2   (~1.5 weeks)      Solidity verifier
PR-3: SC.3   (~1 week)         Cross-stack corpus + retirement
```

SC.1 must land first; SC.2 implements its spec.  SC.3 ratifies
both.

## §6 Quality gates

  * Lean: `lake build`, `lake test`, `lake exe count_sorries`,
    `lake exe tcb_audit`, `lake exe deferral_audit`.
  * Solidity: `forge build`, `forge test`, `forge fmt --check`,
    gas-snapshot regression.
  * Cross-stack corpus passes both sides.

## §7 Risk register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SC.1 soundness proof more complex than sketched | Medium | High | Budget 15 days for proof; if blocked, split into sub-units (depth-bounded variant first, then full 256 depth) |
| Solidity `assembly` block introduces a subtle keccak256 bug | Low | High | Reference well-known patterns (Solady, OpenZeppelin); fuzz-test extensively |
| Gas target (50k) unachievable | Low | Medium | Document the achieved number; the spec is "≤ 50k for typical paths" — adjust if needed |
| Adversarial corpus misses an attack class | Medium | Medium | Pair with a property-test fuzzer for both sides |
| Migration path: existing fault-proof games in-flight with witness-state cell proofs | Low | Medium | Both schemes ship simultaneously; gate the SMT scheme behind a deployment flag in `CanonFaultProofGame` for the first deployment; cut over after a stabilisation period |

## §8 Acceptance criteria

SC is **complete** when:

  1. `cellProof_sound_under_collision_free` and
    `cellProof_no_value_substitution` ship in Lean.
  2. `SmtVerifier.sol` ships in Solidity with `verifyCellProof`
    at ≤ 50k gas for typical paths.
  3. Cross-stack corpus extended with 100+ fixtures; CI passes
    both sides.
  4. GENESIS_PLAN §15B deferral note retired.
  5. `solidity/src/lib/StepVMMerkle.sol:35` deferral marker
    removed.
  6. `LegalKernel/FaultProof/Cell.lean:52` deferral marker
    removed.
  7. CLAUDE.md headline-theorem table includes both new
    theorems.

## §9 Out-of-scope items

  * **ZK proofs over SMT paths** (Phase 7 advanced).  An SNARK
    over the verifier reduces gas further but is out of scope.
    Phase 7.C (see `docs/phase_7_plan.md`) covers SNARK
    primitives; an SMT-over-SNARK follow-up is a portfolio
    item, not part of SC.
  * **Variable-depth SMT** (sparse-by-depth-prefix tree).
    A constant 256-depth tree is the design (see OQ-H-1 in
    `docs/open_questions.md` §6; resolved in favour of
    uniform-depth).  Alternative shapes are future research.
  * **State-rent / cell-eviction.**  Cells stay forever; eviction
    is a Phase 7 concern.
  * **Cross-cell consistency proofs** (e.g. "the sum of all
    balance cells equals total supply").  These are conservation
    theorems, not cell proofs; they live elsewhere in the chain
    (Workstream CA in `docs/chain_level_accounting_plan.md`).
  * **Rust observer port of `verifyCellProof`.**  The Rust
    fault-proof observer (`docs/rust_host_runtime_plan.md`
    RH-G) only *constructs* cell proofs against the canonical
    Lean replay; verification happens on L1 (the Solidity
    `SmtVerifier`).  The observer therefore needs a *cell-proof
    generator* in Rust but not a verifier.  Cell-proof
    generation is straightforward (walk the canonical map,
    collect siblings); document the API in the RH workstream's
    observer plan.

## §10 References

  * `docs/GENESIS_PLAN.md` §15B (state-commit and cell-proof
    sections; lines 5170–5187 carry the deferral note).
  * `docs/fault_proof_design.md` §8 (future work).
  * `docs/fault_proof_migration_plan.md` §2.2 (non-goals).
  * `LegalKernel/FaultProof/Cell.lean` — current cell-proof
    machinery.
  * `LegalKernel/FaultProof/Commit.lean` — state-commitment
    scheme.
  * `LegalKernel/Runtime/Hash.lean` — `CollisionFree hashBytes`
    predicate.
  * `solidity/src/lib/StepVMMerkle.sol` — current witness-state
    verifier; SC.2 replaces.
  * `solidity/src/contracts/CanonStateRootSubmission.sol` —
    consumes the cell-proof library.

---

**End of plan.**  Landing SC retires the documented cross-stack
soundness optimisation and moves the operational mitigation
("audit off-chain") to a mechanical L1-side defence.
