<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

# Encoder Injectivity (AR.4 Follow-Up) — Engineering Plan

This document plans the engineering effort to ship the deferred AR.4
work: per-sub-state `*_encode_injective` lemmas for the five
map-backed sub-states inside `ExtendedState`, plus the composition
theorem that retires CLAUDE.md footnote 1 and promotes the
fault-proof chain from bytes-equality to extensional state
equality.

The work is the single largest residual Lean proof debt identified
by the audit-remediation pass.  The formal design (CBE canonicality
for map-backed types) lives in `docs/GENESIS_PLAN.md` §15B.1 / §15C.7
and `docs/planning/audit_remediation_plan.md` §4.4 / §15C.7.

## Status

  * **Workstream prefix:** `EI` (Encoder Injectivity).  Top-level
    sub-units `EI.1` … `EI.8`, each decomposed into sub-sub-units
    (e.g. `EI.1.a`, `EI.1.b`, …) sized for a single-day PR.
    Inherits the eight-sub-unit decomposition sketched in
    `docs/planning/audit_remediation_plan.md` §4.4 (formerly
    AR.4.1 – AR.4.8); `EI.k` corresponds to the AR plan's
    `AR.4.k`.  The sub-sub-unit decomposition is new in this
    revision and is the engineering plan's primary deliverable.
  * **Total sub-sub-units:** 47 (3 + 9 + 6 + 2 + 2 + 5 + 4 + 6 +
    10).  Two are conditional (EI.1.a only lands if EI.0.a finds
    a missing Std lemma; EI.7.a only if `EthAddress.toBytes_injective`
    isn't shipped); the certain-to-land count is 45.  See §4 for
    the per-unit catalogue and §5 for the per-PR landing matrix.
  * **Branch convention:** `claude/encoder-injectivity-<slug>`,
    landing in one PR per sub-sub-unit for bisection cleanliness
    (with stipulated exceptions in §5 where two consecutive
    sub-sub-units are tightly coupled and benefit from a single
    PR).
  * **Build-posture target:** `lake build`, `lake test`, plus all
    audit binaries (`count_sorries`, `tcb_audit`, `stub_audit`,
    `naming_audit`, `deferral_audit`, `lex_lint`,
    `lex_codegen --check`, `mock_import_audit`) green throughout
    the workstream's progression.  **No new sorries**, **no new
    axioms**, **no new opaques**, **no TCB expansion**.
  * **TCB delta.**  Zero by default.  All new theorems land in
    `LegalKernel/Encoding/*.lean` and `LegalKernel/FaultProof/*.lean`
    (non-TCB).  `Kernel.lean` is untouched.
    `RBMapLemmas.lean` (TCB-tier) is touched **only** by sub-unit
    EI.1.a, and **only if** the Std-core pre-flight audit
    (EI.0.b) finds that the helper lemma is absent from Lean
    core.  If EI.1.a is required, it triggers the §13.6
    two-reviewer gate.
  * **Trust-assumption delta.**  Zero.  The injectivity proofs
    are closed-form and consume only `propext`, `Classical.choice`,
    `Quot.sound`, and the existing `Std.TreeMap` lemma set.
    They do not depend on `Verify`, `hashBytes`, or any other
    opaque.
  * **Frozen indices reserved:** none.  EI does not add `Action`
    or `Event` constructors and therefore does not touch the
    `Lex.IndexRegistry.txt` append-only registry.
  * **Branch.**  `claude/review-encoder-plan-dTlnd` (the current
    branch carrying the plan revision); implementation branches
    follow `claude/encoder-injectivity-<slug>` per the
    convention above.

## Table of contents

  * §1 Goals and non-goals
    * §1.1 Goals
    * §1.2 Non-goals
    * §1.3 Reading guide
    * §1.4 Glossary
    * §1.5 Audit-discovered corrections (from the pre-rewrite audit)
  * §2 Mathematical background
    * §2.1 What "encoder injectivity" means precisely
    * §2.2 The bytes-eq → toList-eq → Equiv lift
    * §2.3 CBE canonicality obligations
    * §2.4 The proof recipe (one sub-state at a time)
    * §2.5 Inner-encoder framing (`encodeAsBytes`) discipline
  * §3 Work-unit dependencies
    * §3.1 Strict ordering
    * §3.2 Parallel-safe sub-units
    * §3.3 Critical path
    * §3.4 Dependency DAG (full, sub-sub-unit granularity)
  * §4 Work-unit specifications (EI.0 – EI.8)
    * §4.0 EI.0 — Pre-flight discovery + scaffolding
    * §4.1 EI.1 — Helper / atomic-injectivity foundation
    * §4.2 EI.2 — `State.encode` template (nested map)
    * §4.3 EI.3 — `NonceState.encode_injective`
    * §4.4 EI.4 — `KeyRegistry.encodeMap_injective`
    * §4.5 EI.5 — `LocalPolicies.encodeMap_injective`
    * §4.6 EI.6 — `BridgeState.encodeConsumed_injective`
    * §4.7 EI.7 — `BridgeState.encodePending_injective`
                  + `BridgeState.encode_injective`
    * §4.8 EI.8 — Composition + documentation + landing
  * §5 Sequencing and PR structure
  * §6 Quality gates, rollback, roll-forward
  * §7 Risk register
  * §8 Acceptance criteria for the workstream
  * §9 Out-of-scope items
  * §10 References
  * Appendix A — Theorem-to-test cross-reference matrix
  * Appendix B — `#print axioms` verification script
  * Appendix C — Cross-document edit checklist
  * Appendix D — Open questions surfaced during planning

## §1 Goals and non-goals

### §1.1 Goals

  1. **Ship the six `*_encode_injective` lemmas** for the map-
     backed sub-states inside `ExtendedState`:

       * `State.encode_injective`               — outer balances map
         (nested: outer `ResourceId → BalanceMap-as-bytes`, inner
         `BalanceMap = TreeMap ActorId Amount`).
       * `NonceState.encode_injective`          — flat map
         (`TreeMap ActorId Nonce`).
       * `KeyRegistry.encodeMap_injective`      — flat map
         (`TreeMap ActorId PublicKey`).
       * `LocalPolicies.encodeMap_injective`    — flat map with
         rich struct value (`TreeMap ActorId LocalPolicy`).
       * `BridgeState.encodeConsumed_injective` — flat map with
         rich struct value (`TreeMap DepositId DepositRecord`).
       * `BridgeState.encodePending_injective`  — flat map with
         rich struct value (`TreeMap WithdrawalId
         PendingWithdrawal`).

     Each theorem has the schema (specialised to the carrier):

     ```lean
     theorem <sub>_encode_injective :
       ∀ (m₁ m₂ : <Carrier>),
         <sub>.encode m₁ = <sub>.encode m₂ →
         m₁.Equiv m₂
     ```

     The conclusion is **`Std.TreeMap.Equiv`** — the canonical
     map-equivalence relation already used elsewhere in
     `LegalKernel/Encoding/State.lean`
     (`balanceMap_encode_deterministic_of_equiv`,
     `localPolicies_encodeMap_deterministic_of_equiv`).  `Equiv`
     is characterised by `Std.TreeMap.equiv_iff_toList_eq` and
     in turn implies extensional pointwise lookup equality
     (`∀ k, m₁[k]? = m₂[k]?`) via the standard `getElem?_eq_of_Equiv`
     family of Std lemmas.

     **Why `Equiv` and not raw pointwise lookup as the conclusion?**
     Two reasons.  (1) The Std API uses `Equiv` as the canonical
     "same logical map" relation; downstream consumers can derive
     pointwise lookup from `Equiv` with one Std lemma, but not vice
     versa without re-deriving `Equiv` from `getElem?` pointwise.
     (2) The existing deterministic-encoding direction
     (`balanceMap_encode_deterministic_of_equiv`) takes `Equiv` as
     hypothesis, so the injectivity direction is its strict mirror
     image — keeping both sides in the same vocabulary makes the
     pair of theorems read as `encode ↔ Equiv` and composes
     trivially with `congr`-style reasoning.

  2. **Ship the auxiliary `BridgeState.encode_injective`
     theorem** that lifts the consumed-/pending-map injectivity
     plus `nextWdId` injectivity through the concatenation
     structure of `Bridge.BridgeState.encode`.  This is required
     by the composition theorem (Goal 3) and is **distinct from**
     the per-sub-map injectivity lemmas because `BridgeState.encode`
     is a *concatenation* (`encodeConsumed ++ encodePending ++
     nextWdId`), not a single map encode.

  3. **Promote `commitExtendedState_subcommits_bytes_eq_under_collision_free`
     to a full extensional-equality variant.**  The new theorem
     in `LegalKernel/FaultProof/Commit.lean`:

     ```lean
     theorem commitExtendedState_subcommits_extensional_eq_under_collision_free
         (es₁ es₂ : ExtendedState)
         (h_cf : Bridge.CollisionFree hashBytes)
         (h_eq : commitExtendedState es₁ = commitExtendedState es₂) :
       ExtendedState.extEq es₁ es₂
     ```

     where `ExtendedState.extEq` is the per-sub-state `Equiv`
     conjunction (defined in EI.8.a).  This is the AR.23 lift
     point: the snapshot-bootstrap regression suite then promotes
     from "bytes match" to "states are extensionally equal".

  4. **Retire CLAUDE.md footnote 1.**  Update CLAUDE.md and the
     Genesis Plan in the EI.8 PR; the footnote's substance is
     replaced by the shipped theorem name.

  5. **Establish the proof template** so future sub-states inherit
     a turnkey injectivity proof.  EI.1 (the helpers) and EI.2
     (the `State.encode` template) are the templates.  Two
     downstream workstreams plan to reuse them: PA
     (`docs/planning/parameterized_laws_landing_plan.md` PA.3)
     for the `parameters` substrate encoder, and any Phase 7
     sub-workstream that adds a new map-backed sub-state (see
     `docs/planning/phase_7_plan.md`).

### §1.2 Non-goals

  1. **No change to the encoder definitions.**  Existing encoder
     bodies (`BalanceMap.encode`, `State.encode`, `NonceState.encode`,
     `KeyRegistry.encodeMap`, `LocalPolicies.encodeMap`,
     `Bridge.BridgeState.encodeConsumed`,
     `Bridge.BridgeState.encodePending`, `Bridge.BridgeState.encode`,
     `ExtendedState.encode`) and their byte outputs are untouched.
     EI proves a property the existing definitions already satisfy.

  2. **No new `Encodable` instance for any of the six sub-states.**
     All six already have `Encodable` instances and shipped
     deterministic-encoding lemmas (the `*_encode_deterministic`
     and `*_encode_deterministic_of_equiv` family in
     `Encoding/State.lean` and `Encoding/LocalPolicy.lean`).

  3. **No structural-equality lemma.**  `m₁ = m₂` (Lean's `Eq` on
     `TreeMap`) is *strictly stronger* than `Equiv` because two
     structurally-distinct red-black trees can represent the same
     logical map.  EI proves `Equiv` only; structural-equality is
     intentionally out of scope and not needed by any current or
     planned consumer.

  4. **No change to the bytes-equality theorem in
     `FaultProof/Commit.lean`.**  The existing
     `commitExtendedState_subcommits_bytes_eq_under_collision_free`
     stays in source as a load-bearing lemma; EI.8 *adds* the
     extensional variant alongside.

  5. **No CBE wire-format change.**  The encoder's byte output is
     untouched.  Existing log files remain replayable byte-for-byte
     and existing snapshots remain decodable.

  6. **No Rust-host or Solidity-mirror changes.**  EI is a Lean-only
     workstream.  If a downstream Rust observer (Workstream H's
     deferred sub-units 5.4 / 5.7 / 5.8 / 5.11) eventually consumes
     the extensional-eq theorem, that's a separate landing.

  7. **No retroactive renaming of existing encoder functions.**
     Some sub-state encoders are named `*.encode` (e.g.
     `NonceState.encode`) and others `*.encodeMap` (e.g.
     `KeyRegistry.encodeMap`, `LocalPolicies.encodeMap`,
     `Bridge.BridgeState.encodeConsumed`).  The naming
     inconsistency is pre-existing and pre-EI; renaming for
     uniformity is out of scope and would force a wide-blast-radius
     diff.  EI's injectivity-lemma names follow the existing
     encoder names verbatim.

### §1.3 Reading guide

  * **Implementer:** read §1.5 (audit-discovered corrections) and §2
    (mathematical background) first, then §4.0 (pre-flight) and §4.1
    (helpers) before any per-sub-state work.  Each sub-unit's
    "Implementation steps" section is self-contained and can be read
    in isolation once the foundation is in place.
  * **Reviewer:** read §1, §2, then the sub-unit being reviewed plus
    its "Reviewer checklist".  For TCB-touching changes (EI.1.a if
    it lands), apply the §13.6 two-reviewer gate.
  * **Future auditor:** read §1 + §8 (workstream-level acceptance
    criteria) + Appendix A (theorem-to-test cross-reference matrix)
    + §10 (cross-references).
  * **Project lead deciding whether to schedule EI now:** read §1.1,
    §3.3 (critical path), §7 (risk register), and §5 (sequencing).
    Total critical-path effort is ~9 engineer-days; total wall-clock
    with parallel sub-units is ~5 days.

### §1.4 Glossary

  * **`Std.TreeMap.Equiv`** (`Equiv` for short).  The standard
    `Std.Data.TreeMap` equivalence relation: two maps are `Equiv`
    iff they contain the same set of `(key, value)` pairs (modulo
    tree shape).  Characterised by `equiv_iff_toList_eq` in Std.
  * **Extensional equality** (`~ext`).  For `m₁ m₂ : TreeMap α β _`:
    `∀ k, m₁[k]? = m₂[k]?`.  Equivalent to `Equiv` under `LawfulCmp
    cmp` via the Std `getElem?_eq_iff_Equiv`-family lemmas (or via
    `toList`).  Used in the glossary for accessibility; the formal
    target relation in EI's theorems is `Equiv`.
  * **Canonical encoding.**  An encoding such that two `Equiv`
    inputs produce identical bytes.  Equivalent to: `m₁.Equiv m₂ →
    encode m₁ = encode m₂`.  Already shipped as the
    `*_encode_deterministic_of_equiv` family.
  * **Injective encoding.**  An encoding such that identical bytes
    imply `Equiv` inputs.  Equivalent to: `encode m₁ = encode m₂ →
    m₁.Equiv m₂`.  This is the missing direction EI ships.
  * **Sorted-pair representation.**  The canonical `List (Key ×
    Val)` form: ordered ascending by `compare`, no duplicate keys.
    Produced by `TreeMap.toList` on a tree of order `compare`.
  * **CBE (Canonical Binary Encoding).**  Canon's wire format; see
    `LegalKernel/Encoding/CBOR.lean` and Genesis Plan §8.7.
  * **Inner-encoder framing.**  The wrapper pattern
    `inner.encodeAsBytes := ByteArray.mk (inner.encode bm).toArray`
    used by `BalanceMap`, `DepositRecord`, `PendingWithdrawal`,
    and `LocalPolicy` to embed a sub-encoding as a length-prefixed
    CBE byte string inside an outer map's value slot.  See §2.5.
  * **Sub-sub-unit.**  An indivisible PR-sized work unit within
    a top-level sub-unit (e.g. `EI.5.b` within `EI.5`).
  * **TCB / non-TCB.**  Trusted Computing Base.  `Kernel.lean` and
    `RBMapLemmas.lean` only.  EI is non-TCB except for the
    conditional EI.1.a addition.

### §1.5 Audit-discovered corrections

Pre-rewrite audit of the codebase (recorded here for traceability;
each item resolved in the rewritten plan body):

  * **`PendingWithdrawal` fields**: previous plan claimed
    `{ recipient, amount, resourceId, l1Block }`.  Actual struct at
    `LegalKernel/Bridge/State.lean:155-167` has fields
    `{ resource, recipient, amount, l2LogIndex }`.  All references
    fixed in EI.7.
  * **`LocalPolicyClause` constructors**: previous plan claimed
    `{ denyTag, requireRecipient, capAmount }`.  Actual inductive
    at `LegalKernel/Authority/LocalPolicy.lean:122-141` has
    constructors `{ denyTags, requireRecipientIn, capAmount }`
    (note: plural `denyTags`; `requireRecipientIn` takes a
    resource argument).  Fixed in EI.5.
  * **`LocalPolicy` fields**: previous plan speculated about
    additional fields like `signerExempted : Bool`.  Actual struct
    at `LegalKernel/Authority/LocalPolicy.lean:151-154` has
    exactly one field: `clauses : List LocalPolicyClause`.  EI.5.b
    is therefore a single-field proof, not a multi-field proof.
  * **`ExtendedState` field names**: previous plan's `extEq`
    definition referenced `s.state.balances`, `s.state.nonces`,
    etc.  Actual struct at
    `LegalKernel/Authority/Nonce.lean:98-141` uses
    `es.base`, `es.nonces`, `es.registry`, `es.bridge`,
    `es.localPolicies`.  Fixed in EI.8.a.
  * **Encoder function names**: previous plan referred to
    `KeyRegistry.encode`, `LocalPolicies.encode`, `consumedEncode`,
    `pendingEncode`.  Actual names are `KeyRegistry.encodeMap`,
    `LocalPolicies.encodeMap`, `Bridge.BridgeState.encodeConsumed`,
    `Bridge.BridgeState.encodePending`.  Fixed throughout §4.
  * **`BridgeState.consumed` value type**: previous plan claimed
    `TreeMap DepositId Unit compare`.  Actual at
    `LegalKernel/Bridge/State.lean:182` is `TreeMap DepositId
    DepositRecord compare`, where `DepositRecord` is a 2-field
    struct `{ resource : ResourceId, amount : Amount }`.  Fixed
    in EI.6.
  * **CBE primitive injectivity**: previous plan assumed
    `cbe_pair_inj` and `cbe_array_inj` were shipped in
    `Encoding/CBOR.lean`.  Audit found no such lemmas; the file
    has round-trip lemmas (`cborHeadRoundtrip`,
    `cborHeadRoundtrip_append`) but no standalone injectivity
    lemmas.  Closed by the new sub-units `EI.1.c`
    (`cborHeadEncode_injective`) and `EI.1.e`
    (`encodeSortedPairs_injective`).
  * **Atomic carrier injectivity coverage**: previous plan
    assumed every value carrier had a shipped `*_encode_injective`.
    Audit at `LegalKernel/Encoding/Encodable.lean` found only
    four: `bool_encode_injective` (line 178),
    `nat_encode_injective` (line 215),
    `boundedNat_encode_injective` (line 280), and
    `byteArray_encode_injective` (line 380).  Missing for:
    `UInt8`/`16`/`32`/`64`, `ActorId`, `Amount`, `Nonce`,
    `ResourceId`, `PublicKey`, `DepositId`, `WithdrawalId`,
    `EthAddress`, `DepositRecord`, `PendingWithdrawal`,
    `LocalPolicyClause`, `LocalPolicy`, `List α`, `Option α`.
    Closed by new sub-units `EI.1.f` – `EI.1.i`.
  * **`Std.TreeMap.equiv_iff_toList_eq`**: previous plan proposed
    a project-defined `toList_canonical` lemma in `RBMapLemmas.lean`.
    Audit shows Lean core already ships `TreeMap.equiv_iff_toList_eq`
    (used in `LegalKernel/Encoding/State.lean:539` and
    `LegalKernel/Encoding/LocalPolicy.lean:563`).  Therefore
    EI.1.a's TCB-tier auxiliary is **likely unnecessary**; the
    pre-flight audit (EI.0.b) confirms and skips it.  The plan
    now schedules EI.1.a only as a contingency.
  * **`FaultProof/EncodeInjectivity.lean` already exists**: previous
    plan did not mention this module.  Audit at
    `LegalKernel/FaultProof/EncodeInjectivity.lean:1-100` shows it
    ships `kernelStep_encode_deterministic`,
    `kernelStep_encode_distinguishes_inputs`,
    `gameState_encode_deterministic`, and
    `gameState_encode_distinguishes_inputs` (the
    distinguish-inputs form is the contrapositive of determinism).
    EI's new lemmas should follow the same naming and live
    alongside (preferred) or under sibling files.  Module
    placement decision recorded in §4.0 and Appendix D OQ-EI-1.
  * **Inner-encoder framing**: the previous plan's recipe
    described decomposition through CBE arrays + pairs but
    did not address the `*.encodeAsBytes` wrapper, which is
    used four times in the encoder stack (BalanceMap,
    DepositRecord, PendingWithdrawal, LocalPolicy).  Each
    requires its own framing-injectivity sub-sub-unit.  Closed
    by new sub-units `EI.2.c`, `EI.5.c`, `EI.6.c`, `EI.7.d`.

## §2 Mathematical background

### §2.1 What "encoder injectivity" means precisely

For each map-backed sub-state `S` (the six listed in §1.1) we have
an encoder `S.encode : S → Stream` (alias `S.encodeMap` for the
sub-states whose encoder follows the `*.encodeMap` naming
convention) and a decoder `S.decode` (or `S.decodeMap`).  The
existing machinery in `LegalKernel/Encoding/State.lean` and
`LegalKernel/Encoding/LocalPolicy.lean` provides:

  * **Round-trip (decode ∘ encode = ok)** for the `DepositRecord`
    inner type via `depositRecord_roundtrip`
    (`Encoding/State.lean:576`).
  * **Determinism (`Eq → byte-eq`)** for each sub-state via the
    `*_encode_deterministic` family
    (`state_encode_deterministic`, `extendedState_encode_deterministic`,
    `bridgeState_encode_deterministic`, `depositRecord_encode_deterministic`,
    `pendingWithdrawal_encode_deterministic`,
    `localPolicies_encodeMap_deterministic`).
  * **Equiv-determinism (`Equiv → byte-eq`)** for `BalanceMap` and
    `LocalPolicies` via
    `balanceMap_encode_deterministic_of_equiv`
    (`Encoding/State.lean:534`) and
    `localPolicies_encodeMap_deterministic_of_equiv`
    (`Encoding/LocalPolicy.lean:558`).

What is missing is the **injective direction** (encoder-output
equality ⇒ input `Equiv`).  Formally, for the inner balance map
(the simplest case):

```lean
theorem BalanceMap.encode_injective :
  ∀ (bm₁ bm₂ : BalanceMap),
    BalanceMap.encode bm₁ = BalanceMap.encode bm₂ →
    bm₁.Equiv bm₂
```

The outer `State.encode` adds a layer of inner-map framing on top
of this (see §2.5).  The remaining four sub-states are flat maps
whose value types are either atomic (`Nonce`, `PublicKey`) or
small structs (`LocalPolicy`, `DepositRecord`, `PendingWithdrawal`)
that EI ships side-injectivity lemmas for as prerequisites.

**Why `Equiv` rather than `Eq`.**  `Eq` on `TreeMap` is *strictly
stronger* than `Equiv` because two structurally-distinct red-black
trees can contain the same `(key, value)` set.  The encoder
canonicalises through `toList`, which erases tree shape: the
decoded map (built by repeated `insert` on the canonical pair
list) may have a different tree shape than the original.  EI's
target relation must therefore be `Equiv`, not `Eq`.

### §2.2 The bytes-eq → toList-eq → Equiv lift

The proof factors through three intermediate steps.  Let `m₁ m₂ :
TreeMap α β cmp` with the project's `compare`-order:

```
        encode m₁ = encode m₂                  (hypothesis: bytes equal)
              │
              ▼  (CBE injectivity at the byte level — EI.1.c + EI.1.e)
    sortedPairs (toList m₁) = sortedPairs (toList m₂)
              │
              ▼  (sortedPairs is `id` modulo encoding; trivial — EI.1.h)
        m₁.toList = m₂.toList                  (canonical-pair-list equal)
              │
              ▼  (Std equiv_iff_toList_eq.mpr)
        m₁.Equiv m₂                            (target conclusion)
              │
              ▼  (Std getElem?_eq_of_Equiv if needed — downstream consumer)
        ∀ k, m₁[k]? = m₂[k]?                   (pointwise lookup equality)
```

Each arrow is a separate lemma.  The two key middle arrows are:

  * **`encodeSortedPairs_injective`** (EI.1.e): two
    `encodeSortedPairs` outputs are equal ⇒ the underlying pair
    lists are equal (modulo `α`/`β` injectivity preconditions).
    This is the load-bearing lemma; once shipped, every per-sub-
    state proof reduces to a mechanical instance of "specialise to
    the sub-state's `(key, value)` types and discharge the
    per-type injectivity preconditions".

  * **`Std.TreeMap.equiv_iff_toList_eq`** (already in Std core,
    used at `Encoding/State.lean:539` and `Encoding/LocalPolicy.lean:563`).
    Bridges canonical-pair-list equality to `Equiv`.

### §2.3 CBE canonicality obligations

CBE encodes a sorted-pair-list map as
`cborHeadEncode cbeTagMap len ++ pair_1 ++ … ++ pair_n` where each
`pair_i = Encodable.encode k_i ++ Encodable.encode v_i`.  The full
canonicality contract has five obligations; EI ships each via a
named sub-unit:

  1. **CBE-head injectivity** (`cborHeadEncode_injective`).  Two
     CBE-head bytes encode the same `(major, len)` iff the major
     tags and counts are equal.  Closed by `EI.1.c`.

  2. **Encodable injectivity for atomic key/value carriers.**
     `Nat`, `Bool`, `ByteArray`, `UInt8`/`16`/`32`/`64`, plus
     the project-specific wrappers `ActorId`, `Amount`, `Nonce`,
     `ResourceId`, `PublicKey`, `DepositId`, `WithdrawalId`,
     `EthAddress`.  Closed by `EI.1.f` (UIntN) and `EI.1.g`
     (project wrappers).

  3. **Encodable injectivity for composite-value carriers.**
     `List α`, `Option α`, `DepositRecord`, `PendingWithdrawal`,
     `LocalPolicyClause`, `LocalPolicy`.  Closed by `EI.1.h`
     (`List`/`Option`) and `EI.4`–`EI.7` per sub-state.

  4. **`encodeSortedPairs` injectivity** modulo (1)+(2).  Closed
     by `EI.1.e`.

  5. **Inner-encoder framing injectivity** for the four
     `*.encodeAsBytes` wrappers used by the encoder stack.
     Closed by `EI.1.d` (the polymorphic shape) and
     `EI.2.c` / `EI.5.c` / `EI.6.c` / `EI.7.d` per call site.

### §2.4 The proof recipe (one sub-state at a time)

For each flat-map sub-state `S` with carrier `TreeMap α β cmp` and
encoder `S.encode := encodeSortedPairs (m.toList.map proj)`:

  1. **Step A.**  From `S.encode m₁ = S.encode m₂` (the hypothesis),
     unfold `S.encode` to expose
     `encodeSortedPairs (toList m₁) = encodeSortedPairs (toList m₂)`.

  2. **Step B.**  Apply `EI.1.e` (`encodeSortedPairs_injective`) to
     get `(toList m₁).map proj = (toList m₂).map proj`.

  3. **Step C.**  Discharge the per-`α`/`β` injectivity precondition
     of `EI.1.e` using the atomic-carrier injectivity lemmas from
     `EI.1.f`–`EI.1.h` and the per-value-type structural lemma
     (`EI.4`-style) where the value is a record.

  4. **Step D.**  Lift `.map proj` equality back to raw `toList`
     equality (trivial when `proj` is the identity or a 1-1
     correspondence; non-trivial when `proj` performs a `toNat`
     coercion — discharged via `UInt64.toNat_injective` or the
     analogous bijection lemma).

  5. **Step E.**  Apply `Std.TreeMap.equiv_iff_toList_eq.mpr` to
     conclude `m₁.Equiv m₂`.

  6. **QED.**

For the nested-map sub-state `State.encode` (EI.2), one additional
layer wraps each inner map in `BalanceMap.encodeAsBytes`; the proof
adds an extra `BalanceMap.encode_injective` step inside step C.

### §2.5 Inner-encoder framing (`encodeAsBytes`) discipline

Four call sites use the framing pattern

```lean
private def Inner.encodeAsBytes (x : Inner) : ByteArray :=
  ByteArray.mk (Inner.encode x).toArray
```

  * `BalanceMap.encodeAsBytes`            (`Encoding/State.lean:205`)
  * `Bridge.DepositRecord.encodeAsBytes`  (`Encoding/State.lean:318`)
  * `Bridge.PendingWithdrawal.encodeAsBytes` (`Encoding/State.lean:343`)
  * (`LocalPolicy.encodeAsBytes` in `Encoding/LocalPolicy.lean` —
    same pattern; mirror call site for the LocalPolicies outer
    map.)

Each is the canonical inverse of "decode bytes, then re-decode as
Inner" performed by the outer decoder.  Each is **injective up to
`Equiv` on the underlying `Inner`** iff `Inner.encode` is injective
up to `Equiv` — i.e. framing-injectivity composes from inner-encoder
injectivity by the polymorphic lemma

```lean
private lemma encodeAsBytes_injective_of_encode_injective
    {Inner : Type} (encode : Inner → Stream)
    (hInj : ∀ x y, encode x = encode y → x.Equiv y) :
    ∀ x y,
      ByteArray.mk (encode x).toArray = ByteArray.mk (encode y).toArray →
      x.Equiv y
```

(For inner types like `DepositRecord` and `PendingWithdrawal` whose
encoder injectivity is `Eq`-shaped rather than `Equiv`-shaped,
specialise `Equiv` to `Eq` in the lemma statement.)

`EI.1.d` ships this polymorphic helper once, and each per-call-site
framing-injectivity lemma is then a one-line specialisation.


## §3 Work-unit dependencies

### §3.1 Strict ordering

```
EI.0 ──► EI.1 ──► EI.2 ──► EI.3, EI.4, EI.5, EI.6, EI.7 (parallelisable)
                                                            │
                                                            ▼
                                                          EI.8
```

  * **EI.0 (pre-flight) gates everything.**  Two read-only audits
    (`EI.0.a` Std lemma scan, `EI.0.b` module-placement decision)
    plus one test-scaffolding sub-unit (`EI.0.c`).  These are
    cheap and resolve open questions before proof work begins.

  * **EI.1 (helpers) blocks every per-sub-state proof.**  EI.1.c
    – EI.1.h ship the CBE primitive injectivity, atomic-carrier
    injectivity, and composite-carrier (List, Option) injectivity.
    Every per-sub-state proof consumes EI.1.e
    (`encodeSortedPairs_injective`).

  * **EI.2 (`State.encode`) is the template.**  Hardest case
    (nested map with inner-encoder framing).  Lands first to
    surface obstacles before parallel work on EI.3–EI.7 begins.

  * **EI.3 – EI.7 are parallelisable.**  Each is a different
    sub-state with disjoint scope (one or two `Encoding/*.lean`
    files per).  Reviewers may merge them in any order once EI.1
    + EI.2 are in.

  * **EI.8 is the closer.**  Composes the per-sub-state lemmas
    into the headline `commitExtendedState_subcommits_extensional_eq_under_collision_free`
    theorem; lifts the snapshot-bootstrap regression; retires
    CLAUDE.md footnote 1; bumps the build tag.

### §3.2 Parallel-safe sub-units

After EI.0 + EI.1 + EI.2 ship, EI.3 / EI.4 / EI.5 / EI.6 / EI.7
may be implemented in parallel by separate contributors as long
as each PR is scoped to a single sub-state's `Encoding/*.lean`
file (or a new `Encoding/<Sub>Injective.lean` sibling — module-
placement decision lives in EI.0.b).  EI.5.a (`LocalPolicyClause`)
and EI.5.b (`LocalPolicy`) inside EI.5 are sequential; the rest of
EI.5 is parallelisable with the other EI.k's.

### §3.3 Critical path

```
EI.0       (~0.5 d)
   └─► EI.1  (~3.0 d)
          └─► EI.2  (~2.5 d)
                 └─► (parallel batch: EI.3 + EI.4 + EI.5 + EI.6 + EI.7, ~2.0 d wall-clock)
                        └─► EI.8  (~1.0 d)
```

Critical path: **~9 working days** for a single full-time contributor,
~5 days wall-clock with parallel execution of EI.3–EI.7 after EI.2
ships.  The AR.4 9–16-day estimate covered serial execution plus
review cycles plus surprise budget; this plan's revised estimate
falls inside that envelope.

### §3.4 Dependency DAG (full, sub-sub-unit granularity)

This DAG is the source of truth for parallel-landing safety; §5's
PR sequencing matrix is derived from it.

```
EI.0.a  (Std-core lemma audit)        ──┐
EI.0.b  (Module placement decision)   ──┤── pre-flight; no other
EI.0.c  (Test/Encoding/Injectivity.lean scaffold) ──┘   sub-unit blocks on these
                                                       (they unblock EI.1+)

EI.1.a  (TreeMap auxiliary, conditional on EI.0.a)
EI.1.b  (Encodable_via_decode_inj polymorphic helper)
EI.1.c  (cborHeadEncode_injective)
EI.1.d  (encodeAsBytes_injective_of_encode_injective polymorphic helper)
EI.1.e  (encodeSortedPairs_injective)
EI.1.f  (UIntN injectivity quartet)
EI.1.g  (project-wrapper injectivity: ActorId, Amount, Nonce,
         ResourceId, PublicKey, DepositId, WithdrawalId, EthAddress)
EI.1.h  (List α / Option α injectivity, parameterised)
EI.1.i  (Encodable.encode_injective hypotheses propagation lemma)

EI.1.c ──► EI.1.e
EI.1.b + EI.1.f + EI.1.g + EI.1.h ──► EI.1.i

EI.2.a  (BalanceMap.encode_injective)            ◄── EI.1.e + EI.1.g
EI.2.b  (Lift to Equiv via toList canonicality)  ◄── EI.2.a
EI.2.c  (BalanceMap.encodeAsBytes_injective)     ◄── EI.1.d + EI.2.b
EI.2.d  (State.encode_injective, nested)         ◄── EI.2.c + EI.1.e
EI.2.e  (Tests + term-level API for EI.2.a-d)
EI.2.f  (Retrospective for EI.3-EI.7 plan review)

EI.3.a  (NonceState.encode_injective)            ◄── EI.1.e + EI.1.g
EI.3.b  (Tests for EI.3.a)

EI.4.a  (KeyRegistry.encodeMap_injective)        ◄── EI.1.e + EI.1.g
EI.4.b  (Tests for EI.4.a)

EI.5.a  (LocalPolicyClause.encode_injective)     ◄── EI.1.b + EI.1.g + EI.1.h
EI.5.b  (LocalPolicy.encode_injective)           ◄── EI.5.a + EI.1.h
EI.5.c  (LocalPolicy.encodeAsBytes_injective)    ◄── EI.1.d + EI.5.b
EI.5.d  (LocalPolicies.encodeMap_injective)      ◄── EI.5.c + EI.1.e
EI.5.e  (Tests for EI.5.a-d)

EI.6.a  (DepositRecord.encode_injective)         ◄── EI.1.b + EI.1.g
EI.6.b  (DepositRecord.encodeAsBytes_injective)  ◄── EI.1.d + EI.6.a
EI.6.c  (BridgeState.encodeConsumed_injective)   ◄── EI.6.b + EI.1.e
EI.6.d  (Tests for EI.6.a-c)

EI.7.a  (EthAddress.toBytes_injective, if absent)
EI.7.b  (PendingWithdrawal.encode_injective)     ◄── EI.7.a + EI.1.b + EI.1.g
EI.7.c  (PendingWithdrawal.encodeAsBytes_injective)
                                                   ◄── EI.1.d + EI.7.b
EI.7.d  (BridgeState.encodePending_injective)    ◄── EI.7.c + EI.1.e
EI.7.e  (BridgeState.encode_injective, concat-shape)
                                                   ◄── EI.6.c + EI.7.d
                                                       + nat_encode_injective
                                                       (for nextWdId)
EI.7.f  (Tests for EI.7.a-e)

EI.8.a  (ExtendedState.extEq definition)         ◄── (all of EI.2 - EI.7)
EI.8.b  (commitExtendedState_subcommits_extensional_eq theorem)
                                                   ◄── EI.8.a + EI.2.d + EI.3.a
                                                       + EI.4.a + EI.5.d + EI.6.c
                                                       + EI.7.d + (LocalPolicies/
                                                       BridgeState concat lemma)
EI.8.c  (AR.23.3 snapshot-bootstrap test lift)   ◄── EI.8.b
EI.8.d  (CLAUDE.md cross-doc retirement)         ◄── EI.8.b
EI.8.e  (GENESIS_PLAN.md cross-doc retirement)   ◄── EI.8.b
EI.8.f  (audit_remediation_plan.md update)       ◄── EI.8.b
EI.8.g  (encoder_injectivity_plan.md self-update)
                                                   ◄── EI.8.b
EI.8.h  (AGENTS.md byte-identical parity sweep)  ◄── EI.8.d
EI.8.i  (kernelBuildTag bump + Test/Umbrella pin)
                                                   ◄── EI.8.b
EI.8.j  (Cross-reference grep + scrub)           ◄── all of EI.8.a - EI.8.i
```

Total sub-sub-units: 47 nominal (EI.0 × 3 + EI.1 × 9 + EI.2 × 6 +
EI.3 × 2 + EI.4 × 2 + EI.5 × 5 + EI.6 × 4 + EI.7 × 6 + EI.8 × 10),
or 45 certain-to-land after subtracting the two conditional units
(`EI.1.a` if the Std core lemma audit passes; `EI.7.a` if
`EthAddress.toBytes_injective` is already shipped or trivially
derivable).

## §4 Work-unit specifications

Each sub-unit follows the template:

  * **Finding map** — which audit finding(s) this closes.
  * **Scope** — files touched.
  * **Math / proof outline** — theorem statement + proof sketch.
  * **Implementation steps** — file-level edit plan.
  * **Acceptance criteria** — what must be true at landing.
  * **Test plan** — value- and term-level coverage.
  * **Definition of done (DoD)** — checklist.
  * **Verification commands** — Lake invocations.
  * **Reviewer checklist** — what to look for in code review.
  * **Risk** — likely failure modes.
  * **Effort** — engineer-days (deliberate underestimate; pad
    for review).

### §4.0 EI.0 — Pre-flight discovery + scaffolding

**Finding map.**  Pre-flight gate for AR.4 (M-3) + CLAUDE.md
footnote 1.

**Scope.**  Three sub-sub-units; one read-only audit, one design
decision, one test-file creation.  No proof work.

#### EI.0.a — Std-core lemma audit

**Activity.**  Confirm or deny the presence of the following Std
lemmas in the pinned Lean toolchain.  For each, record the exact
name and statement signature in `docs/std_dependencies.md`:

  1. `Std.TreeMap.equiv_iff_toList_eq` — already used at two call
     sites (`Encoding/State.lean:539`, `Encoding/LocalPolicy.lean:563`);
     audit confirms presence and exact signature.
  2. `Std.TreeMap.getElem?_eq_of_Equiv` (or equivalent: any lemma
     deriving pointwise `m₁[k]? = m₂[k]?` from `m₁.Equiv m₂`).
     If absent, EI.0.a flags this; EI.1.a derives it from
     `equiv_iff_toList_eq` + `toList` properties (low effort,
     pure Std composition).
  3. `Std.TreeMap.toList_isSorted` and `Std.TreeMap.toList_nodup`
     (or the project's RBMapLemmas reflexes).  Audit confirms or
     identifies the project-supplied substitutes.
  4. `Std.TreeMap.equiv_refl`, `equiv_symm`, `equiv_trans` (used
     in EI.2.b when lifting bytes-eq through framing).

**Implementation steps.**

  1. Open the pinned toolchain's `Std.Data.TreeMap` source
     (`~/.elan/toolchains/$(cat lean-toolchain | tr -d ' ')/lib/lean4/library/Std/Data/TreeMap`).
  2. `grep -rn "equiv_iff_toList_eq\|getElem?_eq_of_Equiv\|toList_isSorted\|toList_nodup\|equiv_refl\|equiv_symm\|equiv_trans"` and record findings.
  3. Update `docs/std_dependencies.md` with the audit results,
     including the exact lemma names found and the version
     identifier of the toolchain inspected.
  4. If any of items 1–4 is absent: log it as an EI.1.a candidate
     and flag in §7 risk register.

**Acceptance criteria.**

  * `docs/std_dependencies.md` has an "EI.0.a audit results"
    subsection enumerating each lemma + its Std-core source
    location.
  * Any absent lemma is captured as an EI.1.a sub-sub-unit in
    §4.1.a's "Conditional inclusion" block.

**Reviewer checklist.**

  * Audit was performed against the *pinned* toolchain
    (`lean-toolchain`), not the contributor's local override.
  * `docs/std_dependencies.md` accurately reflects the audit (no
    paraphrasing; cite exact lemma signatures).

**Risk.**  Low; read-only.

**Effort.**  ~0.2 engineer-day.

#### EI.0.b — Module-placement decision

**Activity.**  Decide where each new injectivity lemma lives.
Three candidate layouts:

  * **Option A.**  Append every new lemma to the existing
    `LegalKernel/Encoding/State.lean` and
    `LegalKernel/Encoding/LocalPolicy.lean` files.  Pros: no new
    files, easier review.  Cons: bloats already-long files
    (`Encoding/State.lean` is ~600 lines pre-EI).

  * **Option B.**  Create per-sub-state injectivity siblings:
    `Encoding/StateInjective.lean`, `Encoding/LocalPolicyInjective.lean`,
    `Encoding/BridgeInjective.lean`.  Pros: scoped review surface,
    easy git bisection.  Cons: three new files; cross-import
    discipline needs to be set up.

  * **Option C.**  Single new file
    `LegalKernel/Encoding/Injectivity.lean` collecting everything
    EI ships.  Pros: one new file; one import in downstream
    consumers.  Cons: large file; reviewer scope grows linearly
    with sub-state count.

  **Recommendation.**  Option B, anchored by precedent: the
  existing `LegalKernel/FaultProof/EncodeInjectivity.lean` follows
  Option B's pattern for the fault-proof side.  Mirror the
  pattern on the encoder side.  Each `*Injective.lean` file
  imports its underlying encoder file plus
  `LegalKernel/Encoding/Encodable.lean`; the umbrella
  `LegalKernel.lean` re-exports each.

**Implementation steps.**

  1. Document the decision (Option B or alternative) in
     `docs/planning/encoder_injectivity_plan.md` Appendix D
     OQ-EI-1 (this plan).
  2. Update Appendix D OQ-EI-1's "Decision" field.
  3. No code changes in this sub-sub-unit.

**Acceptance criteria.**

  * OQ-EI-1 (Appendix D) has a "Decision: <choice>" line.
  * Every EI.k sub-unit in §4 cites the chosen module path
    consistently.

**Reviewer checklist.**

  * Decision is recorded with explicit rationale.
  * No code changes (this sub-unit is a planning artifact only).

**Risk.**  Trivial.

**Effort.**  ~0.1 engineer-day.

#### EI.0.c — Test-file scaffolding

**Scope.**  `LegalKernel/Test/Encoding/Injectivity.lean` (new),
`Tests.lean` (umbrella registration).

**Implementation steps.**

  1. Create `LegalKernel/Test/Encoding/Injectivity.lean` with:
     - License header (copy from sibling test files).
     - `/-! ... -/` module docstring naming the plan section
       (this plan §4.0.c).
     - `import LegalKernel.Test.Framework`.
     - Empty `def suite : List TestCase := []` initially.
     - Shared fixtures used by EI.1 – EI.7 (a `genTreeMap`
       helper producing representative test maps in three
       sizes: empty, singleton, three-element).
  2. Register the new test module in `Tests.lean` per the
     existing convention (find the `Test.Encoding.State` import
     and append a new `Test.Encoding.Injectivity` import + a
     line in `Tests.testDriver`).
  3. Ensure `lake test` succeeds with the empty suite (verifies
     wiring before any actual tests land).
  4. Run `mock_import_audit` to confirm no production module
     accidentally imports the test fixtures.

**Acceptance criteria.**

  * `lake build` succeeds.
  * `lake test` runs with no new failures.
  * `lake exe mock_import_audit` passes.
  * The file is imported by `Tests.lean`.

**Reviewer checklist.**

  * License header matches sibling test files.
  * Module docstring follows project convention.
  * `genTreeMap` helper is well-named and lives in a test
    namespace, not the production namespace.

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day.

---

### EI.0 — Rolled-up acceptance criteria

  * EI.0.a / EI.0.b / EI.0.c all individually accepted.
  * `docs/std_dependencies.md` updated.
  * OQ-EI-1 (Appendix D) resolved.
  * `LegalKernel/Test/Encoding/Injectivity.lean` exists and is
    registered in `Tests.lean`.
  * **Aggregate effort:** ~0.5 engineer-day.

### §4.1 EI.1 — Helper / atomic-injectivity foundation

**Finding map.**  Foundation for AR.4 (M-3) + CLAUDE.md footnote 1.

**Scope.**  `LegalKernel/Encoding/Encodable.lean` (atomic-carrier
injectivity additions), `LegalKernel/Encoding/CBOR.lean`
(CBE-primitive injectivity), `LegalKernel/Encoding/State.lean`
(`encodeSortedPairs` injectivity).  Optionally
`LegalKernel/RBMapLemmas.lean` (only if EI.0.a flagged a missing
Std lemma; triggers two-reviewer gate).

**EI.1 decomposes into nine sub-sub-units**, landing as 5–7
PRs depending on reviewer preference (some sub-units bundle
cleanly: 1.b + 1.d are both polymorphic helpers; 1.f + 1.g are
both atomic-carrier sweeps).

#### EI.1.a — Conditional Std-auxiliary lemma

**Scope.**  `LegalKernel/RBMapLemmas.lean` (TCB-tier; two reviewers
required) if and only if EI.0.a flagged a missing Std lemma.

**Conditional inclusion.**  This sub-unit lands only if EI.0.a's
audit determined that one or more of `equiv_iff_toList_eq`,
`getElem?_eq_of_Equiv`, `toList_isSorted`, `toList_nodup`,
`equiv_refl`, `equiv_symm`, or `equiv_trans` is absent from the
pinned Lean toolchain's `Std.Data.TreeMap`.  Given that
`equiv_iff_toList_eq` is *already in use* at two codebase sites,
the expected outcome of EI.0.a is "all four lemmas present in Std",
which makes this sub-sub-unit a no-op.

**Math (if any lemma missing).**  Derive the missing lemma from
the present ones.  Most likely candidate: `getElem?_eq_of_Equiv`,
derivable as

```lean
theorem getElem?_eq_of_Equiv
    {α β : Type*} {cmp : α → α → Ordering} [LawfulCmp cmp]
    {m₁ m₂ : Std.TreeMap α β cmp} (h : m₁.Equiv m₂) :
    ∀ k, m₁[k]? = m₂[k]? := by
  intro k
  have hList : m₁.toList = m₂.toList := equiv_iff_toList_eq.mp h
  -- find?-of-toList trace-through
  ...
```

**Implementation steps.**  Only if needed:

  1. Open `RBMapLemmas.lean`.
  2. Add the lemma immediately after the existing
     `find?_insert_*` block.
  3. Prove via list induction (≤ 15 lines).
  4. Update `docs/std_dependencies.md` with the new lemma and its
     justification (closing the audit gap).
  5. Update `tcb_allowlist.txt` if any new import is needed
     (unlikely — `RBMapLemmas` already imports `Std.Data.TreeMap`).

**Acceptance criteria.**

  * If shipped: two reviewers on the `RBMapLemmas.lean` change.
  * `#print axioms <new lemma>` ⊆ `[propext, Classical.choice,
    Quot.sound]`.
  * `lake exe tcb_audit` green (no new imports added to the
    TCB tier).
  * `docs/std_dependencies.md` updated.

**Reviewer checklist.**

  * Lemma is genuinely Std-flavoured (no project-specific
    dependencies).
  * Proof does not introduce any new opaque or axiom.
  * `docs/std_dependencies.md` updated.
  * If two reviewers required (TCB-touching), both have signed off.

**Risk.**  Low if Std core has the lemma; medium if EI.1.a must
land (touches TCB-tier file; triggers §13.6 two-reviewer gate).

**Effort.**  0 days if Std covers; ~0.5 engineer-day if needed.

#### EI.1.b — `Encodable_via_decode_inj` polymorphic helper

**Scope.**  `LegalKernel/Encoding/Encodable.lean`.

**Math.**  The "decode both sides" technique packaged as a
polymorphic helper so every atomic-carrier injectivity proof
becomes a one-liner.  For any type with a round-trip lemma:

```lean
theorem Encodable_via_decode_inj
    {T : Type} [inst : Encodable T]
    (roundtrip : ∀ (v : T), Encodable.decode (T := T) (Encodable.encode v) = .ok (v, []))
    {v₁ v₂ : T} (h : Encodable.encode v₁ = Encodable.encode v₂) :
    v₁ = v₂ := by
  have h₁ : Encodable.decode (T := T) (Encodable.encode v₁) = .ok (v₁, []) := roundtrip v₁
  have h₂ : Encodable.decode (T := T) (Encodable.encode v₂) = .ok (v₂, []) := roundtrip v₂
  rw [h] at h₁
  rw [h₂] at h₁
  exact (Except.ok.inj h₁).1
```

**Proof structure.**  Three rewrites and a constructor injection.

**Implementation steps.**

  1. Add the helper to `Encoding/Encodable.lean` after the
     existing per-type `_roundtrip` lemmas.
  2. (Optional but recommended) ship a variant that takes
     `roundtrip` with a residual suffix (`∀ v rest, decode
     (encode v ++ rest) = .ok (v, rest)`), since most shipped
     round-trip lemmas have this stronger form
     (`bool_roundtrip`, `nat_roundtrip`, etc.).

**Acceptance criteria.**

  * Theorem ships.
  * `#print axioms` clean.
  * `lake build LegalKernel.Encoding.Encodable` succeeds.

**Test plan.**

  * Term-level API stability test in
    `Test/Encoding/Injectivity.lean`.

**Reviewer checklist.**

  * Helper is genuinely polymorphic (not specialised to any
    sub-state's carrier).
  * Docstring names "decode both sides" as the technique.

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day.

#### EI.1.c — `cborHeadEncode_injective`

**Scope.**  `LegalKernel/Encoding/CBOR.lean`.

**Math.**

```lean
theorem cborHeadEncode_injective
    {major₁ major₂ : UInt8} {n₁ n₂ : Nat}
    (h₁ : n₁ < 256 ^ 8) (h₂ : n₂ < 256 ^ 8)
    (h : cborHeadEncode major₁ n₁ = cborHeadEncode major₂ n₂) :
    major₁ = major₂ ∧ n₁ = n₂
```

**Proof structure.**

  1. Unfold `cborHeadEncode`: both sides are `[major_i, b_i_0, …,
     b_i_7]` (9-byte sequences).
  2. From list equality, the head bytes are equal: `major₁ =
     major₂`.
  3. The tail bytes are equal as `List UInt8`s.
  4. Apply `natFromBytesLE_natToBytesLE` (`Encoding/CBOR.lean:192`)
     to extract `n₁ = n₂` from byte-list equality under the
     `< 2^64` hypotheses.

**Implementation steps.**

  1. Add the theorem after `cborHeadRoundtrip_append`.
  2. Proof: ≤ 10 lines.

**Acceptance criteria.**

  * Theorem ships.
  * `#print axioms` clean.

**Reviewer checklist.**

  * Both `< 2^64` hypotheses are documented in the docstring as
    canonical-encoding-bound preconditions.

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day.

#### EI.1.d — `encodeAsBytes_injective_of_encode_injective` helper

**Scope.**  `LegalKernel/Encoding/Encodable.lean` (or new
`Encoding/Framing.lean` per OQ-EI-1's resolution).

**Math.**  Polymorphic shape lifting inner-encoder injectivity
through the `ByteArray.mk ... .toArray` framing wrapper.  Two
variants are needed because some inner encoders conclude `Eq`
(`DepositRecord`, `PendingWithdrawal`, `LocalPolicy`) and one
concludes `Equiv` (`BalanceMap`).

```lean
-- Eq variant (used by DepositRecord, PendingWithdrawal, LocalPolicy)
theorem encodeAsBytes_eq_injective_of_encode_eq_injective
    {Inner : Type} (encode : Inner → Stream)
    (hInj : ∀ x y, encode x = encode y → x = y)
    {x y : Inner}
    (h : ByteArray.mk (encode x).toArray = ByteArray.mk (encode y).toArray) :
    x = y

-- Equiv variant (used by BalanceMap)
theorem encodeAsBytes_equiv_injective_of_encode_equiv_injective
    {α β : Type*} {cmp : α → α → Ordering}
    (encode : Std.TreeMap α β cmp → Stream)
    (hInj : ∀ m₁ m₂, encode m₁ = encode m₂ → m₁.Equiv m₂)
    {m₁ m₂ : Std.TreeMap α β cmp}
    (h : ByteArray.mk (encode m₁).toArray = ByteArray.mk (encode m₂).toArray) :
    m₁.Equiv m₂
```

**Proof structure (both variants).**

  1. `ByteArray.mk a = ByteArray.mk b ↔ a = b` (Lean structure
     equality on a single-field record).
  2. `List.toArray` is injective.
  3. The two encoder outputs (as `Stream`s) are therefore equal.
  4. Apply `hInj`.

**Implementation steps.**

  1. Add both helpers.
  2. Lean has `Array.toList_inj` or equivalent (audit Std);
     if not, ship a small auxiliary.

**Acceptance criteria.**

  * Both helpers ship.
  * `#print axioms` clean.

**Risk.**  Low.

**Effort.**  ~0.3 engineer-day.

#### EI.1.e — `encodeSortedPairs_injective`

**Scope.**  `LegalKernel/Encoding/State.lean` (where
`encodeSortedPairs` lives, line 107).

**Math.**  The headline polymorphic injectivity lemma:

```lean
theorem encodeSortedPairs_injective
    {K V : Type} [Encodable K] [Encodable V]
    (hK : ∀ (k₁ k₂ : K), Encodable.encode k₁ = Encodable.encode k₂ → k₁ = k₂)
    (hV : ∀ (v₁ v₂ : V), Encodable.encode v₁ = Encodable.encode v₂ → v₁ = v₂)
    (hKLen : ∀ (k : K), (Encodable.encode k).length = 9)  -- CBE head bound
    (hVLen : ∀ (v : V), (Encodable.encode v).length = 9)  -- CBE head bound (or document the Nat/ByteArray case explicitly)
    {pairs₁ pairs₂ : List (K × V)}
    (h : encodeSortedPairs pairs₁ = encodeSortedPairs pairs₂) :
    pairs₁ = pairs₂
```

**Note on length hypotheses.**  The above formulation is the
simplest case where K and V both have fixed-width encodings (9 bytes
each via `cborHeadEncode`).  For variable-width encodings (e.g.
`ByteArray`), the formulation needs adjusting: variable-width
encodings include their own length prefix, so the boundary between
two adjacent pair encodings is unambiguous *from the bytes alone*.
The proof still goes through; it just doesn't need the `hKLen` /
`hVLen` hypotheses (they're replaced by reliance on the
`Encodable` instance's self-delimiting structure).

**Recommendation.**  Ship two variants: one for the fixed-width
case (used by `NonceState`, `KeyRegistry`, `BridgeState.consumed`,
`BridgeState.pending`'s inner-bytes form) and one for the
self-delimiting case (covering when the value is itself an
`Encodable ByteArray`).  Specialise each per-sub-state proof to
the variant that fits.

**Proof structure (sketch, fixed-width case).**

  1. Unfold `encodeSortedPairs`: both sides are
     `cborHeadEncode cbeTagMap n_i ++ ⟨concat of pair encodings⟩`.
  2. By `cborHeadEncode_injective` (EI.1.c), the two pair-counts
     are equal: `pairs₁.length = pairs₂.length`.
  3. By induction on `pairs₁`, the per-pair concatenations split
     into equal head pairs and equal tails (using `hKLen`/`hVLen`
     to slice the byte stream).
  4. By `hK` and `hV`, the head pair's key and value match.
  5. Conclude by `List.cons_inj`.

**Implementation steps.**

  1. State the fixed-width variant first.
  2. Prove via induction on `pairs₁` (≤ 30 lines).
  3. Add the self-delimiting variant; specialise the proof to
     use `Encodable`'s decode-friendly structure to find the
     pair boundary.
  4. Land both with shared `private` helpers as needed.

**Acceptance criteria.**

  * Both variants ship.
  * `#print axioms` clean.
  * `lake build` succeeds.

**Test plan.**

  * Term-level API tests for both variants.
  * Value-level: three concrete pair lists (empty, singleton,
    three-element) for each variant.

**Reviewer checklist.**

  * Both variants documented with clear "when to use which".
  * The length-precondition is clearly stated and non-circular
    (i.e. it's a property of `Encodable K` / `Encodable V`, not a
    side condition the caller has to prove for each call site).

**Risk.**  Medium.  The induction's pair-boundary slicing is the
trickiest reasoning in the workstream; if the proof gets unwieldy,
fall back to a `decodeNPairs`-based formulation that uses
round-trip in the inductive step.

**Effort.**  ~1.0 engineer-day.

#### EI.1.f — UIntN injectivity quartet

**Scope.**  `LegalKernel/Encoding/Encodable.lean`.

**Math.**

```lean
theorem uInt8_encode_injective  : ∀ n₁ n₂ : UInt8,  Encodable.encode n₁ = Encodable.encode n₂ → n₁ = n₂
theorem uInt16_encode_injective : ∀ n₁ n₂ : UInt16, Encodable.encode n₁ = Encodable.encode n₂ → n₁ = n₂
theorem uInt32_encode_injective : ∀ n₁ n₂ : UInt32, Encodable.encode n₁ = Encodable.encode n₂ → n₁ = n₂
theorem uInt64_encode_injective : ∀ n₁ n₂ : UInt64, Encodable.encode n₁ = Encodable.encode n₂ → n₁ = n₂
```

**Proof structure.**  Each is `Encodable_via_decode_inj` (EI.1.b)
applied with the existing `uIntN_roundtrip` lemma
(`Encoding/Encodable.lean:634`, `659`, `684`, `709`).

**Implementation steps.**  Four lemmas, each ≤ 3 lines.

**Acceptance criteria.**  As EI.1.b.

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day.

#### EI.1.g — Project-wrapper injectivity sweep

**Scope.**  `LegalKernel/Encoding/Encodable.lean` (or per-type
sibling files; e.g. `Encoding/Identity.lean` for `ActorId` /
`PublicKey` if those have dedicated encoder files — audit during
implementation).

**Math.**  One lemma per wrapper.  Each is derivable from
`Encodable_via_decode_inj` (EI.1.b) given the existing
roundtrip lemmas, OR a one-line corollary of the underlying
atomic-carrier injectivity (e.g. `ActorId` is a `UInt64` abbrev;
`ActorId.encode_injective := uInt64_encode_injective`).

```lean
theorem actorId_encode_injective    : ∀ a₁ a₂ : ActorId,    encode a₁ = encode a₂ → a₁ = a₂
theorem amount_encode_injective     : ∀ a₁ a₂ : Amount,     encode a₁ = encode a₂ → a₁ = a₂
theorem nonce_encode_injective      : ∀ n₁ n₂ : Nonce,      encode n₁ = encode n₂ → n₁ = n₂
theorem resourceId_encode_injective : ∀ r₁ r₂ : ResourceId, encode r₁ = encode r₂ → r₁ = r₂
theorem publicKey_encode_injective  : ∀ p₁ p₂ : PublicKey,  encode p₁ = encode p₂ → p₁ = p₂
theorem depositId_encode_injective    : ∀ d₁ d₂ : Bridge.DepositId,    encode d₁ = encode d₂ → d₁ = d₂
theorem withdrawalId_encode_injective : ∀ w₁ w₂ : Bridge.WithdrawalId, encode w₁ = encode w₂ → w₁ = w₂
```

**Note on `EthAddress`.**  `EthAddress` is a separate type with
its own `toBytes`/`ofBytes` pair (not directly an `Encodable`
instance at the wrapper level — see `PendingWithdrawal.encode`
which uses `Encodable.encode (T := ByteArray) (EthAddress.toBytes
wd.recipient)`).  EI.7.a separately verifies `EthAddress.toBytes`
injectivity; the combined `EthAddress`-via-`ByteArray`-encoding
injectivity is then a one-liner.

**Pre-implementation audit.**  Some of these may be the *same
declaration as their underlying primitive* (e.g. if
`ActorId := UInt64` and `Encodable ActorId` is the same instance
as `Encodable UInt64`, then `actorId_encode_injective` is
literally `uInt64_encode_injective`).  Check during
implementation; ship as either re-export or distinct lemma
following the existing project convention.

**Implementation steps.**

  1. For each wrapper, run `#check Encodable` and `#check
     (Encodable.encode : <Wrapper> → Stream)` to determine whether
     the encoding is delegated to the underlying primitive.
  2. If delegated: ship as `theorem <wrapper>_encode_injective :=
     <primitive>_encode_injective` (re-export).
  3. If wrapped (rare): use `Encodable_via_decode_inj` (EI.1.b).

**Acceptance criteria.**

  * All seven (or eight, counting EthAddress) lemmas ship.
  * `#print axioms` clean for each.

**Risk.**  Trivial.

**Effort.**  ~0.3 engineer-day.

#### EI.1.h — `List α` / `Option α` injectivity (parameterised)

**Scope.**  `LegalKernel/Encoding/Encodable.lean`.

**Math.**

```lean
theorem list_encode_injective
    {α : Type} [Encodable α]
    (hα : ∀ (a₁ a₂ : α), Encodable.encode a₁ = Encodable.encode a₂ → a₁ = a₂)
    {xs₁ xs₂ : List α}
    (h : Encodable.encode xs₁ = Encodable.encode xs₂) :
    xs₁ = xs₂

theorem option_encode_injective
    {α : Type} [Encodable α]
    (hα : ∀ (a₁ a₂ : α), Encodable.encode a₁ = Encodable.encode a₂ → a₁ = a₂)
    {o₁ o₂ : Option α}
    (h : Encodable.encode o₁ = Encodable.encode o₂) :
    o₁ = o₂
```

**Proof structure.**

  * **`list_encode_injective`.**  Induction on `xs₁`:
    - Empty case: the encoded prefix is `cbeTagArray ++ <0 count>`;
      pair-equality forces `xs₂ = []` by `cborHeadEncode_injective`
      (EI.1.c).
    - Cons case: split `xs₂ = x₂' :: xs₂'`; the head-byte equality
      forces equal counts; the per-element encodings then split by
      `hα`-injective and induction hypothesis.

  * **`option_encode_injective`.**  Two-case analysis: each
    `Option` variant has a distinct tag byte (`some` vs `none`);
    same-tag implies same payload by `hα`.

**Implementation steps.**

  1. State both lemmas with the `hα`-parameterised shape.
  2. Prove `list_encode_injective` by induction (≤ 25 lines).
  3. Prove `option_encode_injective` by case-split (≤ 12 lines).

**Acceptance criteria.**

  * Both lemmas ship.
  * `#print axioms` clean.

**Risk.**  Low.

**Effort.**  ~0.4 engineer-day.

#### EI.1.i — `Encodable.encode_injective` hypothesis-propagation lemma

**Scope.**  `LegalKernel/Encoding/Encodable.lean`.

**Math.**  Sugar lemma that packages the `EI.1.b` + `EI.1.f` +
`EI.1.g` + `EI.1.h` chain into a "one-stop" lookup for downstream
proofs.  No new mathematical content; pure ergonomic helper.

```lean
/-- For an atomic carrier with a shipped roundtrip lemma, the
    `Encodable.encode_injective` precondition required by
    `encodeSortedPairs_injective` is automatic.  Provided here as
    a typeclass-friendly wrapper so per-sub-state proofs can
    `simp [encode_injective]` rather than manually unfolding. -/
class Encodable.HasInjective (T : Type) [Encodable T] : Prop where
  encode_injective : ∀ (v₁ v₂ : T),
    Encodable.encode v₁ = Encodable.encode v₂ → v₁ = v₂
```

Plus instances for each atomic carrier (one-liner each).

**Implementation steps.**

  1. Add the `HasInjective` class.
  2. Add instances for `Bool`, `Nat`, `BoundedNat`, `ByteArray`,
     `UInt8/16/32/64`, `ActorId`, `Amount`, `Nonce`, `ResourceId`,
     `PublicKey`, `DepositId`, `WithdrawalId`.
  3. Provide a parameterised instance for `List α` / `Option α`
     gated by `[HasInjective α]`.

**Note.**  This is a quality-of-life addition that pays for itself
over EI.2 – EI.7; it isn't required for correctness.  If the
project prefers explicit hypotheses over typeclass machinery, the
maintainer may strike this sub-unit and have each per-sub-state
proof pass the injectivity hypotheses explicitly.

**Acceptance criteria.**

  * `HasInjective` class + all instances ship.
  * `#print axioms` clean.
  * No `instance`-search performance regression in `lake build`.

**Reviewer checklist.**

  * Class is `Prop`-valued (not `Type`-valued) — keeps elaboration
    cheap.
  * No circular instance chains.

**Risk.**  Low; if instance-search slows the build, can be
removed by un-marking the instances.

**Effort.**  ~0.3 engineer-day.

---

### EI.1 — Rolled-up acceptance criteria

  * EI.1.b – EI.1.i individually accepted (EI.1.a only if needed).
  * The seven (or eight) sub-sub-units land as 4–6 PRs at
    reviewer discretion.
  * **Aggregate effort:** ~3.0 engineer-days (or ~3.5 with EI.1.a).

### §4.2 EI.2 — `State.encode` template (nested map)

**Finding map.**  AR.4.2 (template) + M-3.

**Scope.**  `LegalKernel/Encoding/StateInjective.lean` (new file
per OQ-EI-1's Option B).  Inner-encoder helpers may be added to
`LegalKernel/Encoding/State.lean` directly when they're sibling
lemmas to existing `encodeAsBytes` machinery.

**Why this is the template.**  `State.encode` is the *only*
nested-map sub-state.  EI.2 establishes the framing-then-outer-map
proof pattern that EI.3 – EI.7 specialise to flat-map carriers
(and EI.5 / EI.6 / EI.7 reuse for their rich-value inner records).
If the nested-map proof exposes any obstacle (e.g. an inner-encoder
length-bound that doesn't fit the EI.1.e signature), EI.2's review
surfaces it before parallel work on EI.3 – EI.7 begins.

**EI.2 decomposes into six sub-sub-units.**

#### EI.2.a — `BalanceMap.encode_injective` (inner-map injectivity)

**Scope.**  `LegalKernel/Encoding/StateInjective.lean`.

**Math.**

```lean
theorem BalanceMap.encode_injective :
  ∀ (bm₁ bm₂ : BalanceMap),
    BalanceMap.encode bm₁ = BalanceMap.encode bm₂ →
    bm₁.Equiv bm₂
```

**Proof structure (step-by-step per §2.4).**

  1. **Step A.**  Unfold `BalanceMap.encode` (`Encoding/State.lean:197`):
     ```
     BalanceMap.encode bm = encodeSortedPairs (bm.toList.map (fun (a, v) => (a.toNat, v)))
     ```
     The `(K, V)` of the underlying `encodeSortedPairs` call is `(Nat, Amount)`.
  2. **Step B.**  Apply `EI.1.e` (`encodeSortedPairs_injective`)
     specialised to `K := Nat`, `V := Amount`.  Required
     preconditions:
       * `hK := nat_encode_injective` (with the `< 2^64`
         hypothesis; discharged because every `a : ActorId =
         UInt64` has `a.toNat < 2^64`).
       * `hV := amount_encode_injective` (EI.1.g; `Amount := Nat`
         with the same bound).
  3. **Step C (key bijection).**  The result of EI.1.e is
     `(bm₁.toList.map proj) = (bm₂.toList.map proj)` where `proj :
     (ActorId × Amount) → (Nat × Amount) := fun (a, v) => (a.toNat, v)`.
     Need to lift to `bm₁.toList = bm₂.toList`.
       * `proj` is injective: `a.toNat = b.toNat → a = b` by
         `UInt64.toNat_injective` (a `Std` / project-shipped
         bijection; audit during implementation, fall back to
         `UInt64.toNat`-defined-via-`val` if needed).
       * `List.map_injective_of_injective` (Std) closes the lift.
  4. **Step D.**  Apply `Std.TreeMap.equiv_iff_toList_eq.mpr` to
     get `bm₁.Equiv bm₂`.

**Implementation steps.**

  1. State and prove `BalanceMap.encode_injective` in
     `Encoding/StateInjective.lean`.
  2. If `UInt64.toNat_injective` isn't shipped by Std or the
     project, ship it as a small auxiliary
     (`private lemma uint64_toNat_injective`); 3 lines via
     `UInt64.toNat` = `UInt64.val` and `Fin.val_injective`.

**Acceptance criteria.**

  * Theorem ships.
  * `#print axioms BalanceMap.encode_injective` ⊆ `[propext,
    Classical.choice, Quot.sound]`.
  * `lake build LegalKernel.Encoding.StateInjective` succeeds.

**Test plan.**

  * **Three baseline fixtures.**  Empty, singleton, five-entry
    `BalanceMap`.
  * **Positive (injectivity direction):** for each fixture pair
    `(bm₁, bm₂)` that differ on at least one actor's amount,
    assert encoding differs.
  * **Negative (determinism direction):** structurally-distinct
    extensionally-equal variant (different insertion order); assert
    encoding equal (re-uses the existing
    `balanceMap_encode_deterministic_of_equiv`).
  * **Term-level:** `let _ : ∀ bm₁ bm₂, … :=
    BalanceMap.encode_injective` ascription.

**Reviewer checklist.**

  * `UInt64.toNat_injective` is real (verifies it's not a
    misremembered Std name).
  * The `< 2^64` precondition discharge is mechanical (not
    "discharged by `decide`" on an unbounded universe).

**Risk.**  Low.  Direct template instance.

**Effort.**  ~0.8 engineer-day.

#### EI.2.b — `BalanceMap.encode_injective` lift to Equiv (verify)

**Scope.**  `LegalKernel/Encoding/StateInjective.lean`.

**Activity.**  Sanity-check that EI.2.a's conclusion is genuinely
`bm₁.Equiv bm₂` and not a weaker variant (e.g. raw `toList`-equality
without the `Equiv` Std-API wrapper).  If EI.2.a's proof shipped
`bm₁.toList = bm₂.toList` as a stepping stone, this sub-unit lifts
to the `Equiv`-wrapped form via `equiv_iff_toList_eq`.

This may be a no-op if EI.2.a directly returns `Equiv`; in that
case EI.2.b's content collapses to a one-line
`@[simp]` alternative phrasing or a test-only assertion.

**Implementation steps.**

  1. Confirm EI.2.a returns `Equiv`-shaped.
  2. If not, add the `Equiv`-shaped variant:
     ```lean
     theorem BalanceMap.encode_injective_to_equiv
         (bm₁ bm₂ : BalanceMap)
         (h : BalanceMap.encode bm₁ = BalanceMap.encode bm₂) :
         bm₁.Equiv bm₂ :=
       Std.TreeMap.equiv_iff_toList_eq.mpr
         (BalanceMap.encode_injective bm₁ bm₂ h)
     ```
  3. Replace EI.2.a's headline name if redundant.

**Acceptance criteria.**

  * EI.2.a or EI.2.a + EI.2.b together expose an `Equiv`-shaped
    theorem.

**Risk.**  Trivial.

**Effort.**  ~0.1 engineer-day.

#### EI.2.c — `BalanceMap.encodeAsBytes_injective`

**Scope.**  `LegalKernel/Encoding/StateInjective.lean` (or
`Encoding/State.lean` next to `encodeAsBytes` itself).

**Math.**

```lean
theorem BalanceMap.encodeAsBytes_injective
    (bm₁ bm₂ : BalanceMap)
    (h : BalanceMap.encodeAsBytes bm₁ = BalanceMap.encodeAsBytes bm₂) :
    bm₁.Equiv bm₂
```

**Proof structure.**  Direct application of EI.1.d's `Equiv`
variant with EI.2.a/b as the inner-injectivity hypothesis.

**Implementation steps.**

  1. State and prove.

**Note on visibility.**  `BalanceMap.encodeAsBytes` is `private` in
`Encoding/State.lean` (line 205).  This sub-unit either (a) promotes
it to non-`private` (visibility decision — requires reviewer
consensus; document in OQ-EI-2), or (b) ships the injectivity
lemma inside `Encoding/State.lean` itself (so `private` stays
intact).  Recommendation: option (b) — keeps the visibility surface
unchanged.

**Acceptance criteria.**

  * Theorem ships.
  * `#print axioms` clean.

**Reviewer checklist.**

  * Visibility decision recorded in OQ-EI-2.

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day.

#### EI.2.d — `State.encode_injective` (nested headline)

**Scope.**  `LegalKernel/Encoding/StateInjective.lean`.

**Math.**

```lean
theorem State.encode_injective :
  ∀ (s₁ s₂ : State),
    State.encode s₁ = State.encode s₂ →
    s₁.balances.Equiv s₂.balances ∧
    (∀ r, ∀ (h₁ : s₁.balances[r]? = some bm₁) (h₂ : s₂.balances[r]? = some bm₂),
       bm₁.Equiv bm₂)
```

**Hmm — formulation note.**  The naive flat statement `∀ r,
s₁.balances[r]? = s₂.balances[r]?` is **strictly weaker** than the
nested form: it compares inner `BalanceMap` `Option`s by `Eq`, which
fails when two extensionally-equal inner maps are structurally
distinct.  The right form uses outer `Equiv` plus a per-resource
inner-`Equiv` quantifier.

The cleanest formulation defines a "nested Equiv" relation:

```lean
def State.Equiv (s₁ s₂ : State) : Prop :=
  ∃ (h_outer_keys : ∀ r, s₁.balances[r]?.isSome = s₂.balances[r]?.isSome),
    ∀ r bm₁ bm₂,
      s₁.balances[r]? = some bm₁ → s₂.balances[r]? = some bm₂ →
      bm₁.Equiv bm₂
```

Then `State.encode_injective : encode s₁ = encode s₂ → s₁.Equiv s₂`.

**Proof structure.**

  1. **Step A.**  Unfold `State.encode`
     (`Encoding/State.lean:214`):
     ```
     State.encode s = encodeSortedPairs (s.balances.toList.map (fun (r, bm) =>
       (r.toNat, BalanceMap.encodeAsBytes bm)))
     ```
     The `(K, V)` of the outer `encodeSortedPairs` is `(Nat,
     ByteArray)`.
  2. **Step B.**  Apply EI.1.e specialised to `(Nat, ByteArray)`:
     - `hK := nat_encode_injective` (with bound; discharged via
       `UInt64.toNat < 2^64`).
     - `hV := byteArray_encode_injective` (already shipped at
       `Encoding/Encodable.lean:380`; with `< 2^64` size bound
       — discharged because every `BalanceMap.encodeAsBytes
       bm` has `.size` bounded by the canonical-encoding
       discipline).
  3. **Step C (outer key bijection).**  As in EI.2.a.
  4. **Step D (inner-bytes-to-Equiv).**  The pair-list equality
     gives, for each outer `r`, equality of the *inner ByteArrays*.
     Apply EI.2.c (`BalanceMap.encodeAsBytes_injective`)
     pointwise to convert each `ByteArray`-equality to
     `BalanceMap.Equiv`.
  5. **Step E.**  Assemble: outer `toList`-equality (from EI.1.e)
     gives outer `Equiv` (via `equiv_iff_toList_eq`); per-key
     inner `Equiv` gives the nested form.

**Implementation steps.**

  1. Define `State.Equiv` (or `State.balances_nested_equiv`).
  2. State and prove `State.encode_injective`.
  3. Add a "lift" lemma deriving `bm₁.Equiv bm₂` for each
     `r` where both inputs have an entry (the common consumer
     shape).
  4. Add the byte-size bound discharge for
     `BalanceMap.encodeAsBytes bm` — likely a length-bound
     auxiliary `BalanceMap.encodeAsBytes_size_bound` already
     shipped or trivially derivable.

**Acceptance criteria.**

  * Theorem ships.
  * `#print axioms State.encode_injective` ⊆ `[propext,
    Classical.choice, Quot.sound]`.

**Test plan.**

  * Three fixtures: empty `State`, single resource with three
    actors, two resources with disjoint actor sets.
  * Positive: pair of fixtures differing on at least one
    `(resource, actor)` cell; assert encoding differs.
  * Negative: structurally-distinct same-content `State`; assert
    encoding equal.
  * Term-level API.

**Reviewer checklist.**

  * `State.Equiv` definition is principled (not ad-hoc).
  * No reliance on `Eq` for inner `BalanceMap` comparison.
  * The byte-size discharge for `BalanceMap.encodeAsBytes` is
    real, not skipped by `simp`.

**Risk.**  Medium.  The nested formulation is the trickiest
piece in the workstream; the inner-bytes-to-Equiv lift requires
careful per-index reasoning.

**Effort.**  ~1.0 engineer-day.

#### EI.2.e — Test fixtures + term-level API

**Scope.**  `LegalKernel/Test/Encoding/Injectivity.lean` (the file
scaffolded by EI.0.c).

**Test plan.**  Covers EI.2.a – EI.2.d as a unified suite:

  * Three baseline fixtures shared with EI.3 – EI.7.
  * For each EI.2.* theorem, a term-level API stability ascription.
  * Three positive-direction integration tests (the encoder
    actually distinguishes distinct-input pairs).
  * Three negative-direction integration tests (the encoder
    actually agrees on structurally-distinct same-content pairs).

**Implementation steps.**

  1. Add `Test.Encoding.Injectivity.balanceMap_*` test cases.
  2. Add `Test.Encoding.Injectivity.state_*` test cases.
  3. Confirm `lake test` passes; record the new test count in
     EI.2.f's retrospective.

**Acceptance criteria.**

  * `lake test` passes with the new tests.
  * Total test count increases by ≥ 6 (the six listed).

**Risk.**  Trivial.

**Effort.**  ~0.3 engineer-day.

#### EI.2.f — Retrospective for EI.3 – EI.7 plan review

**Scope.**  This document.

**Activity.**  After EI.2.a – EI.2.e land, the implementer writes
a short (≤ 200 words) retrospective covering:

  * Was the `Equiv`-as-target choice (vs raw pointwise `getElem?`)
    a net win?  Should EI.3 – EI.7 keep it?
  * Was `encodeAsBytes_injective_of_encode_injective` (EI.1.d) the
    right granularity, or should each call site inline the framing
    proof?
  * Was `encodeSortedPairs_injective` (EI.1.e) callable as-is, or
    did EI.2.d need to bypass it for the variable-width
    `ByteArray` value type?
  * Should the per-sub-state lemmas use the `Equiv`-conclusion or
    a per-sub-state derived "extensional pointwise lookup"
    conclusion?  (The plan currently mandates `Equiv` per Goal 1;
    revisit if EI.2 surfaces a usability problem.)

The retrospective lands as a small Edit to this plan's §3.3
"Critical path" section.  If revisions to EI.3 – EI.7 are needed,
they land *before* parallel work starts.

**Risk.**  Trivial.

**Effort.**  ~0.1 engineer-day.

---

### EI.2 — Rolled-up acceptance criteria

  * EI.2.a – EI.2.e all individually accepted.
  * EI.2.f retrospective committed.
  * **Aggregate effort:** ~2.5 engineer-days.

### §4.3 EI.3 — `NonceState.encode_injective`

**Finding map.**  AR.4.3 + M-3.

**Scope.**  `LegalKernel/Encoding/StateInjective.lean` (the same
file as EI.2; sub-state is encoded in the same `Encoding/State.lean`
source).

#### EI.3.a — `NonceState.encode_injective`

**Math.**

```lean
theorem NonceState.encode_injective :
  ∀ (n₁ n₂ : NonceState),
    NonceState.encode n₁ = NonceState.encode n₂ →
    n₁.next.Equiv n₂.next
```

Flat map: `TreeMap ActorId Nonce compare`.  One application of the
§2.4 recipe.

**Note on conclusion shape.**  The `Equiv` is on the underlying
`next` field (the inner `TreeMap`), not on `NonceState` itself.
The `NonceState` structure has only the one map-typed field; a
`NonceState.Equiv` derived definition (`n₁.next.Equiv n₂.next`) is
unnecessary and would obscure the proof.  Downstream consumers can
derive `n₁.expectedNonce a = n₂.expectedNonce a` for all `a` via
`Std.TreeMap.equiv_iff_toList_eq` + `expectedNonce`'s definition
(`Authority/Nonce.lean` — `lp[a]?.getD 0`).

**Proof structure.**

  1. **Step A.**  Unfold `NonceState.encode`
     (`Encoding/State.lean:269`):
     ```
     NonceState.encode ns = encodeSortedPairs (ns.next.toList.map
       (fun (a, n) => (a.toNat, n)))
     ```
     The `(K, V)` is `(Nat, Nonce)`.
  2. **Step B.**  Apply EI.1.e with `hK := nat_encode_injective`,
     `hV := nonce_encode_injective` (EI.1.g; `Nonce := Nat`).
  3. **Step C.**  Key bijection via `UInt64.toNat_injective`.
  4. **Step D.**  `equiv_iff_toList_eq.mpr`.

**Implementation steps.**

  1. State the theorem.
  2. Prove via §2.4 steps A – E.
  3. (Optional) ship a derived "pointwise nonce equality" lemma
     `expectedNonce_eq_of_encode_eq`:

     ```lean
     theorem NonceState.expectedNonce_eq_of_encode_eq
         (n₁ n₂ : NonceState)
         (h : NonceState.encode n₁ = NonceState.encode n₂) :
         ∀ a, n₁.expectedNonce a = n₂.expectedNonce a
     ```

     Useful for callers that want the application-level form
     directly; derived via EI.3.a + `equiv_iff_toList_eq` +
     `expectedNonce`'s definition.

**Acceptance criteria.**

  * `NonceState.encode_injective` ships.
  * `#print axioms` clean.
  * `lake build` succeeds.

**Reviewer checklist.**

  * Conclusion is `n₁.next.Equiv n₂.next` (not raw `Eq`).
  * Optional pointwise variant has matching docstring.

**Risk.**  Low.  Flat map, atomic value.

**Effort.**  ~0.5 engineer-day.

#### EI.3.b — Tests + term-level API

**Scope.**  `LegalKernel/Test/Encoding/Injectivity.lean`.

**Test plan.**

  * Three baseline fixtures: empty `NonceState`, single actor
    nonce-3, three actors with mixed nonces.
  * Positive: pair with at least one differing nonce.
  * Negative: structurally-distinct same-content.
  * Term-level API ascription.

**Implementation steps.**

  1. Add `Test.Encoding.Injectivity.nonceState_*` test cases.

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day.

---

### EI.3 — Rolled-up acceptance criteria

  * EI.3.a + EI.3.b individually accepted.
  * **Aggregate effort:** ~0.7 engineer-day.

---

### §4.4 EI.4 — `KeyRegistry.encodeMap_injective`

**Finding map.**  AR.4.4 + M-3.

**Scope.**  `LegalKernel/Encoding/StateInjective.lean`.

#### EI.4.a — `KeyRegistry.encodeMap_injective`

**Math.**

```lean
theorem KeyRegistry.encodeMap_injective :
  ∀ (kr₁ kr₂ : KeyRegistry),
    KeyRegistry.encodeMap kr₁ = KeyRegistry.encodeMap kr₂ →
    kr₁.Equiv kr₂
```

`KeyRegistry := TreeMap ActorId PublicKey compare`.  Flat map.

**Proof structure.**

  1. **Step A.**  Unfold `KeyRegistry.encodeMap`
     (`Encoding/State.lean:273`):
     ```
     KeyRegistry.encodeMap kr = encodeSortedPairs (kr.toList.map
       (fun (a, pk) => (a.toNat, pk)))
     ```
     The `(K, V)` is `(Nat, PublicKey)`.
  2. **Step B.**  Apply EI.1.e with `hK := nat_encode_injective`,
     `hV := publicKey_encode_injective` (EI.1.g).
  3. **Step C / D.**  As in EI.3.a.

**Implementation steps.**

  1. State and prove.
  2. (Optional) ship a derived `publicKeyOf_eq_of_encode_eq` for
     the application-level form
     (`kr.publicKeyOf a := kr[a]?.getD <default>` — verify the
     exact definition in `Authority/Identity.lean`).

**Pre-implementation audit note.**  `PublicKey` encoding goes
through `Encodable ByteArray`.  If `byteArray_encode_injective`
(`Encoding/Encodable.lean:380`) is conditional on `< 2^64` size,
verify that `PublicKey` has a fixed byte-length (typically 32 or
64) that satisfies the bound trivially.  Audit during
implementation; ship a small auxiliary if needed
(`publicKey_size_lt_2_64`).

**Acceptance criteria.**

  * Theorem ships.
  * `#print axioms` clean.

**Reviewer checklist.**

  * `byteArray_encode_injective`'s preconditions are discharged
    (not skipped).
  * Conclusion is `kr₁.Equiv kr₂`.

**Risk.**  Low.

**Effort.**  ~0.5 engineer-day.

#### EI.4.b — Tests + term-level API

**Scope.**  `LegalKernel/Test/Encoding/Injectivity.lean`.

**Test plan.**

  * Three baseline fixtures: empty `KeyRegistry`, single actor,
    three actors.
  * Positive / negative / term-level as EI.3.b.

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day.

---

### EI.4 — Rolled-up acceptance criteria

  * EI.4.a + EI.4.b individually accepted.
  * **Aggregate effort:** ~0.7 engineer-day.

---

### §4.5 EI.5 — `LocalPolicies.encodeMap_injective`

**Finding map.**  AR.4.5 + M-3.

**Scope.**  `LegalKernel/Encoding/LocalPolicyInjective.lean` (new
file, per OQ-EI-1's Option B).

**Why this is the second-hardest sub-state.**  Unlike EI.3 / EI.4 /
EI.6 / EI.7 (atomic or fixed-shape value carriers), the value type
`LocalPolicy` is a struct wrapping a `List LocalPolicyClause`,
where `LocalPolicyClause` is itself an inductive with three
constructors of varying arities.  Injectivity factors through:

  1. CBE constructor-tag discrimination for `LocalPolicyClause`
     (different tags → different bytes).
  2. Per-arm field injectivity for each `LocalPolicyClause`
     constructor.
  3. List-level injectivity (`list_encode_injective` from EI.1.h).
  4. Struct-field injectivity (`LocalPolicy` has the single field
     `clauses`; mechanical).
  5. Map-level injectivity (the §2.4 recipe).

**EI.5 decomposes into five sub-sub-units.**

#### EI.5.a — `LocalPolicyClause.encode_injective`

**Pre-implementation audit.**  Before coding, search for any
existing clause-level injectivity:

```bash
grep -rn "LocalPolicyClause.*injective\|encode_injective.*LocalPolicyClause" \
  LegalKernel/Encoding/ LegalKernel/Authority/ Lex/
```

The Lex M2 constructor-tag pinning machinery may already supply
adjacent lemmas (round-trip / determinism).  If found, EI.5.a may
be a re-export or a small derivation; otherwise EI.5.a lands a
fresh proof.

**Math (always needed, in some form).**

```lean
theorem LocalPolicyClause.encode_injective :
  ∀ (c₁ c₂ : LocalPolicyClause),
    Encodable.encode c₁ = Encodable.encode c₂ →
    c₁ = c₂
```

Structural equality (`c₁ = c₂` as Lean `Eq`), not extensional.
Inductives admit structural equality directly; the canonical Lean
`Eq` is the right notion for non-map data.

**Proof structure.**

  1. CBE encoding of an inductive prefixes a constructor-tag byte
     (per `Encoding/CBOR.lean` discipline).  Confirm the encoder
     definition for `LocalPolicyClause` in
     `Encoding/LocalPolicy.lean` — verify it follows the standard
     pattern.
  2. From `encode c₁ = encode c₂`, the tag bytes match → both
     are the same constructor.
  3. Case-split on the constructor (3 cases for the actual three
     constructors `denyTags`, `requireRecipientIn`, `capAmount`):
       * `denyTags (tags₁ : List Nat)`: by `list_encode_injective`
         (EI.1.h) with `hα := nat_encode_injective`, conclude
         `tags₁ = tags₂`.
       * `requireRecipientIn (resource₁ : ResourceId) (allowed₁ :
         List ActorId)`: by `resourceId_encode_injective` plus
         `list_encode_injective` with `hα :=
         actorId_encode_injective`.
       * `capAmount (resource₁ : ResourceId) (max₁ : Amount)`: by
         `resourceId_encode_injective` plus
         `amount_encode_injective`.
  4. The cross-arm cases (3 × 3 = 9 total; 3 same-constructor + 6
     different-constructor) discharge as follows:
       * Same-constructor: as above.
       * Different-constructor: contradicts tag-byte equality.

**Implementation steps.**

  1. State the theorem in `Encoding/LocalPolicyInjective.lean`.
  2. Proof by `cases c₁ <;> cases c₂` (9 cases).
  3. Use `simp [Encodable.encode]` + tag-mismatch contradiction
     for the 6 cross-arm cases.
  4. Discharge the 3 same-arm cases by per-field injectivity.

**Acceptance criteria.**

  * Theorem ships.
  * `#print axioms` clean.

**Reviewer checklist.**

  * The 6 cross-arm cases are *actually proved*, not skipped via
    `decide` (which would be expensive on the encoding's universe).
  * The 3 same-arm cases use the per-field atomic injectivity
    correctly (not via `simp [encode]` alone — that may not
    discharge cleanly).

**Risk.**  Low.  Standard inductive case-split.

**Effort.**  ~0.6 engineer-day.

#### EI.5.b — `LocalPolicy.encode_injective`

**Math.**

```lean
theorem LocalPolicy.encode_injective :
  ∀ (p₁ p₂ : LocalPolicy),
    Encodable.encode p₁ = Encodable.encode p₂ →
    p₁ = p₂
```

Structural equality.  `LocalPolicy` is a single-field struct
(`clauses : List LocalPolicyClause`); two LocalPolicies are equal
iff their `clauses` lists are equal.

**Proof structure.**

  1. From struct encoding (which is the encoding of the single
     field per CBE struct discipline), extract `clauses` byte
     equality.
  2. Apply `list_encode_injective` (EI.1.h) with `hα :=
     LocalPolicyClause.encode_injective` (EI.5.a) to get
     `clauses₁ = clauses₂`.
  3. Use `LocalPolicy.ext` (Lean's auto-generated structure
     extensionality) to conclude `p₁ = p₂`.

**Implementation steps.**

  1. State the theorem.
  2. `intro p₁ p₂ h`.
  3. `apply LocalPolicy.ext`.
  4. Apply `list_encode_injective` with the EI.5.a hypothesis.

**Pre-implementation audit.**  Verify `LocalPolicy` is genuinely
a single-field struct.  Plan's audit confirmed this for the
current revision; if the struct gains additional fields in a future
amendment, EI.5.b's proof needs a corresponding field-injectivity
step per added field.

**Acceptance criteria.**

  * Theorem ships.
  * `#print axioms` clean.

**Risk.**  Low.

**Effort.**  ~0.3 engineer-day.

#### EI.5.c — `LocalPolicy.encodeAsBytes_injective`

**Scope.**  `Encoding/LocalPolicyInjective.lean`.

**Math.**  If `LocalPolicies.encodeMap` uses an `encodeAsBytes`
framing for the inner `LocalPolicy` value (audit during
implementation), ship the framing-injectivity lemma:

```lean
theorem LocalPolicy.encodeAsBytes_injective
    (p₁ p₂ : LocalPolicy)
    (h : LocalPolicy.encodeAsBytes p₁ = LocalPolicy.encodeAsBytes p₂) :
    p₁ = p₂
```

Direct application of EI.1.d's `Eq` variant with EI.5.b as the
inner hypothesis.

**Conditional inclusion.**  Audit `Encoding/LocalPolicy.lean`'s
`LocalPolicies.encodeMap` body to confirm whether the inner
`LocalPolicy` is encoded via `encodeAsBytes` framing (mirroring
the BalanceMap / DepositRecord / PendingWithdrawal pattern), or
inlined directly without framing.  If inlined, EI.5.c is omitted
and EI.5.d directly invokes EI.5.b.

**Implementation steps (if needed).**

  1. State and prove via EI.1.d.

**Acceptance criteria.**

  * If shipped: `#print axioms` clean.

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day (or 0 if not needed).

#### EI.5.d — `LocalPolicies.encodeMap_injective`

**Math.**

```lean
theorem LocalPolicies.encodeMap_injective :
  ∀ (ps₁ ps₂ : LocalPolicies),
    LocalPolicies.encodeMap ps₁ = LocalPolicies.encodeMap ps₂ →
    ps₁.Equiv ps₂
```

`LocalPolicies := TreeMap ActorId LocalPolicy compare`.

**Proof.**  Standard §2.4 recipe with `LocalPolicy.encode_injective`
(EI.5.b) or `LocalPolicy.encodeAsBytes_injective` (EI.5.c) as the
inner injectivity, depending on whether the encoder uses framing.

**Implementation steps.**

  1. State and prove.
  2. (Optional) ship a `lookup_eq_of_encode_eq` derived lemma
     for the `LocalPolicies.lookup` application-level form
     (`lp.lookup a := lp[a]?.getD LocalPolicy.empty` per
     `Authority/LocalPolicy.lean:181`).

**Acceptance criteria.**  As EI.3.a.

**Risk.**  Low.

**Effort.**  ~0.4 engineer-day.

#### EI.5.e — Tests + term-level API

**Scope.**  `LegalKernel/Test/Encoding/Injectivity.lean`.

**Test plan.**

  * Clause fixtures: `denyTags [0, 1, 2]`, `requireRecipientIn 5
    [10, 20]`, `capAmount 5 100`.
  * Policy fixtures: empty, single `denyTags`, three mixed
    clauses.
  * Map fixtures: empty `LocalPolicies`, single actor with single
    `denyTags`, three actors with mixed clause types.
  * Positive: each pair differing on at least one clause / actor
    / list element.
  * Negative: structurally-distinct same-content.
  * Term-level API for all four theorems (EI.5.a, EI.5.b, EI.5.c
    if shipped, EI.5.d).

**Risk.**  Trivial.

**Effort.**  ~0.4 engineer-day.

---

### EI.5 — Rolled-up acceptance criteria

  * EI.5.a / EI.5.b / EI.5.c (if needed) / EI.5.d / EI.5.e
    individually accepted.
  * **Aggregate effort:** ~1.7–1.9 engineer-days.

### §4.6 EI.6 — `BridgeState.encodeConsumed_injective`

**Finding map.**  AR.4.6 + M-3.

**Scope.**  `LegalKernel/Encoding/BridgeInjective.lean` (new file,
per OQ-EI-1's Option B).

**Important correction from previous plan.**  The previous plan
described `BridgeState.consumed` as having `Unit` values; this is
incorrect.  The actual value type is `DepositRecord` — a 2-field
struct `{ resource : ResourceId, amount : Amount }` defined at
`Bridge/State.lean:145-150`.  EI.6 must ship injectivity for
`DepositRecord` first.

**EI.6 decomposes into four sub-sub-units.**

#### EI.6.a — `DepositRecord.encode_injective`

**Math.**

```lean
theorem Bridge.DepositRecord.encode_injective :
  ∀ (rec₁ rec₂ : Bridge.DepositRecord),
    Bridge.DepositRecord.encode rec₁ = Bridge.DepositRecord.encode rec₂ →
    rec₁ = rec₂
```

Structural equality (single struct, two atomic fields).

**Proof structure.**

  1. Unfold `Bridge.DepositRecord.encode` (`Encoding/State.lean:296`):
     ```
     encode rec = Encodable.encode (T := Nat) rec.resource.toNat ++
                  Encodable.encode (T := Nat) rec.amount
     ```
  2. The encoding is `head_resource ++ head_amount` where each
     head is 9 bytes (fixed-width Nat encoding via `cborHeadEncode`).
  3. From byte equality, split into `head_resource₁ = head_resource₂`
     (first 9 bytes) and `head_amount₁ = head_amount₂` (last 9
     bytes).
  4. Apply `nat_encode_injective` (with the standard `< 2^64`
     bound discharged for `ResourceId.toNat` and for `Amount`) to
     get field-wise equality.
  5. `Bridge.DepositRecord.ext` (struct extensionality) to
     conclude.
  6. Note that `ResourceId.toNat`'s injectivity (via
     `UInt64.toNat_injective`) is needed to lift `resource.toNat₁
     = resource.toNat₂` to `resource₁ = resource₂`.

**Alternative proof via `Encodable_via_decode_inj`.**  Since
`depositRecord_roundtrip` is shipped (`Encoding/State.lean:576`),
the cleaner proof is one line via EI.1.b:

```lean
theorem Bridge.DepositRecord.encode_injective
    (rec₁ rec₂ : Bridge.DepositRecord)
    (hBounds₁ : rec₁.resource.toNat < 256 ^ 8 ∧ rec₁.amount < 256 ^ 8)
    (hBounds₂ : rec₂.resource.toNat < 256 ^ 8 ∧ rec₂.amount < 256 ^ 8)
    (h : Bridge.DepositRecord.encode rec₁ = Bridge.DepositRecord.encode rec₂) :
    rec₁ = rec₂
```

The bounds are routine to discharge at call sites (`ResourceId :=
UInt64` ⇒ `toNat < 2^64`; `Amount := Nat` requires the
canonical-encoding bound, which is invariant of the kernel —
verify against `Authority.Action.lean`'s `Action` admissibility).

**Implementation steps.**

  1. Choose the `Encodable_via_decode_inj` route for brevity.
  2. State and prove (≤ 8 lines).
  3. Ship a `wrapper` lemma that discharges the bounds for the
     concrete `Bridge.DepositRecord` carrier
     (which is the only call-site shape):

     ```lean
     theorem Bridge.DepositRecord.encode_injective_canonical
         (rec₁ rec₂ : Bridge.DepositRecord)
         (h : Bridge.DepositRecord.encode rec₁ = Bridge.DepositRecord.encode rec₂) :
         rec₁ = rec₂
     ```

     where the bounds are discharged internally via the kernel's
     canonical-amount discipline.

**Acceptance criteria.**

  * Both lemmas ship (the explicit-bounds variant + the
    canonical-discharge wrapper).
  * `#print axioms` clean.

**Reviewer checklist.**

  * Canonical-amount discharge is principled (cites the kernel's
    invariant, not "discharged by `decide`").
  * The bounds are documented as canonical-encoding preconditions
    in the docstrings.

**Risk.**  Low.

**Effort.**  ~0.4 engineer-day.

#### EI.6.b — `DepositRecord.encodeAsBytes_injective`

**Scope.**  `Encoding/BridgeInjective.lean` (or `Encoding/State.lean`
to keep visibility intact — `encodeAsBytes` is `private` at
`Encoding/State.lean:318`).

**Math.**

```lean
theorem Bridge.DepositRecord.encodeAsBytes_injective
    (rec₁ rec₂ : Bridge.DepositRecord)
    (h : Bridge.DepositRecord.encodeAsBytes rec₁ = Bridge.DepositRecord.encodeAsBytes rec₂) :
    rec₁ = rec₂
```

**Proof.**  Direct application of EI.1.d's `Eq` variant with
EI.6.a as the inner hypothesis.

**Note on visibility.**  Same as EI.2.c — `encodeAsBytes` is
`private`.  Recommendation: ship the injectivity lemma inside
`Encoding/State.lean` (where `encodeAsBytes` is visible) and
re-export via `Encoding/BridgeInjective.lean`.

**Acceptance criteria.**  As EI.6.a.

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day.

#### EI.6.c — `BridgeState.encodeConsumed_injective`

**Math.**

```lean
theorem Bridge.BridgeState.encodeConsumed_injective :
  ∀ (bs₁ bs₂ : Bridge.BridgeState),
    Bridge.BridgeState.encodeConsumed bs₁ = Bridge.BridgeState.encodeConsumed bs₂ →
    bs₁.consumed.Equiv bs₂.consumed
```

**Proof.**  Standard §2.4 recipe.

  1. Unfold `encodeConsumed` (`Encoding/State.lean:323`):
     ```
     encodeConsumed bs = encodeSortedPairs (bs.consumed.toList.map
       (fun (d, rec) => (d, Bridge.DepositRecord.encodeAsBytes rec)))
     ```
     The `(K, V)` is `(Nat, ByteArray)`
     (`DepositId := Nat`).
  2. Apply EI.1.e with `hK := nat_encode_injective` and `hV :=
     byteArray_encode_injective`.
  3. Apply EI.6.b pointwise to lift the inner `ByteArray`-equality
     to `DepositRecord`-equality.
  4. Lift `toList`-equality to `Equiv` via `equiv_iff_toList_eq`.

**Acceptance criteria.**

  * Theorem ships.
  * `#print axioms` clean.

**Reviewer checklist.**

  * The conclusion is `Equiv`, not raw `Eq`.
  * The pointwise `DepositRecord` lift is explicit (no `simp`-
    magic).

**Risk.**  Low-medium.  The lift from outer `ByteArray`-equality to
inner `DepositRecord`-equality is the same shape as EI.2.d but
simpler (atomic fields rather than nested maps).

**Effort.**  ~0.5 engineer-day.

#### EI.6.d — Tests + term-level API

**Test plan.**

  * Three baseline fixtures: empty `BridgeState.consumed`, single
    deposit, three deposits.
  * Per-fixture pair: positive (differing deposit metadata) /
    negative (structurally-distinct same-content).
  * Term-level API.

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day.

---

### EI.6 — Rolled-up acceptance criteria

  * EI.6.a / EI.6.b / EI.6.c / EI.6.d individually accepted.
  * **Aggregate effort:** ~1.3 engineer-days.

---

### §4.7 EI.7 — `BridgeState.encodePending_injective` + `BridgeState.encode_injective`

**Finding map.**  AR.4.7 + M-3.

**Scope.**  `LegalKernel/Encoding/BridgeInjective.lean`.

**Important corrections from previous plan.**  The previous plan
described `PendingWithdrawal` as having fields `{ recipient,
amount, resourceId, l1Block }`.  The actual struct at
`Bridge/State.lean:155-167` has fields `{ resource, recipient,
amount, l2LogIndex }`.  In addition, `recipient : EthAddress` is
encoded via `EthAddress.toBytes` (a 20-byte serialisation) rather
than as a raw `Nat` — see `Encoding/State.lean:335-339`.  EI.7
must ship `EthAddress.toBytes`-injectivity as a prerequisite.

**EI.7 decomposes into six sub-sub-units.**

#### EI.7.a — `EthAddress.toBytes_injective` (if absent)

**Pre-implementation audit.**  Search for existing `EthAddress`
injectivity:

```bash
grep -rn "EthAddress.toBytes\|EthAddress_injective\|ofBytes_toBytes" \
  LegalKernel/Bridge/ LegalKernel/Encoding/
```

If a `toBytes_ofBytes_roundtrip` lemma already ships, EI.7.a is
a one-line corollary via `Encodable_via_decode_inj` (EI.1.b).
Otherwise EI.7.a ships both:

**Math.**

```lean
theorem Bridge.EthAddress.toBytes_injective :
  ∀ (e₁ e₂ : Bridge.EthAddress),
    Bridge.EthAddress.toBytes e₁ = Bridge.EthAddress.toBytes e₂ →
    e₁ = e₂
```

**Proof.**  If `EthAddress` is a `ByteArray` wrapper (the typical
representation), `toBytes` is the projection; injectivity follows
from the structural extensionality of the wrapper.  If `EthAddress`
is structurally richer, prove via `ofBytes`-roundtrip:

```
toBytes e₁ = toBytes e₂
⇒ ofBytes (toBytes e₁) = ofBytes (toBytes e₂)
⇒ some e₁ = some e₂   (by ofBytes_toBytes_roundtrip)
⇒ e₁ = e₂             (by Option.some.inj)
```

**Implementation steps.**

  1. Audit the `EthAddress` definition (`Bridge/State.lean` or
     `Bridge/Eip712.lean`).
  2. Ship `toBytes_injective` per the appropriate route.
  3. If `ofBytes`-roundtrip is missing, ship it as a small
     auxiliary (likely already in source — audit during
     implementation).

**Acceptance criteria.**

  * `toBytes_injective` ships.
  * `#print axioms` clean.

**Risk.**  Low.

**Effort.**  ~0.3 engineer-day (or 0 if already shipped).

#### EI.7.b — `PendingWithdrawal.encode_injective`

**Math.**

```lean
theorem Bridge.PendingWithdrawal.encode_injective
    (wd₁ wd₂ : Bridge.PendingWithdrawal)
    (hBounds₁ : wd₁.resource.toNat < 256 ^ 8 ∧ wd₁.amount < 256 ^ 8 ∧ wd₁.l2LogIndex < 256 ^ 8)
    (hBounds₂ : wd₂.resource.toNat < 256 ^ 8 ∧ wd₂.amount < 256 ^ 8 ∧ wd₂.l2LogIndex < 256 ^ 8)
    (h : Bridge.PendingWithdrawal.encode wd₁ = Bridge.PendingWithdrawal.encode wd₂) :
    wd₁ = wd₂
```

Structural equality (four-field struct).

**Proof structure.**

  1. Unfold `Bridge.PendingWithdrawal.encode`
     (`Encoding/State.lean:335`):
     ```
     encode wd = Encodable.encode (T := Nat) wd.resource.toNat ++
                 Encodable.encode (T := ByteArray) (Bridge.EthAddress.toBytes wd.recipient) ++
                 Encodable.encode (T := Nat) wd.amount ++
                 Encodable.encode (T := Nat) wd.l2LogIndex
     ```
  2. Decompose the byte stream into the four field encodings.
     The first, third, and fourth are fixed-width 9-byte
     `cborHeadEncode` outputs; the second is a length-prefixed
     `ByteArray` encoding (variable length but self-delimiting).
  3. Split byte-equality into per-field equalities (this is the
     trickier step — variable-length middle field requires the
     `ByteArray` encoding's self-delimiting property).  The
     cleanest route is via `Encodable_via_decode_inj` (EI.1.b)
     since `pendingWithdrawal_decode` ships at
     `Encoding/State.lean:348`.
  4. From `decode (encode wd₁) = .ok (wd₁, [])` and the same for
     `wd₂`, conclude `wd₁ = wd₂` by struct-extensionality on the
     decode output.

**Required pre-lemma.**  `pendingWithdrawal_roundtrip` — verify
this lemma exists at `Encoding/State.lean` or ship it as a small
auxiliary alongside EI.7.b.  Audit: the plan's first-look saw
`depositRecord_roundtrip` at line 576 but not a
`pendingWithdrawal_roundtrip` companion.  If missing, EI.7.b
divides into:

  * EI.7.b.i — ship `pendingWithdrawal_roundtrip`.
  * EI.7.b.ii — ship `encode_injective` via EI.1.b.

**Implementation steps.**

  1. Audit for `pendingWithdrawal_roundtrip` existence; ship if
     missing.
  2. State and prove `encode_injective` via EI.1.b.

**Acceptance criteria.**

  * `encode_injective` ships.
  * If `roundtrip` had to be shipped first, both ship together
    (atomic PR).
  * `#print axioms` clean.

**Reviewer checklist.**

  * The `EthAddress` recipient field is handled correctly (uses
    EI.7.a's `toBytes_injective`, not raw `Eq`).
  * Bounds for `l2LogIndex` discharge is principled (cites the
    runtime's bound, not "discharged by `decide`").

**Risk.**  Medium.  The four-field decomposition + `EthAddress`
encoding is the most complex per-value record in EI.

**Effort.**  ~0.7 engineer-day (or ~1.0 if `roundtrip` ships in
the same PR).

#### EI.7.c — `PendingWithdrawal.encodeAsBytes_injective`

**Math.**

```lean
theorem Bridge.PendingWithdrawal.encodeAsBytes_injective
    (wd₁ wd₂ : Bridge.PendingWithdrawal)
    (hBounds₁ : … as in EI.7.b)
    (hBounds₂ : … as in EI.7.b)
    (h : Bridge.PendingWithdrawal.encodeAsBytes wd₁ = Bridge.PendingWithdrawal.encodeAsBytes wd₂) :
    wd₁ = wd₂
```

**Proof.**  EI.1.d's `Eq` variant + EI.7.b.

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day.

#### EI.7.d — `BridgeState.encodePending_injective`

**Math.**

```lean
theorem Bridge.BridgeState.encodePending_injective :
  ∀ (bs₁ bs₂ : Bridge.BridgeState),
    Bridge.BridgeState.encodePending bs₁ = Bridge.BridgeState.encodePending bs₂ →
    bs₁.pending.Equiv bs₂.pending
```

**Proof.**  Standard §2.4 recipe with EI.7.c as the inner-value
framing injectivity.  Same shape as EI.6.c.

**Effort.**  ~0.5 engineer-day.

#### EI.7.e — `BridgeState.encode_injective` (concatenation)

**Math.**

```lean
theorem Bridge.BridgeState.encode_injective :
  ∀ (bs₁ bs₂ : Bridge.BridgeState),
    Bridge.BridgeState.encode bs₁ = Bridge.BridgeState.encode bs₂ →
    bs₁.consumed.Equiv bs₂.consumed ∧
    bs₁.pending.Equiv bs₂.pending ∧
    bs₁.nextWdId = bs₂.nextWdId
```

`BridgeState.encode` (`Encoding/State.lean:382`) is **a
concatenation of three encodings**, not a single-map encoding:

```
BridgeState.encode bs = encodeConsumed bs ++ encodePending bs ++ encode (T := Nat) bs.nextWdId
```

Injectivity must therefore decompose the concatenation:

**Proof structure.**

  1. The byte stream is structured as
     `[consumed_bytes ; pending_bytes ; nextWdId_bytes]`.
     Each segment is **self-delimiting**:
       * `encodeConsumed` starts with `cborHeadEncode cbeTagMap n`
         (9-byte head with pair-count), followed by exactly `n`
         pair encodings.  Total length is determinable from the
         head.
       * `encodePending` analogously.
       * `nextWdId` is a fixed-width `cborHeadEncode cbeTagUint`
         (9 bytes).
  2. Use the `decodeBridgeState` definition's structure
     (`Encoding/State.lean:427`) to split the bytes via
     `Encodable_via_decode_inj` (EI.1.b) — the cleanest route.
  3. From the three per-segment byte equalities, apply EI.6.c
     (for `consumed`), EI.7.d (for `pending`), and
     `nat_encode_injective` (for `nextWdId`) to conclude the
     three-way conjunction.

**Required pre-lemma.**  `bridgeState_roundtrip` — audit during
implementation.  If absent, ship as a precursor (similar to the
`pendingWithdrawal_roundtrip` situation in EI.7.b).

**Implementation steps.**

  1. Audit for `bridgeState_roundtrip`.
  2. State and prove `BridgeState.encode_injective` via EI.1.b
     and the per-segment lifts.

**Acceptance criteria.**

  * Theorem ships.
  * `#print axioms` clean.

**Risk.**  Medium.  Three-segment concatenation; if the
self-delimiting structure has any gap (e.g. a missing
length-prefix discipline), the decomposition fails.  The audit
of the round-trip lemma is the safety net.

**Effort.**  ~0.7 engineer-day.

#### EI.7.f — Tests + term-level API

**Test plan.**

  * `EthAddress` fixtures: a few representative 20-byte addresses.
  * `PendingWithdrawal` fixtures: three baseline.
  * `BridgeState.pending` fixtures: empty, single withdrawal,
    three.
  * `BridgeState` fixtures: empty, populated consumed only,
    populated pending only, both populated with `nextWdId > 0`.
  * Positive / negative / term-level for each of EI.7.a – EI.7.e.

**Risk.**  Trivial.

**Effort.**  ~0.4 engineer-day.

---

### EI.7 — Rolled-up acceptance criteria

  * EI.7.a (if needed) / EI.7.b / EI.7.c / EI.7.d / EI.7.e /
    EI.7.f individually accepted.
  * **Aggregate effort:** ~2.5–2.8 engineer-days.

### §4.8 EI.8 — Composition + documentation + landing

**Finding map.**  AR.4.8 + M-3 + CLAUDE.md footnote 1 retirement
+ AR.23 partial → complete + EI workstream closure.

**Scope.**  `LegalKernel/FaultProof/Commit.lean` (composition
theorem), `LegalKernel/Test/Integration/SnapshotBootstrap.lean`
(test lift), CLAUDE.md, GENESIS_PLAN.md,
`docs/planning/audit_remediation_plan.md`, this plan, AGENTS.md
(parity), and any straggler cross-references identified by
EI.8.j's grep sweep.

**EI.8 decomposes into ten sub-sub-units**, landing in a single
coordinated PR (the cross-document edits must be atomic; an
interleaved partial landing would leave the project's status
surface transiently inconsistent — e.g. CLAUDE.md saying "AR.4
complete" while `audit_remediation_plan.md` still says
"deferred").  The single-PR composition is recorded in §5 as PR-8.

#### EI.8.a — `ExtendedState.extEq` definition

**Scope.**  `LegalKernel/FaultProof/Commit.lean` (the
composition's natural home — sits alongside the existing
bytes-eq theorem).

**Math.**  Corrected to the actual `ExtendedState` field names
(`base`, `nonces`, `registry`, `bridge`, `localPolicies`):

```lean
def ExtendedState.extEq (es₁ es₂ : ExtendedState) : Prop :=
  es₁.base.balances.Equiv es₂.base.balances ∧
  (∀ r bm₁ bm₂,
     es₁.base.balances[r]? = some bm₁ →
     es₂.base.balances[r]? = some bm₂ →
     bm₁.Equiv bm₂) ∧
  es₁.nonces.next.Equiv es₂.nonces.next ∧
  es₁.registry.Equiv es₂.registry ∧
  es₁.localPolicies.Equiv es₂.localPolicies ∧
  es₁.bridge.consumed.Equiv es₂.bridge.consumed ∧
  es₁.bridge.pending.Equiv es₂.bridge.pending ∧
  es₁.bridge.nextWdId = es₂.bridge.nextWdId
```

**Note on decidability.**  `ExtendedState.extEq` quantifies over
unbounded key sets (e.g. all `ActorId`s).  It is **not** decidable
in general; we do not need it to be — `extEq` is a propositional
relation used in proof goals, not in executable predicates.  No
`Decidable` instance is required.

Reviewers should confirm no consumer of `extEq` requires
`Decidable` (e.g. via `decide` tactic in some downstream proof).
If a consumer does, that consumer's proof needs an `extEq → Eq`
lift or a finite-range variant; flag in this sub-unit's review.

**Implementation steps.**

  1. Add `ExtendedState.extEq` to `FaultProof/Commit.lean`
     between the existing bytes-eq theorem and the
     `#print axioms` smoke check at the bottom of the file.
  2. Add a multi-line docstring naming the per-sub-state
     conjuncts and citing EI.2 – EI.7 as their providers.
  3. No `Decidable` instance.

**Acceptance criteria.**

  * Definition lands.
  * `lake build` succeeds.

**Reviewer checklist.**

  * Field names match the actual `ExtendedState` struct (audit
    against `Authority/Nonce.lean:98-141`).
  * The nested `balances` quantifier is correctly structured (per-
    `r` pair-existence check + inner `Equiv`).

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day.

#### EI.8.b — Composition theorem

**Math.**

```lean
theorem commitExtendedState_subcommits_extensional_eq_under_collision_free
    (es₁ es₂ : ExtendedState) (h_cf : Bridge.CollisionFree hashBytes)
    (h_eq : commitExtendedState es₁ = commitExtendedState es₂) :
    ExtendedState.extEq es₁ es₂
```

**Proof structure.**

  1. From `h_eq` and `h_cf`, apply the existing
     `commitExtendedState_subcommits_bytes_eq_under_collision_free`
     (`FaultProof/Commit.lean:392`) to get five sub-state
     byte-equalities:
       * `State.encode es₁.base = State.encode es₂.base`
       * `NonceState.encode es₁.nonces = NonceState.encode es₂.nonces`
       * `KeyRegistry.encodeMap es₁.registry = KeyRegistry.encodeMap es₂.registry`
       * `Encodable.encode es₁.localPolicies = Encodable.encode es₂.localPolicies`
       * `Encodable.encode es₁.bridge = Encodable.encode es₂.bridge`
  2. Strip the `ByteArray.mk … .toArray` wrappers (these are
     definitionally equal to the underlying `Stream` equalities;
     a small `congr_arg`-style lemma may be needed).
  3. Apply EI.2.d to the first byte-equality to get the nested
     `State` extensional equality (outer `Equiv` + per-resource
     inner `Equiv`).
  4. Apply EI.3.a / EI.4.a / EI.5.d to the next three.
  5. Apply EI.7.e to the bridge byte-equality to get the
     three-way conjunction (consumed / pending / nextWdId).
  6. Conjoin into `ExtendedState.extEq`.

**Implementation steps.**

  1. State the theorem alongside the existing bytes-eq lemma.
  2. Prove via the structure above; each step is one or two
     Lean lines (`have hX := EI.k.lemma h_byte_X` + `exact
     ⟨h1, …⟩`).
  3. Add an `#print axioms` smoke check at the bottom of the
     file (so the theorem's axiom set is visible at glance).

**Acceptance criteria.**

  * Theorem ships.
  * `#print axioms commitExtendedState_subcommits_extensional_eq_under_collision_free`
    ⊆ `[propext, Classical.choice, Quot.sound]`.
  * `lake build` and `lake test` green.

**Reviewer checklist.**

  * Each EI.k lemma is named explicitly in the proof body (not
    invoked via `simp`-magic; reviewers must see the composition).
  * The bytes-eq theorem is preserved alongside (not replaced).

**Risk.**  Low.  Pure composition; the per-component sub-units
do the actual mathematical work.

**Effort.**  ~0.5 engineer-day.

#### EI.8.c — AR.23.3 snapshot-bootstrap test lift

**Scope.**  `LegalKernel/Test/Integration/SnapshotBootstrap.lean`.

**Edit.**  Currently the `finalStateEqualsGenesis` test
(`SnapshotBootstrap.lean:120-149`) checks state-hash equality
(`hashEncodable rs1.state = hashEncodable rs2.state`); the
docstring at lines 116-119 notes that "a full final-state-equality
regression for non-empty logs requires the AR.4.8
extensional-equality lemma (deferred)".

EI.8.c lifts the test by:

  1. Strengthening the assertion: in the post-EI environment,
     replace the byte-hash check with an `ExtendedState.extEq`
     assertion via the new composition theorem.
  2. Removing the "deferred" comment at lines 116-119.
  3. (Optional) adding a non-empty-log variant of the test that
     exercises the new lemma's full power.

**Implementation steps.**

  1. Edit the test body to use `ExtendedState.extEq` (decidable
     within the test fixture's bounded domain via per-actor /
     per-resource enumeration; or, drop down to per-component
     `Equiv` checks that ARE decidable given the test fixture's
     finite content).
  2. Remove the deferred comment.
  3. Mark `audit_remediation_plan.md` §15C.2 AR.23 row as
     "Complete" (this lands in EI.8.f).

**Acceptance criteria.**

  * Test passes with the stronger assertion.
  * No remaining "AR.4.8 (deferred)" mention in the test file.

**Reviewer checklist.**

  * The new assertion is `ExtendedState.extEq`-shaped, not a
    weaker variant.
  * Comment scrub: no remaining "AR.4.8 (deferred)" mention.

**Risk.**  Trivial.

**Effort.**  ~0.3 engineer-day.

#### EI.8.d — CLAUDE.md cross-document retirement

**Scope.**  CLAUDE.md.

**Edits required.**

  1. Remove footnote 1 entirely (lines reference
     "commitExtendedState_subcommits_bytes_eq_under_collision_free"
     and the "9–16-day proof track" caveat).
  2. Update the "Headline theorems" table row currently citing
     `commitExtendedState_subcommits_bytes_eq_under_collision_free`:
     recommend (a) replace the row with the extensional-eq theorem
     (the bytes-eq lemma stays in source as a primitive but the
     headline is the extensional form), or (b) list both rows.
     Per the project's "Headline theorems" discipline (most
     consumer-visible form is the headline), prefer (a).
  3. In the "Deferred from AR" section (currently at lines
     ~805-811 of CLAUDE.md), retire AR.4 — replace the
     "AR.4 (encoder injectivity quartet for the five
     map-backed sub-states) is a 9–16 working-day proof track…"
     paragraph with a one-line "AR.4: Complete; landed under
     Workstream EI (see
     `docs/planning/encoder_injectivity_plan.md`)".
  4. In the "Current development status" section, bump the
     status entry for "Active development history" if needed.
     The build-tag bump (EI.8.i) lands separately.

**Implementation steps.**

  1. Read the current footnote 1 and "Deferred from AR" section
     to anchor edit positions exactly.
  2. Edit one logical change per Edit tool call per
     `CLAUDE.md`'s own guidance.
  3. Run `grep -n "footnote 1\|AR\.4 (encoder injectivity)" CLAUDE.md`
     to confirm zero residual references.

**Acceptance criteria.**

  * `grep -n "footnote 1" CLAUDE.md` returns zero hits.
  * Headline-theorems table updated.
  * "Deferred from AR" section updated.

**Reviewer checklist.**

  * Headline-theorem row is real (the new theorem name spelled
    correctly).
  * No orphan footnote anchor (`¹` superscript) remaining.

**Risk.**  Low-medium.  Documentation drift; the grep sweep in
EI.8.j is the safety net.

**Effort.**  ~0.3 engineer-day.

#### EI.8.e — GENESIS_PLAN.md cross-document retirement

**Scope.**  `docs/GENESIS_PLAN.md`.

**Edits required.**

  1. §15B.1: cite the new extensional-eq theorem alongside the
     bytes-eq lemma.  The §15B.1 statement currently describes
     the state-commitment scheme and its bytes-eq guarantee;
     append a one-paragraph note pointing to the new
     `commitExtendedState_subcommits_extensional_eq_under_collision_free`.
  2. §15C.7 ("Encoder injectivity (deferred)"): replace the
     section body with "Complete; landed under Workstream EI".
     Keep the §15C.7 anchor for cross-references but update the
     subsection title to "Encoder injectivity (complete)".

**Implementation steps.**

  1. Use Read with offset+limit to fetch the §15B.1 region
     before editing (file is ~4200 lines).
  2. Single Edit per logical change.

**Acceptance criteria.**

  * §15B.1 cites the new theorem.
  * §15C.7 marked complete; section title updated.

**Reviewer checklist.**

  * The Genesis Plan's §15B.1 description still reads coherently
    after the addition (not a tacked-on paragraph).
  * §15C.7's content matches the new state (no leftover
    "deferred" language).

**Risk.**  Medium.  Genesis Plan edits are high-traffic and
high-visibility; carelessness leaves stale claims in the
canonical design document.

**Effort.**  ~0.3 engineer-day.

#### EI.8.f — `audit_remediation_plan.md` update

**Scope.**  `docs/planning/audit_remediation_plan.md`.

**Edits required.**

  1. §15C.2 status table: AR.4 row from "Deferred" → "Complete".
  2. §15C.2 status table: AR.23 row from "Partial" → "Complete"
     (the snapshot-bootstrap lift in EI.8.c closes the AR.23
     residue).
  3. §15C.7 mirror: section heading from "(deferred)" to
     "(complete)".
  4. §4.4 body: append a brief "Complete (see
     `docs/planning/encoder_injectivity_plan.md` §4)" note.

**Implementation steps.**

  1. Locate the status table (`grep -n "^| AR\.4 \||" docs/planning/audit_remediation_plan.md`).
  2. Single Edit per status update.

**Acceptance criteria.**

  * AR.4 / AR.23 / §15C.7 all show "Complete".

**Risk.**  Low.

**Effort.**  ~0.2 engineer-day.

#### EI.8.g — `encoder_injectivity_plan.md` self-update

**Scope.**  This file.

**Edits required.**

  1. Status section: move workstream from "in progress" to
     "complete" (when EI.8 lands).
  2. Annotate every sub-unit (EI.0 – EI.7) as "Complete" in
     its per-sub-unit section.
  3. Add a final "Landing summary" at the bottom of §4 with the
     actual landing dates / PR numbers.

**Implementation steps.**

  1. Single Edit per sub-unit section update.
  2. Add the landing summary as a new sub-section at the end of
     §4.

**Acceptance criteria.**

  * Every sub-unit section ends with "Status: Complete".
  * Landing summary present.

**Risk.**  Trivial.

**Effort.**  ~0.2 engineer-day.

#### EI.8.h — AGENTS.md parity sweep

**Scope.**  `AGENTS.md`.

**Activity.**  `AGENTS.md` must remain byte-identical to
`CLAUDE.md` per CLAUDE.md's "Documentation rules".  After
EI.8.d's CLAUDE.md edits, propagate them to `AGENTS.md`.

**Implementation steps.**

  1. `diff CLAUDE.md AGENTS.md` to confirm pre-EI parity.
  2. After EI.8.d lands, `cp CLAUDE.md AGENTS.md` (or apply
     identical edits) to restore parity.
  3. Verify with a second `diff`.

**Acceptance criteria.**

  * `diff CLAUDE.md AGENTS.md` returns empty.

**Reviewer checklist.**

  * `diff` actually clean.

**Risk.**  Trivial.

**Effort.**  ~0.1 engineer-day.

#### EI.8.i — `kernelBuildTag` bump + Test/Umbrella pin

**Scope.**  `LegalKernel.lean`, `LegalKernel/Test/Umbrella.lean`.

**Edit.**  Bump `kernelBuildTag` (currently
`"canon-audit-remediation"`) to `"canon-encoder-injectivity"`
(or whatever naming convention the maintainers prefer; see
OQ-DOC-1 in `open_questions.md` for the cadence rule).  Update
the regression test in `Test/Umbrella.lean` to pin the new
value.

**Implementation steps.**

  1. Edit the constant in `LegalKernel.lean`.
  2. Edit the pinned value in `Test/Umbrella.lean`.
  3. Run `lake test` to confirm the regression test passes
     against the new value.

**Acceptance criteria.**

  * Constant and test value match.
  * `lake test` passes.
  * README's build-tag (per CL.1) updates in the same PR or in
    an immediately-following CL.1 PR.

**Reviewer checklist.**

  * The two edits land in the same PR (atomic).

**Risk.**  Trivial.

**Effort.**  ~0.1 engineer-day.

#### EI.8.j — Cross-reference grep + scrub

**Scope.**  Workstream-wide.

**Activity.**  Final grep sweep to catch any cross-reference EI.8
missed.

**Implementation steps.**

  1. Run the following greps from the repository root:

     ```bash
     grep -rn 'footnote 1' CLAUDE.md AGENTS.md docs/ solidity/README.md README.md
     grep -rn 'AR\.4 follow-up\|AR\.4 (encoder' CLAUDE.md AGENTS.md docs/
     grep -rn 'encoder injectivity (deferred)\|encoder_injectivity (deferred)' CLAUDE.md AGENTS.md docs/
     grep -rn '9.16 working-day\|9–16 working-day\|9-16 working-day' CLAUDE.md AGENTS.md docs/
     grep -rn 'AR\.4\.8 (deferred)\|AR\.4\.8 extensional-equality lemma (deferred)' LegalKernel/ docs/
     ```

  2. Every hit must be either (a) intentional historical reference
     (e.g. in a `git log`-flavoured passage), or (b) updated in a
     follow-up Edit before EI.8.j lands.

**Acceptance criteria.**

  * All five greps return only intentional historical references
    (auditable in the PR's commit messages).

**Reviewer checklist.**

  * The "intentional historical reference" justification is
    explicit in the PR description.

**Risk.**  Medium.  Stragglers are easy to miss; the grep sweep
is the principal mitigation.

**Effort.**  ~0.2 engineer-day.

---

### EI.8 — Rolled-up acceptance criteria

  * EI.8.a – EI.8.j all land in a single coordinated PR (PR-8 in
    §5).
  * **Single-PR rationale:** cross-document edits + build-tag bump
    + test lift form an atomic state change.  Interleaved partial
    landing would leave the project status surface transiently
    inconsistent (e.g. CLAUDE.md says "AR.4 complete" but
    `audit_remediation_plan.md` still says "deferred"; or the
    extensional-eq theorem ships but the test still uses the
    weaker hash-eq assertion).
  * **Aggregate effort:** ~2.4 engineer-days.

**Migration notes.**  The bytes-eq lemma stays in source as a
load-bearing primitive (other call sites consume it directly,
e.g. the per-sub-state `commitState_bytes_injective_*` family in
`FaultProof/Commit.lean`).  EI.8 *adds* the extensional variant;
no breaking change.

## §5 Sequencing and PR structure

### §5.1 PR landing matrix

The 41 sub-sub-units land as 14–17 PRs (some sub-units bundle
cleanly; the lower bound assumes all conditional sub-units are
no-ops).

```
PR-0   ─ EI.0          ─ Pre-flight discovery + scaffolding         (1 reviewer)
PR-1   ─ EI.1.b + EI.1.d ─ Polymorphic helpers                       (1 reviewer)
PR-2   ─ EI.1.c        ─ cborHeadEncode_injective                    (1 reviewer)
PR-3   ─ EI.1.e        ─ encodeSortedPairs_injective                 (1 reviewer)
PR-4   ─ EI.1.f + EI.1.g ─ UIntN + project wrapper injectivity sweep (1 reviewer)
PR-5   ─ EI.1.h + EI.1.i ─ List/Option + HasInjective class          (1 reviewer)
PR-5a  ─ EI.1.a        ─ RBMapLemmas auxiliary (conditional;
                            **2 reviewers** if shipped)
PR-6   ─ EI.2          ─ State.encode_injective (template)           (1 reviewer)
PR-7   ─ EI.3          ─ NonceState.encode_injective                  \
PR-8   ─ EI.4          ─ KeyRegistry.encodeMap_injective                \
PR-9   ─ EI.5          ─ LocalPolicies.encodeMap_injective              ─ parallel landing
PR-10  ─ EI.6          ─ BridgeState.encodeConsumed_injective         /
PR-11  ─ EI.7          ─ BridgeState.encodePending_injective +       /
                          BridgeState.encode_injective              /
PR-12  ─ EI.8          ─ Composition + footnote-1 retirement +
                          build-tag bump (single atomic PR)          (1 reviewer)
```

Each PR title prefix: `EI.<n>[.<letter>]: <one-line summary>`.
PR body must include `#print axioms <new theorem>` output as a
sanity check.

### §5.2 PR bundling rationale

  * **PR-1 (EI.1.b + EI.1.d).**  Both are polymorphic helpers in
    the same `Encoding/Encodable.lean` file; landing together
    avoids a review-context swap.
  * **PR-4 (EI.1.f + EI.1.g).**  All four UIntN injectivity lemmas
    plus all seven project-wrapper injectivity lemmas are
    one-liners using EI.1.b; they land cleanly as a single sweep.
  * **PR-5 (EI.1.h + EI.1.i).**  `List`/`Option` injectivity plus
    the `HasInjective` class are conceptually adjacent (the class
    typeclass-routes the parameterised hypothesis).
  * **PR-7 – PR-11 (parallel).**  Five PRs may land in any order
    after PR-6 (EI.2) ships, by separate contributors on disjoint
    files (one `Encoding/<Sub>Injective.lean` per).
  * **PR-12 (EI.8 atomic).**  Single atomic PR for the
    cross-document scrub + composition theorem + test lift +
    build-tag bump.  Interleaved landing would leave the project
    status surface transiently inconsistent.

### §5.3 Branch naming

Per the project's `claude/<topic>-<slug>` convention:

  * PR-0:  `claude/encoder-injectivity-preflight`
  * PR-1:  `claude/encoder-injectivity-polymorphic-helpers`
  * PR-2:  `claude/encoder-injectivity-cbor-head`
  * PR-3:  `claude/encoder-injectivity-sorted-pairs`
  * PR-4:  `claude/encoder-injectivity-atomic-carriers`
  * PR-5:  `claude/encoder-injectivity-list-option`
  * PR-5a: `claude/encoder-injectivity-rbmap-aux`     (if shipped)
  * PR-6:  `claude/encoder-injectivity-state-template`
  * PR-7:  `claude/encoder-injectivity-nonce`
  * PR-8:  `claude/encoder-injectivity-keyregistry`
  * PR-9:  `claude/encoder-injectivity-localpolicies`
  * PR-10: `claude/encoder-injectivity-bridge-consumed`
  * PR-11: `claude/encoder-injectivity-bridge-pending`
  * PR-12: `claude/encoder-injectivity-composition`

### §5.4 PR description template

Each PR body must include the following sections (verbatim
template, outer fenced with `~~~` to avoid nested-fence
ambiguity):

~~~
## Summary
<one-paragraph what + why>

## Sub-sub-units shipped
- EI.<n>.<letter>: <name>
- …

## Theorems shipped
- <theorem name> (`<file>:<line>`)
- …

## Axiom audit

```
$ lake env lean -e '#print axioms <theorem-name>'
<axiom list — should be ⊆ {propext, Classical.choice, Quot.sound}>
```

## Build posture
- lake build: green
- lake test: green; test count <before> → <after>
- count_sorries: 0
- tcb_audit: green
- (other audits as relevant)

## Reviewer notes
- <anything reviewers should pay attention to>
~~~

The trailing session-permalink CLAUDE.md prohibits (see CLAUDE.md
"Pull request authoring policy") must NOT appear in the PR body.

## §6 Quality gates, rollback, roll-forward

### §6.1 Per-PR forcing functions

Every PR must pass on CI:

  * `lake build` (full project)
  * `lake test`
  * `lake exe count_sorries`        (zero new sorries)
  * `lake exe tcb_audit`            (no new TCB imports)
  * `lake exe stub_audit`           (no new stubs)
  * `lake exe naming_audit`         (no forbidden tokens)
  * `lake exe deferral_audit`       (no new deferrals)
  * `lake exe lex_lint`             (no registry violations)
  * `lake exe lex_codegen --check`  (no codegen drift)
  * `lake exe mock_import_audit`    (no production → test imports)

### §6.2 Two-reviewer gate

EI.1.a (if it lands; touches `RBMapLemmas.lean`) triggers the
§13.6 two-reviewer rule.  No other sub-unit triggers it because
all other EI proofs live in non-TCB modules.

If the EI.0.a Std audit determines EI.1.a is unnecessary, the
two-reviewer gate is avoided entirely.

### §6.3 Rollback

Each PR is a single git commit (or a small commit chain).
Rollback is `git revert <sha>`.  Theorems are additive; reverting
affects only downstream PRs (e.g. reverting PR-6 forces revert
of PR-7 – PR-12 that consume EI.2.d).

The dependency graph in §3.4 is the source of truth for which
downstream PRs must follow a given revert.

### §6.4 Roll-forward

If a sub-unit lands with a defective proof (audit catches it),
the fix lands in a new PR titled `EI.<n>.<letter>.fix:
<description>` that supersedes the defective theorem.  Do not
amend; preserve git history per CLAUDE.md policy.

### §6.5 Mid-workstream pause

If EI work pauses mid-way (e.g. resource reallocation), the
project's status surface remains consistent because:

  * Each PR is self-contained (passes all audits independently).
  * No status-claim changes happen until EI.8 lands (the
    documentation update is the last sub-unit).
  * The deferred-AR-4 narrative in CLAUDE.md footnote 1 stays
    accurate until EI.8.

Resuming after a pause: re-read this plan, audit the
already-landed PRs against §3.4's dependency graph, and continue
from the first un-landed sub-unit.

## §7 Risk register

| ID | Risk | Likelihood | Impact | Mitigation |
|----|------|-----------|--------|------------|
| EI-R1 | `Std.TreeMap.equiv_iff_toList_eq` or the per-direction `getElem?_eq_of_Equiv` family changes between Lean toolchain versions | Low | Medium | EI.0.a baselines the audit against the *pinned* toolchain; toolchain bumps require re-running EI.0.a |
| EI-R2 | EI.2's nested-map proof surfaces an obstacle (e.g. byte-size bound for `BalanceMap.encodeAsBytes` is harder to discharge than expected) | Medium | High | EI.2 lands first specifically to surface this; the EI.2.f retrospective revises EI.3 – EI.7 plan if needed before parallel work starts |
| EI-R3 | `EthAddress.toBytes_injective` is missing and harder to derive than expected | Low | Medium | EI.7.a sub-sub-unit isolates this; audit during implementation; fall back to a minimal `EthAddress.ofBytes_toBytes` round-trip if needed |
| EI-R4 | `pendingWithdrawal_roundtrip` is missing (the plan assumes it ships; audit confirms `depositRecord_roundtrip` exists at `Encoding/State.lean:576` but didn't confirm a Pending companion) | Medium | Medium | EI.7.b sub-sub-unit's audit step; ship `roundtrip` as a precursor in the same PR if absent |
| EI-R5 | `LocalPolicyClause.encode_injective` (EI.5.a) requires more constructor-tag-discipline work than expected (e.g. the encoder doesn't follow the standard tag-byte pattern) | Medium | Medium | Audit `Encoding/LocalPolicy.lean`'s `LocalPolicyClause` encoder body during EI.5.a planning; ship a small inductive-decoder-discipline auxiliary if needed |
| EI-R6 | `encodeSortedPairs_injective` (EI.1.e) needs both fixed-width and self-delimiting variants; one of them is harder to prove than expected | Medium | High | EI.1.e is the critical path's load-bearing lemma; allow up to 1.5 days of buffer; fall back to `decodeMap`-based formulation (which uses Std's already-shipped `decodeMap_isOk_iff` family) if the direct induction proves intractable |
| EI-R7 | EI.2.c / EI.5.c / EI.6.b / EI.7.c (framing-injectivity lemmas) need access to the `private` `encodeAsBytes` definitions | Low | Low | Ship the framing-injectivity lemmas inside `Encoding/State.lean` and `Encoding/LocalPolicy.lean` (where the `private` definitions are visible), re-exported via `*Injective.lean` |
| EI-R8 | Footnote-1 retirement misses one cross-reference (CLAUDE.md, AGENTS.md, README.md, GENESIS_PLAN.md, audit_remediation_plan.md, fault_proof_design.md, audits/05-encoding.md, audits/09-fault-proof.md, audits/19-findings-and-followups.md, solidity/README.md) | High | Low | EI.8.j's grep sweep explicitly enumerates each file; grep for the footnote text at landing |
| EI-R9 | `deferral_audit` regression after footnote-1 removal (the audit doesn't currently scan CLAUDE.md but the project may extend it) | Low | Low | Run `deferral_audit` in PR-12's CI; the binary's scope is `LegalKernel/`, `Lex/`, `Tools/` per source, not `docs/` — confirmed via audit |
| EI-R10 | `ExtendedState.extEq` (EI.8.a) shape doesn't match what downstream consumers expect | Low | Medium | The current shape is derived from the existing `commitExtendedState_subcommits_bytes_eq_under_collision_free` byte-equality structure; reviewers confirm shape matches the test in `Test/Integration/SnapshotBootstrap.lean` |
| EI-R11 | `kernelBuildTag` bump conflict with a parallel workstream landing a different tag bump | Low | Low | EI.8.i lands last; coordinate with any other in-flight tag-bumping PR (none currently planned in `deferred_work_index.md`) |
| EI-R12 | `BridgeState.encode_injective` (EI.7.e) cannot decompose the three-segment concatenation because the segments aren't actually self-delimiting in the byte stream | Low | High | Ship the decomposition via `Encodable_via_decode_inj` (EI.1.b) routed through `bridgeState_roundtrip`; if `bridgeState_roundtrip` is missing, ship it first |
| EI-R13 | Test count growth from `Test/Encoding/Injectivity.lean` slows `lake test` measurably | Low | Low | The new tests are pure-Lean term-level (no IO besides the test driver scaffold); per-test runtime is microsecond-scale; total growth bounded by ~50 new tests |
| EI-R14 | The `HasInjective` typeclass (EI.1.i) creates instance-search slowdowns | Low | Low | Marked `Prop`-valued; if measurable, strike EI.1.i and reformulate per-sub-state proofs with explicit hypotheses |
| EI-R15 | Reviewers ask for `Eq`-shaped (not `Equiv`-shaped) conclusions, requiring re-derivation | Low | High | The plan's Goal-1 rationale is explicit; the EI.2.f retrospective documents reviewer feedback before EI.3 – EI.7 start |

## §8 Acceptance criteria for the workstream

EI is **complete** when:

  1. Six `*_encode_injective` lemmas ship (one per map-backed
     sub-state), each concluding `*.Equiv`:
       * `State.encode_injective`            (nested; outer
         `balances` + per-resource inner `BalanceMap`)
       * `NonceState.encode_injective`
       * `KeyRegistry.encodeMap_injective`
       * `LocalPolicies.encodeMap_injective`
       * `Bridge.BridgeState.encodeConsumed_injective`
       * `Bridge.BridgeState.encodePending_injective`
  2. Auxiliary `Bridge.BridgeState.encode_injective` ships
     (concatenation-shape; consumed `Equiv` + pending `Equiv` +
     `nextWdId` `Eq`).
  3. `commitExtendedState_subcommits_extensional_eq_under_collision_free`
     ships in `FaultProof/Commit.lean`.
  4. CLAUDE.md footnote 1 is removed; the headline-theorems
     table cites the new composition theorem.
  5. AGENTS.md is byte-identical to CLAUDE.md.
  6. GENESIS_PLAN.md §15B.1 cites the new theorem; §15C.7 is
     updated to "Complete".
  7. `audit_remediation_plan.md` §15C.2 status table moves
     AR.4 from "Deferred" to "Complete" and AR.23 from
     "Partial" to "Complete".
  8. `lake exe count_sorries`, `lake exe tcb_audit`,
     `lake exe deferral_audit`, `lake exe naming_audit`,
     `lake exe stub_audit`, `lake exe lex_lint`,
     `lake exe lex_codegen --check`, and
     `lake exe mock_import_audit` all pass.
  9. `#print axioms` on each new theorem prints a subset of
     `[propext, Classical.choice, Quot.sound]` (Appendix B's
     verification script automates this).
  10. Every new theorem has a term-level API-stability test in
      `LegalKernel/Test/Encoding/Injectivity.lean` (or a sibling
      test module per the EI.0.b module-placement decision).
  11. The `kernelBuildTag` in `LegalKernel.lean` bumps to a new
      value reflecting EI landing; `Test/Umbrella.lean` is
      updated in the same PR.
  12. EI.8.j's grep sweep returns zero stale references.
  13. `Test/Integration/SnapshotBootstrap.lean`'s
      `finalStateEqualsGenesis` test uses the new composition
      theorem (or an `ExtendedState.extEq` assertion derived from
      it).
  14. Total test count grows monotonically (no regressions; new
      total ≥ ~1957, baseline + ~50).

## §9 Out-of-scope items

  1. **Structural map equality** (`m₁ = m₂` as Lean `Eq`).  Strictly
     stronger than `Equiv`; unnecessary for any current or planned
     consumer.  Future work if a consumer ever requires it.
  2. **`Std.TreeMap` lemma library fork.**  EI uses Std as-is; the
     conditional EI.1.a covers any single missing lemma but is not
     a fork.
  3. **Cross-format encoder injectivity** (e.g. proving a deployment
     that swaps CBE for protobuf has the same injectivity
     property).  EI is about the canonical CBE encoder; alternative
     encoders would need their own injectivity proofs.
  4. **`@[extern]` adaptor swap-out injectivity.**  Production
     deployments may swap `hashBytes` via `@[extern]`.  The
     composition theorem is conditioned on `Bridge.CollisionFree
     hashBytes` (a hypothesis, not a fact); deployments that swap
     a non-collision-free hash break the conclusion, by design.
  5. **Rust off-chain observer side updates.**  Workstream H's
     deferred Rust observer (WUs 5.4 / 5.7 / 5.8 / 5.11) may
     eventually consume the extensional-eq theorem; that's a
     separate landing.
  6. **Solidity-mirror updates.**  The Solidity L1 verifier
     consumes byte-level commits, not extensional state; no
     Solidity changes required.
  7. **Encoder-function renaming for uniformity** (`*.encode` vs
     `*.encodeMap`).  Pre-existing inconsistency; renaming is a
     wide-blast-radius diff and is out of scope.

## §10 References

  * `docs/planning/audit_remediation_plan.md` §4.4 (original AR.4
    spec) and §15C.7 (deferral note).
  * `docs/GENESIS_PLAN.md` §15B.1 (state-commitment scheme),
    §15C.7 (encoder injectivity deferral).
  * `CLAUDE.md` footnote 1 (the gap being closed).
  * `LegalKernel/FaultProof/Commit.lean` — the existing bytes-eq
    theorem `commitExtendedState_subcommits_bytes_eq_under_collision_free`
    (line 392).
  * `LegalKernel/FaultProof/EncodeInjectivity.lean` — the
    pre-existing encoder-determinism + distinguish-inputs lemmas
    for `KernelStep` and `GameState` (the EI workstream's encoder
    side complements this).
  * `LegalKernel/Encoding/Encodable.lean` — the existing
    `Encodable` class and per-carrier round-trip lemmas (lines
    152, 202, 265, 350) and injectivity lemmas (lines 178, 215,
    280, 380).
  * `LegalKernel/Encoding/CBOR.lean` — CBE primitive infrastructure
    (`cborHeadEncode` line 244, `cborHeadDecode` line 257,
    `cborHeadRoundtrip` line 298).
  * `LegalKernel/Encoding/State.lean` — `encodeSortedPairs` line
    107, `decodeMap` line 164, sub-state encoders lines 197–455.
  * `LegalKernel/Encoding/LocalPolicy.lean` —
    `LocalPolicies.encodeMap` line 482.
  * `LegalKernel/Authority/LocalPolicy.lean` —
    `LocalPolicyClause` inductive (lines 122–141),
    `LocalPolicy` struct (lines 151–154).
  * `LegalKernel/Authority/Nonce.lean` — `NonceState` (lines
    68–75) and `ExtendedState` (lines 98–141) struct definitions.
  * `LegalKernel/Bridge/State.lean` — `DepositId`/`WithdrawalId`
    abbrevs (lines 127, 132), `DepositRecord` (lines 145–150),
    `PendingWithdrawal` (lines 155–167), `BridgeState` (lines
    180–188) struct definitions.
  * `LegalKernel/RBMapLemmas.lean` — the TCB-tier RB-map lemma
    library (touched only by EI.1.a if `equiv_iff_toList_eq` is
    missing from the pinned Std core; audit during EI.0.a).
  * `docs/std_dependencies.md` — Std-library lemma audit;
    extended by EI.0.a.
  * `docs/planning/deferred_work_index.md` — the master deferred-
    work index; EI's entries removed by EI.8.g (this plan's
    self-update sub-unit).

## Appendix A — Theorem-to-test cross-reference matrix

| Theorem                                       | EI sub-unit | Test file                              | Test pattern (term-level)                  |
|-----------------------------------------------|-------------|----------------------------------------|--------------------------------------------|
| `Encodable_via_decode_inj`                    | EI.1.b      | `Test/Encoding/Injectivity.lean`        | `let _ : <…> := Encodable_via_decode_inj` |
| `cborHeadEncode_injective`                    | EI.1.c      | `Test/Encoding/Injectivity.lean`        | term-level + 3 fixture-pair assertions     |
| `encodeAsBytes_eq_injective_of_…`             | EI.1.d (eq) | `Test/Encoding/Injectivity.lean`        | term-level + structural-eq fixture         |
| `encodeAsBytes_equiv_injective_of_…`          | EI.1.d (Eq.) | `Test/Encoding/Injectivity.lean`       | term-level + `Equiv` fixture               |
| `encodeSortedPairs_injective`                 | EI.1.e      | `Test/Encoding/Injectivity.lean`        | term-level + per-arity fixture             |
| `uIntN_encode_injective` (×4)                 | EI.1.f      | `Test/Encoding/Injectivity.lean`        | term-level × 4                             |
| `actorId_encode_injective` etc. (×7)          | EI.1.g      | `Test/Encoding/Injectivity.lean`        | term-level × 7                             |
| `list_encode_injective` / `option_encode_injective` | EI.1.h | `Test/Encoding/Injectivity.lean`        | term-level + 3 list fixtures               |
| `Encodable.HasInjective` instances            | EI.1.i      | `Test/Encoding/Injectivity.lean`        | typeclass-search smoke                     |
| `BalanceMap.encode_injective`                 | EI.2.a      | `Test/Encoding/Injectivity.lean`        | term-level + 3 fixture pairs                |
| `BalanceMap.encodeAsBytes_injective`          | EI.2.c      | `Test/Encoding/Injectivity.lean`        | term-level                                  |
| `State.encode_injective`                      | EI.2.d      | `Test/Encoding/Injectivity.lean`        | term-level + 3 fixture pairs                |
| `NonceState.encode_injective`                 | EI.3.a      | `Test/Encoding/Injectivity.lean`        | term-level + 3 fixture pairs                |
| `KeyRegistry.encodeMap_injective`             | EI.4.a      | `Test/Encoding/Injectivity.lean`        | term-level + 3 fixture pairs                |
| `LocalPolicyClause.encode_injective`          | EI.5.a      | `Test/Encoding/Injectivity.lean`        | term-level + 3 clause fixtures              |
| `LocalPolicy.encode_injective`                | EI.5.b      | `Test/Encoding/Injectivity.lean`        | term-level + 3 policy fixtures              |
| `LocalPolicies.encodeMap_injective`           | EI.5.d      | `Test/Encoding/Injectivity.lean`        | term-level + 3 map fixtures                 |
| `Bridge.DepositRecord.encode_injective`       | EI.6.a      | `Test/Encoding/Injectivity.lean`        | term-level + 3 record fixtures              |
| `Bridge.BridgeState.encodeConsumed_injective` | EI.6.c      | `Test/Encoding/Injectivity.lean`        | term-level + 3 fixture pairs                |
| `Bridge.EthAddress.toBytes_injective`         | EI.7.a      | `Test/Encoding/Injectivity.lean`        | term-level + 3 address fixtures (if shipped) |
| `Bridge.PendingWithdrawal.encode_injective`   | EI.7.b      | `Test/Encoding/Injectivity.lean`        | term-level + 3 record fixtures              |
| `Bridge.BridgeState.encodePending_injective`  | EI.7.d      | `Test/Encoding/Injectivity.lean`        | term-level + 3 fixture pairs                |
| `Bridge.BridgeState.encode_injective`         | EI.7.e      | `Test/Encoding/Injectivity.lean`        | term-level + 3 fixture pairs                |
| `commitExtendedState_subcommits_extensional_eq_under_collision_free` | EI.8.b | `Test/Integration/SnapshotBootstrap.lean` | term-level + AR.23.3 lift assertion |

## Appendix B — `#print axioms` verification script

After all EI PRs land, the following script verifies that every
new theorem depends only on the canonical three Lean built-ins:

```bash
#!/usr/bin/env bash
# scripts/audit-ei-axioms.sh — verifies EI theorems' axiom dependency.
# Pre-EI.8.b, the composition theorem name doesn't exist; the script's
# last grep will fail until EI.8 lands.
set -euo pipefail

THEOREMS=(
  "Encoding.Encodable_via_decode_inj"
  "Encoding.cborHeadEncode_injective"
  "Encoding.encodeAsBytes_eq_injective_of_encode_eq_injective"
  "Encoding.encodeAsBytes_equiv_injective_of_encode_equiv_injective"
  "Encoding.encodeSortedPairs_injective"
  "Encoding.uInt8_encode_injective"
  "Encoding.uInt16_encode_injective"
  "Encoding.uInt32_encode_injective"
  "Encoding.uInt64_encode_injective"
  "Encoding.actorId_encode_injective"
  "Encoding.amount_encode_injective"
  "Encoding.nonce_encode_injective"
  "Encoding.resourceId_encode_injective"
  "Encoding.publicKey_encode_injective"
  "Encoding.depositId_encode_injective"
  "Encoding.withdrawalId_encode_injective"
  "Encoding.list_encode_injective"
  "Encoding.option_encode_injective"
  "BalanceMap.encode_injective"
  "BalanceMap.encodeAsBytes_injective"
  "State.encode_injective"
  "NonceState.encode_injective"
  "KeyRegistry.encodeMap_injective"
  "LocalPolicyClause.encode_injective"
  "LocalPolicy.encode_injective"
  "LocalPolicies.encodeMap_injective"
  "Bridge.DepositRecord.encode_injective"
  "Bridge.DepositRecord.encodeAsBytes_injective"
  "Bridge.BridgeState.encodeConsumed_injective"
  "Bridge.EthAddress.toBytes_injective"
  "Bridge.PendingWithdrawal.encode_injective"
  "Bridge.PendingWithdrawal.encodeAsBytes_injective"
  "Bridge.BridgeState.encodePending_injective"
  "Bridge.BridgeState.encode_injective"
  "FaultProof.commitExtendedState_subcommits_extensional_eq_under_collision_free"
)

ALLOWED='^(propext|Classical\.choice|Quot\.sound)$'

for t in "${THEOREMS[@]}"; do
  echo "Auditing: $t"
  AXIOMS=$(lake env lean -e "#print axioms $t" 2>&1 | grep -oE '[A-Za-z][A-Za-z0-9_.]*' || true)
  for ax in $AXIOMS; do
    if ! [[ "$ax" =~ $ALLOWED ]]; then
      echo "  VIOLATION: $t depends on $ax (not in allowlist)"
      exit 1
    fi
  done
done

echo "All EI theorems clean."
```

(Lives in `scripts/audit-ei-axioms.sh` once EI ships; not landed
with this plan revision.)

## Appendix C — Cross-document edit checklist

EI.8.j's grep sweep verifies these edits land cleanly.  The full
file inventory affected by EI.8's documentation retirement:

  * [ ] `CLAUDE.md` — footnote 1 removed; headline-theorems table
        updated; "Deferred from AR" section updated.
  * [ ] `AGENTS.md` — byte-identical with CLAUDE.md post-edit.
  * [ ] `docs/GENESIS_PLAN.md` §15B.1 — cites new theorem.
  * [ ] `docs/GENESIS_PLAN.md` §15C.7 — heading from "(deferred)"
        to "(complete)".
  * [ ] `docs/planning/audit_remediation_plan.md` §15C.2 — AR.4
        "Deferred" → "Complete"; AR.23 "Partial" → "Complete".
  * [ ] `docs/planning/audit_remediation_plan.md` §15C.7 — heading
        update.
  * [ ] `docs/planning/audit_remediation_plan.md` §4.4 — append
        "Complete" note.
  * [ ] `docs/planning/encoder_injectivity_plan.md` (this file) —
        Status section; per-sub-unit completion annotations.
  * [ ] `docs/planning/deferred_work_index.md` — EI rows updated
        (move from in-progress to complete; update closure
        column).
  * [ ] `LegalKernel.lean` — `kernelBuildTag` bumped.
  * [ ] `LegalKernel/Test/Umbrella.lean` — build-tag regression
        test updated.
  * [ ] `LegalKernel/Test/Integration/SnapshotBootstrap.lean` —
        AR.23.3 assertion lifted; "deferred" comment removed.
  * [ ] `README.md` — build-tag (per CL.1) — confirm whether
        README cites the build tag; edit if it does.
  * [ ] `solidity/README.md` — verify no footnote-1 / AR.4
        cross-reference; edit if present.
  * [ ] `docs/audits/05-encoding.md` — verify no stale
        cross-reference; annotate "resolved by EI" if appropriate.
  * [ ] `docs/audits/09-fault-proof.md` — same as above.
  * [ ] `docs/audits/19-findings-and-followups.md` — mark M-3
        ("Map-backed sub-state encoder injectivity") as
        "Complete".

## Appendix D — Open questions

| ID | Question | Owner | Resolution surface |
|----|----------|-------|---------------------|
| OQ-EI-1 | Where do the new injectivity lemmas live?  (Option A: append to existing files; Option B: per-sub-state `*Injective.lean` siblings; Option C: single `Encoding/Injectivity.lean`) | Implementer (EI.0.b) | Recommendation: Option B (mirrors `FaultProof/EncodeInjectivity.lean` pattern) |
| OQ-EI-2 | Visibility of `encodeAsBytes` (currently `private`).  Promote to non-`private` (clean export surface) or keep `private` and ship framing-injectivity lemmas inside the same file? | Implementer (EI.2.c review) | Recommendation: keep `private`; ship framing lemmas inside `Encoding/State.lean` and `Encoding/LocalPolicy.lean` |
| OQ-EI-3 | Should the per-sub-state theorems use the `Equiv` conclusion (plan's current choice) or also ship a derived "pointwise `getElem?`" form? | Plan + reviewer (EI.2.f retrospective) | Plan defaults: `Equiv`-shaped only; derived pointwise lemmas as optional sub-sub-unit additions where downstream consumers need them |
| OQ-EI-4 | If `Encodable.HasInjective` (EI.1.i) causes instance-search slowdowns, do we strike the typeclass and pass explicit hypotheses? | Implementer (EI.1.i implementation) | If `lake build` slows measurably (≥ 5%), strike EI.1.i and reformulate per-sub-state proofs |
| OQ-EI-5 | New `kernelBuildTag` value: `"canon-encoder-injectivity"` (plan default), `"canon-ei"`, or per-OQ-DOC-1? | Maintainer (EI.8.i) | Defer to OQ-DOC-1 in `open_questions.md`; plan uses `"canon-encoder-injectivity"` as a placeholder |
| OQ-EI-6 | Should `BalanceMap.encodeAsBytes`-type lemmas have `Equiv` or `Eq` conclusions when the inner carrier supports both? | Plan + reviewer (EI.2.c review) | Match the inner encoder's conclusion shape: `BalanceMap.encode` → `Equiv`; `DepositRecord.encode` → `Eq` |
| OQ-EI-7 | Does the Rust off-chain observer (Workstream H deferred WUs) need an EI-side hook? | Out of scope; document for the Rust workstream when scheduled | EI flags this in the "Out-of-scope" section §9 |
| OQ-EI-8 | Is `pendingWithdrawal_roundtrip` shipped, or does EI.7.b ship it as a precursor? | Implementer (EI.7.b audit) | Audit determines; if absent, ship in same PR |
| OQ-EI-9 | Is `bridgeState_roundtrip` shipped, or does EI.7.e ship it as a precursor? | Implementer (EI.7.e audit) | Audit determines; if absent, ship in same PR |
| OQ-EI-10 | Does `Std.TreeMap.equiv_iff_toList_eq` have a project-internal name (or is `equiv_iff_toList_eq` the literal Std name we use)? | Implementer (EI.0.a) | Audit during EI.0.a; the code already uses the bare name at two call sites |

---

**End of plan.**  Landing EI closes the headline residual proof
debt of the project and retires CLAUDE.md footnote 1.  Total
effort budget: ~9 engineer-days for serial execution, ~5 days
wall-clock with parallel EI.3 – EI.7 landing.
