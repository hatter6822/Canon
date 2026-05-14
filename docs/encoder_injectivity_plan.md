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
fault-proof chain from bytes-equality to extensional state equality.

The work is the single largest residual Lean proof debt identified
by the audit-remediation pass.  The formal design (CBE canonicality
for map-backed types) lives in `docs/GENESIS_PLAN.md` §15B.1 / §15C.7
and `docs/audit_remediation_plan.md` §4.4 / §15C.7.

## Status

  * **Workstream prefix:** `EI` (Encoder Injectivity).  Sub-units
    `EI.1` … `EI.8`.  Inherits the eight-sub-unit decomposition
    sketched in `docs/audit_remediation_plan.md` §4.4 (formerly
    AR.4.1 – AR.4.8); `EI.k` corresponds to the AR plan's `AR.4.k`.
  * **Branch convention:** `claude/encoder-injectivity-<slug>`,
    landing in a single PR per sub-unit for bisection cleanliness.
    `EI.2` (the template sub-unit) may take two PRs (skeleton +
    closure) at reviewer discretion.
  * **Build-posture target:** `lake build`, `lake test`, plus all
    audit binaries (`count_sorries`, `tcb_audit`, `stub_audit`,
    `naming_audit`, `deferral_audit`, `lex_lint`,
    `lex_codegen --check`) green throughout.  **No new sorries**,
    **no new axioms**, **no new opaques**, **no TCB expansion**.
  * **TCB delta:** zero.  All new theorems land in
    `LegalKernel/Encoding/*.lean` (non-TCB).  `Kernel.lean` and
    `RBMapLemmas.lean` are untouched.
  * **Trust-assumption delta:** zero.  The injectivity proofs are
    closed-form; they depend only on `propext`, `Classical.choice`,
    `Quot.sound`, and the existing `Std.TreeMap` lemma set.
  * **Frozen indices reserved:** none.  EI does not add `Action`
    or `Event` constructors.

## Table of contents

  * §1 Goals and non-goals
    * §1.1 Goals
    * §1.2 Non-goals
    * §1.3 Reading guide
    * §1.4 Glossary
  * §2 Mathematical background
    * §2.1 What "encoder injectivity" means precisely
    * §2.2 The bytes-eq → toList-eq → extensional-eq lift
    * §2.3 CBE canonicality for map-backed types
    * §2.4 The proof recipe (one sub-state at a time)
  * §3 Work-unit dependencies
    * §3.1 Strict ordering
    * §3.2 Parallel-safe sub-units
    * §3.3 Critical path
  * §4 Work-unit specifications (EI.1 – EI.8)
  * §5 Sequencing and PR structure
  * §6 Quality gates, rollback, roll-forward
  * §7 Risk register
  * §8 Acceptance criteria for the workstream
  * §9 Out-of-scope items
  * §10 References

## §1 Goals and non-goals

### §1.1 Goals

  1. **Ship the five `*_encode_injective` lemmas** for the
     `ExtendedState` sub-states whose underlying carrier is
     `Std.TreeMap`: `BalanceMap` (`State.balances` substrate),
     `NonceState`, `KeyRegistry`, `LocalPolicies`,
     `BridgeState.consumed`, and `BridgeState.pending`.  Each
     theorem has the schema

     ```
     theorem <sub>_encode_injective :
       ∀ (m₁ m₂ : <Carrier>),
         <sub>.encode m₁ = <sub>.encode m₂ →
         ∀ k, m₁[k]? = m₂[k]?
     ```

     The conclusion is *extensional* equality (point-wise lookup
     equality), not structural map equality.  Extensional
     equality is the form the fault-proof chain consumes.

  2. **Promote `commitExtendedState_subcommits_bytes_eq_under_collision_free`
     to a full extensional-equality variant.**  The new theorem

     ```
     theorem commitExtendedState_subcommits_extensional_eq_under_collision_free :
       CollisionFree hashBytes →
       commitExtendedState s₁ = commitExtendedState s₂ →
       s₁ ~ext s₂
     ```

     where `~ext` is the per-sub-state extensional-equality
     conjunction.  This is the AR.23 lift point: the snapshot-
     bootstrap regression suite then promotes from "bytes match"
     to "states are extensionally equal".

  3. **Retire CLAUDE.md footnote 1.**  Update CLAUDE.md and the
     Genesis Plan in the EI.8 PR; the footnote's substance is
     replaced by the shipped theorem name.

  4. **Establish the proof template** so future sub-states
     inherit a turnkey injectivity proof.  EI.1 (the helper
     lemma) and EI.2 (the `BalanceMap` template) are the
     templates.  Two downstream workstreams plan to reuse
     them: PA (`docs/parameterized_laws_landing_plan.md`
     PA.3) for the `parameters` substrate encoder, and any
     Phase 7 sub-workstream that adds a new map-backed
     sub-state (see `docs/phase_7_plan.md` for the
     sub-workstreams).

### §1.2 Non-goals

  1. **No change to the encoder definition.**  The `*_encode`
     functions already canonicalise (encode sorted by key); EI
     proves that property, it does not change it.

  2. **No new `Encodable` instance.**  All five sub-states already
     have `Encodable` instances and round-trip lemmas.

  3. **No structural equality lemma.**  `m₁ = m₂` (Lean's `Eq` on
     `TreeMap`) is *strictly stronger* than extensional equality
     because two structurally-distinct red-black trees can
     represent the same logical map.  EI proves extensional
     equality only; structural-equality is intentionally out of
     scope and not needed by any downstream consumer.

  4. **No change to bytes-equality theorems.**  The existing
     `commitExtendedState_subcommits_bytes_eq_under_collision_free`
     stays in source as a load-bearing lemma; EI.8 *adds* the
     extensional variant alongside.

  5. **No CBE wire-format change.**  The encoder's byte output is
     untouched.  Existing log files remain replayable byte-for-byte.

### §1.3 Reading guide

  * **Implementer:** read §2 (mathematical background) then §4 in
    order EI.1 → EI.8.  Each sub-unit's "Implementation steps"
    section is self-contained.
  * **Reviewer:** read §1, §2, then the sub-unit being reviewed.
    The "Acceptance criteria" + "Reviewer checklist" sections
    define what to check.
  * **Future auditor:** read §1 + §8 (acceptance criteria for the
    overall workstream) + §10 (cross-references).  The shipped
    theorem names match the headline theorems table in CLAUDE.md.

### §1.4 Glossary

  * **Extensional equality** (`~ext`).  For `m₁ m₂ : TreeMap α β _`:
    `∀ k, m₁[k]? = m₂[k]?`.  Weaker than `Eq`, stronger than
    bytes-equality.
  * **Canonical encoding.**  An encoding such that two extensionally-
    equal inputs produce identical bytes.  Equivalent to:
    `m₁ ~ext m₂ → encode m₁ = encode m₂`.  Already shipped as
    `*_encode_deterministic`.
  * **Injective encoding.**  An encoding such that identical bytes
    imply extensionally-equal inputs.  Equivalent to:
    `encode m₁ = encode m₂ → m₁ ~ext m₂`.  This is the missing
    direction.
  * **Sorted-pair representation.**  The canonical `List (Key × Val)`
    form: ordered ascending by `compare`, no duplicate keys.
    Produced by `TreeMap.toList` on a tree of order `compare`.
  * **CBE (Canonical Binary Encoding).**  Canon's wire format;
    see `LegalKernel/Encoding/CBOR.lean` and §8.7 of the Genesis
    Plan.

## §2 Mathematical background

### §2.1 What "encoder injectivity" means precisely

For each sub-state `S` (the `BalanceMap`, `NonceState`, etc.) we
have an encoder `encode : S → ByteArray` and a decoder
`decode : ByteArray → Except DecodeError S`.  The existing
machinery gives:

  * **Round-trip (decode∘encode = ok).**  `decode (encode m) = .ok m'`
    where `m' ~ext m` (extensional, not structural — because the
    decoder builds a fresh tree by inserting pairs in order,
    which produces the same `toList` but possibly a different
    internal RB shape).
  * **Determinism / canonicality.**  `m₁ ~ext m₂ → encode m₁ = encode m₂`.

What is missing is the *injective* direction.  Formally:

```
theorem balanceMap_encode_injective :
  ∀ (m₁ m₂ : TreeMap ActorId Amount compare),
    BalanceMap.encode m₁ = BalanceMap.encode m₂ →
    ∀ k, m₁[k]? = m₂[k]?
```

(Substitute the appropriate carrier type for each sub-state.)

### §2.2 The bytes-eq → toList-eq → extensional-eq lift

The proof factors through three intermediate steps.  Let
`m₁ m₂ : TreeMap α β cmp` with the project's `compare`-order.

```
        encode m₁ = encode m₂        (hypothesis: bytes equal)
              │
              ▼  (CBE injectivity at the byte level)
   sortedPairs₁ = sortedPairs₂        (sorted (k, v) lists equal)
              │
              ▼  (m.toList = sortedPairs m for compare-ordered RB)
        m₁.toList = m₂.toList         (toList representations equal)
              │
              ▼  (toList-eq ⇒ pointwise lookup equal)
        ∀ k, m₁[k]? = m₂[k]?         (extensional equality)
```

Each arrow is a separate lemma.  The middle arrow
(`m.toList = sortedPairs m`) is the *insight*: the encoder's
deterministic ordering is exactly `TreeMap.toList`, which by
RB-balance invariants is the unique sorted-pair representation.
This is the load-bearing observation; once it is shipped as
EI.1, every per-sub-state proof reduces to a mechanical instance.

### §2.3 CBE canonicality for map-backed types

CBE encodes a map as `cbe_array(cbe_pair(k_1, v_1), …,
cbe_pair(k_n, v_n))` where the pairs are sorted ascending by `k`.
The full canonicality contract has four obligations:

  1. **Pair-list canonicality** (no duplicates, sorted).  Holds by
    construction of `TreeMap.toList`.
  2. **Per-key encoder injectivity** (`Encodable α` and `Encodable β`
    are injective).  Holds for all atomic carriers (`Nat`,
    `ByteArray`, `ActorId`, `Amount`, `PublicKey`, `Nonce`, etc.)
    because each has a shipped `_encode_injective` lemma in
    `Encoding/Encodable.lean`.
  3. **`cbe_pair` and `cbe_array` injectivity.**  Already shipped
    in `Encoding/CBOR.lean`.
  4. **No length-prefix ambiguity.**  CBE uses CBOR major-type
    discipline; the byte-stream is unambiguously segmented.

The encoder injectivity proof composes these four obligations.

### §2.4 The proof recipe (one sub-state at a time)

For each sub-state `S` with carrier `TreeMap α β`:

  1. **Step A.**  From `S.encode m₁ = S.encode m₂` extract
    `cbe_array_eq` (the CBE pair-list arrays are equal as bytes).
  2. **Step B.**  Apply the CBE-array injectivity lemma:
    `cbe_array_inj : encodeArray xs = encodeArray ys → xs = ys`
    (already in `Encoding/CBOR.lean`).
  3. **Step C.**  The resulting equality is over
    `List (encodedPair α β)`.  Apply CBE-pair injectivity
    point-wise to get `List (α × β)` equality.
  4. **Step D.**  Apply the helper lemma EI.1
    (`encodeSortedPairs_decodeMap_roundtrip`): both lists are
    `m.toList`-shaped, so the lists are `toList m₁ = toList m₂`.
  5. **Step E.**  Apply `toList_eq_iff_extensional` (a small new
    lemma, also under EI.1): `toList m₁ = toList m₂ → ∀ k, m₁[k]? = m₂[k]?`.
  6. **QED.**

The mechanical work per sub-state is therefore (A) wrap the
specific sub-state's encoder, (B) discharge the per-value
injectivity goal (e.g. `Amount.encode_injective`,
`LocalPolicy.encode_injective`).  Step (B) is the *only*
non-trivial cost; the rest is template instantiation.

## §3 Work-unit dependencies

### §3.1 Strict ordering

```
EI.1 ──► EI.2 ──► EI.3, EI.4, EI.5, EI.6, EI.7 (parallelisable)
                                                 │
                                                 ▼
                                              EI.8 (composition)
```

  * **EI.1 blocks everything else.**  EI.1 ships
    `encodeSortedPairs_decodeMap_roundtrip` and
    `toList_eq_iff_extensional`.  Every per-sub-state proof
    consumes EI.1.
  * **EI.2 (`BalanceMap`) is the template.**  It is the hardest
    sub-state because the value type is itself a map
    (`TreeMap ActorId (TreeMap ResourceId Amount _) _`).  Landing
    EI.2 first establishes the nested-map proof pattern and
    surfaces any unexpected obstacles before parallel work
    starts.
  * **EI.3 – EI.7 are parallel.**  Each is a different sub-state
    with a flat carrier; they share no internal dependency.
    Reviewers may merge them in any order.
  * **EI.8 is the closer.**  Composes the five injectivity
    lemmas into the headline `commitExtendedState_subcommits_extensional_eq_under_collision_free`
    theorem.  Lands after EI.2 – EI.7.

### §3.2 Parallel-safe sub-units

After EI.1 + EI.2 ship, EI.3 / EI.4 / EI.5 / EI.6 / EI.7 may be
implemented in parallel by separate contributors as long as each
PR is scoped to a single sub-state's `Encoding/*.lean` file.

### §3.3 Critical path

```
EI.1 (~1.5 days) ─► EI.2 (~3 days) ─► (parallel batch ~2 days) ─► EI.8 (~1 day)
                                       └─ critical path
```

Critical path: **~7.5 working days** for a single full-time
contributor.  The lower bound of the AR.4 9–16-day estimate
assumes serial execution; the upper bound includes review cycles
and any per-sub-state surprise (e.g. `LocalPolicy.encode_injective`
turning out to need its own sub-lemma).

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
  * **Effort** — engineer-days.

---

### EI.1 — Helper lemmas: `encodeSortedPairs_decodeMap_roundtrip` + `toList_eq_iff_extensional`

**Finding map.**  Foundation for AR.4 (M-3) + CLAUDE.md footnote 1.

**Scope.**  `LegalKernel/Encoding/Encodable.lean` (additive: two
new theorems alongside existing CBE machinery).

**Math / proof outline.**

Two helper lemmas, both polymorphic over the key/value carriers
and the `compare` predicate.  Let `cmp : α → α → Ordering` and
`m : TreeMap α β cmp` and `xs : List (α × β)`.

```
theorem encodeSortedPairs_decodeMap_roundtrip
    {α β : Type*} {cmp : α → α → Ordering}
    [Encodable α] [Encodable β] [LawfulCmp cmp]
    (m : TreeMap α β cmp) :
  decodeMap (encodeSortedPairs (TreeMap.toList m)) = .ok m
```

This is essentially the existing `*_roundtrip` lemmas extracted
into a single polymorphic statement.  Proof: induction on the
toList structure, using existing `TreeMap.find?_insert_*` lemmas
from `RBMapLemmas.lean`.

```
theorem toList_eq_iff_extensional
    {α β : Type*} {cmp : α → α → Ordering} [LawfulCmp cmp]
    (m₁ m₂ : TreeMap α β cmp) :
  TreeMap.toList m₁ = TreeMap.toList m₂ ↔ ∀ k, m₁[k]? = m₂[k]?
```

Proof: forward direction is a fold over the toList structure
using `TreeMap.find?_eq_of_toList_eq`.  Reverse direction follows
from the canonical ordering of `toList` (sorted, no duplicates):
two maps with identical pointwise lookup have identical
`toList`s by `TreeMap.toList_canonical` (a Std lemma; if missing,
land it under EI.1 as a small auxiliary lemma using
`Std.TreeMap.toList_sorted` + extensional uniqueness).

**Implementation steps.**

  1. Open `LegalKernel/Encoding/Encodable.lean`.  Add the two
    theorems after the existing `Encodable.encode_injective`
    lemma block.
  2. Add a small section header `section TreeMapEncodable` so the
    helper lemmas group cleanly.
  3. If `TreeMap.toList_canonical` (or equivalent) is not in
    `RBMapLemmas.lean`, add it there.  This is a one-line proof
    using `Std.TreeMap.toList_isSorted` + uniqueness; the
    `RBMapLemmas.lean` ownership rule means TWO REVIEWERS are
    required for this addition.

**Acceptance criteria.**

  * `lake build LegalKernel.Encoding.Encodable` succeeds.
  * `lake exe count_sorries` passes (no new sorries).
  * `lake exe tcb_audit` passes (if `RBMapLemmas.lean` is
    touched, the two-reviewer rule applies; the helper lemma is
    Std-only and does not expand the TCB).
  * `#print axioms encodeSortedPairs_decodeMap_roundtrip` and
    `#print axioms toList_eq_iff_extensional` both return
    `[propext, Classical.choice, Quot.sound]` (or a strict subset).

**Test plan.**

  * Value-level: encode two extensionally-equal trees built by
    different insertion orders, assert byte-equality (already
    covered by `Encoding/Test/Roundtrip.lean`; reaffirm).
  * Term-level: ascribe each new theorem to a `let _proof : T :=
    theorem ...` binding in `LegalKernel/Test/Encoding/Injectivity.lean`
    (new test file).

**DoD.**

  * [ ] Two new theorems land in `Encodable.lean`.
  * [ ] Optional `toList_canonical` lemma in `RBMapLemmas.lean`
    (if not already present).
  * [ ] Term-level API test added in `Test/Encoding/Injectivity.lean`.
  * [ ] `#print axioms` of both theorems prints the three Lean
    built-ins only.

**Verification.**

```bash
lake build LegalKernel.Encoding.Encodable
lake build LegalKernel.Test.Encoding.Injectivity
lake test
lake exe count_sorries
lake exe tcb_audit
```

**Reviewer checklist.**

  * Theorem signatures match §2 schema.
  * No `axiom`; no `sorry`.
  * `#print axioms` confirms the three built-ins only.
  * If `RBMapLemmas.lean` was touched, second reviewer signed
    off.

**Risk.**  Low.  Pure proof addition; no behaviour change.

**Effort.**  ~1.5 engineer-days.

---

### EI.2 — `BalanceMap.encode_injective` (template sub-unit)

**Finding map.**  AR.4.2 (template) + M-3.

**Scope.**  `LegalKernel/Encoding/Encodable.lean` or a new file
`LegalKernel/Encoding/BalanceMapInjective.lean`.

**Math / proof outline.**

The carrier is `TreeMap ActorId (TreeMap ResourceId Amount _) _`
— a nested map.  The proof recursively applies the EI.1 helpers
twice: once for the outer map, once for the inner.

```
theorem BalanceMap.encode_injective :
  ∀ (b₁ b₂ : BalanceMap),
    BalanceMap.encode b₁ = BalanceMap.encode b₂ →
    ∀ a r, b₁[a]?.bind (·[r]?) = b₂[a]?.bind (·[r]?)
```

Note the conclusion is *nested* extensional equality (pointwise
in both the actor key and the resource key).  The flat-conclusion
form

```
∀ k, b₁[k]? = b₂[k]?
```

is *not* what we want — it would compare two inner `TreeMap`s as
options, but two extensionally-equal inner trees can be
structurally distinct.  The nested form is the load-bearing
shape.

**Proof sketch.**

  1. From `BalanceMap.encode b₁ = BalanceMap.encode b₂` extract
    the equality of outer-array CBE encodings.
  2. Apply CBE-array injectivity (`cbe_array_inj`).
  3. The resulting list-equality is over the encoded inner-pairs.
    By pointwise CBE-pair injectivity, this gives
    `List.zip outer₁.toList outer₂.toList`-style equality.
  4. For each (actor, inner_map) pair, the inner CBE-array
    encodings are equal.  Apply EI.1 recursively to get
    `∀ r, inner₁[r]? = inner₂[r]?`.
  5. Compose: `∀ a r, b₁[a]?.bind (·[r]?) = b₂[a]?.bind (·[r]?)`.

**Implementation steps.**

  1. State the theorem in `Encoding/Encodable.lean` (or new file
    `BalanceMapInjective.lean`; recommend new file for review
    cleanliness).
  2. Prove via the recipe in §2.4 with one extra application of
    EI.1 for the inner map.
  3. Add a Lean-level comment block above the proof citing §2.4
    and EI.1 (one short line; no multi-paragraph docstring).

**Acceptance criteria.**

  * Theorem lands.  `lake build` succeeds.  `count_sorries` and
    `tcb_audit` pass.
  * `#print axioms` of the theorem prints a subset of the three
    Lean built-ins.

**Test plan.**

  * Value-level: construct two `BalanceMap`s that differ on a
    single (actor, resource) entry, encode both, assert encodings
    differ.
  * Negative: construct two structurally-distinct `BalanceMap`s
    that are extensionally equal (e.g. via different insertion
    order), encode both, assert encodings equal (`*_encode_deterministic`
    coverage; already exists but reaffirm in the new test file).
  * Term-level API test.

**DoD.**

  * [ ] `BalanceMap.encode_injective` shipped.
  * [ ] New test file `Test/Encoding/BalanceMapInjective.lean`.
  * [ ] `#print axioms` clean.

**Verification.**

```bash
lake build LegalKernel.Encoding.BalanceMapInjective  # if new file
lake build LegalKernel.Test.Encoding.BalanceMapInjective
lake test
lake exe count_sorries
```

**Reviewer checklist.**

  * Nested extensional-equality conclusion matches §2.1.
  * Proof factors cleanly through EI.1 helpers.
  * No new auxiliary lemmas in `RBMapLemmas.lean` unless they are
    truly Std-flavoured (would require two reviewers).

**Risk.**  Medium.  Nested maps are the hardest case; the proof
template established here is reused by EI.3 – EI.7.  If the proof
turns out to need a new auxiliary lemma, surface it during code
review and consider extracting it back into EI.1 (then re-merging
EI.1 before continuing).

**Effort.**  ~3 engineer-days.

---

### EI.3 — `NonceState.encode_injective`

**Finding map.**  AR.4.3 + M-3.

**Scope.**  `LegalKernel/Encoding/State.lean` (where `NonceState`
encoder lives) or new `Encoding/NonceStateInjective.lean`.

**Math / proof outline.**

Flat map: `TreeMap ActorId Nonce compare`.  One application of
the §2.4 recipe.

```
theorem NonceState.encode_injective :
  ∀ (n₁ n₂ : NonceState),
    NonceState.encode n₁ = NonceState.encode n₂ →
    ∀ a, n₁.expectedNonce a = n₂.expectedNonce a
```

Note the conclusion is phrased in terms of `expectedNonce` (the
public NonceState accessor) rather than raw `m[k]?`, matching the
NonceState API surface.

**Implementation steps.**

  1. State and prove the theorem.  Apply §2.4 steps A – E with
    the trivial atomic value-encoder injectivity for `Nonce`
    (`Nonce` is a `Nat` wrapper; injectivity is by definition).
  2. Add a small bridge lemma `NonceState.expectedNonce_eq_of_extensional`
    if needed to translate from `[k]?` to `expectedNonce` (likely
    a one-liner).

**Acceptance criteria.**  As EI.2.

**Test plan.**  As EI.2 with NonceState fixtures.

**DoD.**  As EI.2.

**Verification.**  As EI.2 with `NonceStateInjective` paths.

**Reviewer checklist.**  As EI.2.

**Risk.**  Low.  Flat map, atomic value.

**Effort.**  ~1 engineer-day.

---

### EI.4 — `KeyRegistry.encode_injective`

**Finding map.**  AR.4.4 + M-3.

**Scope.**  `LegalKernel/Encoding/State.lean` (KeyRegistry
encoder) or new `Encoding/KeyRegistryInjective.lean`.

**Math / proof outline.**

Flat map: `TreeMap ActorId PublicKey compare`.  Same recipe as
EI.3.  `PublicKey` is a `ByteArray` wrapper with shipped
`ByteArray.encode_injective`.

```
theorem KeyRegistry.encode_injective :
  ∀ (k₁ k₂ : KeyRegistry),
    KeyRegistry.encode k₁ = KeyRegistry.encode k₂ →
    ∀ a, k₁.publicKeyOf a = k₂.publicKeyOf a
```

**Implementation steps + acceptance + test + DoD + verification.**
Same template as EI.3.

**Risk.**  Low.

**Effort.**  ~1 engineer-day.

---

### EI.5 — `LocalPolicies.encode_injective`

**Finding map.**  AR.4.5 + M-3.

**Scope.**  `LegalKernel/Encoding/LocalPolicy.lean` or new
`Encoding/LocalPoliciesInjective.lean`.

**Math / proof outline.**

Flat map: `TreeMap ActorId LocalPolicy compare`.  The wrinkle:
`LocalPolicy` is a structure containing a `List LocalPolicyClause`
where `LocalPolicyClause` is an inductive with three constructors
(`denyTag`, `requireRecipient`, `capAmount`).  Injectivity at the
clause level is therefore a discrete case-split.

```
theorem LocalPolicyClause.encode_injective :
  ∀ (c₁ c₂ : LocalPolicyClause),
    LocalPolicyClause.encode c₁ = LocalPolicyClause.encode c₂ →
    c₁ = c₂

theorem LocalPolicy.encode_injective :
  ∀ (p₁ p₂ : LocalPolicy),
    LocalPolicy.encode p₁ = LocalPolicy.encode p₂ →
    p₁ = p₂  -- structural; List + inductive

theorem LocalPolicies.encode_injective :
  ∀ (ps₁ ps₂ : LocalPolicies),
    LocalPolicies.encode ps₁ = LocalPolicies.encode ps₂ →
    ∀ a, ps₁.lookup a = ps₂.lookup a
```

`LocalPolicyClause.encode_injective` may already exist (M2's
constructor-tag pinning machinery in Lex requires per-constructor
encoder identities).  If so, reuse; if not, ship it under EI.5
as a sub-lemma.

**Implementation steps.**

  1. Audit `LocalPolicy.lean` for an existing
    `LocalPolicyClause.encode_injective` lemma.
  2. If absent, ship it: case-split on the constructor, apply
    atomic encoder injectivity per arm.
  3. Lift to `LocalPolicy.encode_injective`: a `List` of
    `LocalPolicyClause`s; use `List.encode_injective` (already
    in `Encoding/Encodable.lean` for any element type with an
    injective encoder).
  4. Apply §2.4 to lift to the `LocalPolicies` map.

**Risk.**  Medium-low.  The inductive case-split is mechanical
but the per-arm value carriers (`Tag`, `ActorId`, `Amount`) must
each have a shipped `_encode_injective`; audit those first.

**Effort.**  ~1.5 engineer-days.

---

### EI.6 — `BridgeState.consumed.encode_injective`

**Finding map.**  AR.4.6 + M-3.

**Scope.**  `LegalKernel/Encoding/Bridge.lean` or new
`Encoding/BridgeConsumedInjective.lean`.

**Math / proof outline.**

Set-like: `TreeMap DepositId Unit compare`.  Encoded as a sorted
list of `DepositId`s (the `Unit` value is encoded as zero bytes).
Injectivity reduces to `DepositId.encode_injective` (a `ByteArray`
wrapper) plus the helper lemma.

```
theorem BridgeState.consumed_encode_injective :
  ∀ (c₁ c₂ : TreeMap DepositId Unit compare),
    consumedEncode c₁ = consumedEncode c₂ →
    ∀ d, c₁.contains d = c₂.contains d
```

**Implementation steps + DoD.**  Trivial instance of the
template.

**Risk.**  Low.

**Effort.**  ~0.5 engineer-day.

---

### EI.7 — `BridgeState.pending.encode_injective`

**Finding map.**  AR.4.7 + M-3.

**Scope.**  `LegalKernel/Encoding/Bridge.lean` or new
`Encoding/BridgePendingInjective.lean`.

**Math / proof outline.**

Flat map with rich value: `TreeMap WithdrawalId PendingWithdrawal compare`.
`PendingWithdrawal` is a structure (`{ recipient, amount,
resourceId, l1Block }`).  Each field carrier has a shipped
`_encode_injective`.

```
theorem PendingWithdrawal.encode_injective :
  ∀ (p₁ p₂ : PendingWithdrawal),
    PendingWithdrawal.encode p₁ = PendingWithdrawal.encode p₂ →
    p₁ = p₂

theorem BridgeState.pending_encode_injective :
  ∀ (p₁ p₂ : TreeMap WithdrawalId PendingWithdrawal compare),
    pendingEncode p₁ = pendingEncode p₂ →
    ∀ w, p₁[w]? = p₂[w]?
```

**Implementation steps.**  Establish
`PendingWithdrawal.encode_injective` first (struct decomposition),
then apply the §2.4 recipe.

**Risk.**  Low-medium.

**Effort.**  ~1 engineer-day.

---

### EI.8 — Composition: `commitExtendedState_subcommits_extensional_eq_under_collision_free`

**Finding map.**  AR.4.8 + M-3 + CLAUDE.md footnote 1 retirement.

**Scope.**  `LegalKernel/FaultProof/Commit.lean` (where the
existing bytes-eq lemma lives).

**Math / proof outline.**

Compose the five injectivity lemmas with the existing
`commitExtendedState_subcommits_bytes_eq_under_collision_free` to
produce the headline theorem:

```
def ExtendedState.extEq (s₁ s₂ : ExtendedState) : Prop :=
  (∀ a r, s₁.state.balances[a]?.bind (·[r]?) =
          s₂.state.balances[a]?.bind (·[r]?)) ∧
  (∀ a, s₁.state.nonces.expectedNonce a = s₂.state.nonces.expectedNonce a) ∧
  (∀ a, s₁.state.keys.publicKeyOf a = s₂.state.keys.publicKeyOf a) ∧
  (∀ a, s₁.state.policies.lookup a = s₂.state.policies.lookup a) ∧
  (∀ d, s₁.bridge.consumed.contains d = s₂.bridge.consumed.contains d) ∧
  (∀ w, s₁.bridge.pending[w]? = s₂.bridge.pending[w]?)

theorem commitExtendedState_subcommits_extensional_eq_under_collision_free
    (h_cr : CollisionFree hashBytes)
    (h_eq : commitExtendedState s₁ = commitExtendedState s₂) :
  ExtendedState.extEq s₁ s₂
```

Proof: apply the existing bytes-eq lemma to get sub-state-wise
byte equality, then apply EI.2 – EI.7 to lift each sub-state's
byte-equality to the extensional form, then conjoin.

**Implementation steps.**

  1. Define `ExtendedState.extEq` (or reuse if a stub exists).
  2. State the composition theorem alongside the existing
    bytes-eq lemma in `FaultProof/Commit.lean`.
  3. Update CLAUDE.md: remove footnote 1, update the FaultProof
    headline-theorem row from the bytes-eq theorem to the new
    extensional-eq theorem (or list both).
  4. Update `docs/GENESIS_PLAN.md` §15B.1 to cite the new
    theorem and retire the corresponding deferral note.
  5. Update `docs/audit_remediation_plan.md` §15C.7 from
    "Encoder injectivity (deferred)" to "Encoder injectivity
    (complete; landed under workstream EI)".
  6. Lift `LegalKernel/Test/Integration/SnapshotBootstrap.lean:117`
    from bytes-eq assertion to extensional-eq assertion (closes
    AR.23 to "Complete" status).
  7. Replace the inline comment `requires the AR.4.8 extensional-
    equality lemma (deferred)` with a content-describing comment
    or just remove the comment.

**Acceptance criteria.**

  * The new composition theorem lands.
  * CLAUDE.md footnote 1 is removed.
  * GENESIS_PLAN.md §15B.1 cites the new theorem.
  * AR.23 ships its strongest-form assertion.
  * `#print axioms` of the new theorem prints a subset of the
    three Lean built-ins.

**Test plan.**

  * Value-level: construct two `ExtendedState`s that differ only
    by RB-tree-internal shape (extensionally equal); assert
    `commitExtendedState` returns the same hash; then apply the
    new theorem to assert `ExtendedState.extEq`.
  * Value-level negative: construct two `ExtendedState`s that
    differ on a single balance entry; assert `commitExtendedState`
    differs.
  * Term-level API test.

**DoD.**

  * [ ] Composition theorem shipped.
  * [ ] CLAUDE.md footnote 1 retired.
  * [ ] GENESIS_PLAN.md §15B.1 / §15C.7 updated.
  * [ ] AR.23 partial → complete in
    `audit_remediation_plan.md` §15C.2 status table.
  * [ ] `SnapshotBootstrap.lean` regression test lifted.

**Verification.**

```bash
lake build LegalKernel.FaultProof.Commit
lake build LegalKernel.Test.FaultProof.Commit
lake test
lake exe count_sorries
lake exe deferral_audit   # footnote-1 removal must not leave
                           # a "deferred to follow-up" trace
```

**Reviewer checklist.**

  * Composition theorem references each of the five injectivity
    lemmas explicitly (named, not by `simp` magic).
  * `ExtendedState.extEq` definition matches the per-sub-state
    extensional forms shipped in EI.2 – EI.7.
  * Documentation updates are consistent across CLAUDE.md,
    GENESIS_PLAN.md, and `audit_remediation_plan.md`.

**Migration notes.**  The bytes-eq lemma stays in source as a
load-bearing primitive (other call sites consume it directly).
EI.8 *adds* the extensional variant; no breaking change.

**Risk.**  Low.  Pure composition; the hard work is in EI.2 – EI.7.

**Effort.**  ~1 engineer-day (mostly documentation).

## §5 Sequencing and PR structure

```
PR-1  ─ EI.1  ─ helper lemmas + RBMapLemmas auxiliary (2 reviewers if RBMapLemmas)
PR-2  ─ EI.2  ─ BalanceMap.encode_injective (template; 1 reviewer)
PR-3  ─ EI.3  ─ NonceState.encode_injective       \
PR-4  ─ EI.4  ─ KeyRegistry.encode_injective       \
PR-5  ─ EI.5  ─ LocalPolicies.encode_injective      ─ parallel landing
PR-6  ─ EI.6  ─ BridgeState.consumed.encode_injective /
PR-7  ─ EI.7  ─ BridgeState.pending.encode_injective /
PR-8  ─ EI.8  ─ Composition + footnote-1 retirement (1 reviewer)
```

Each PR title prefix: `EI.<n>: <one-line summary>`.  PR body
must include `#print axioms <new theorem>` output as a sanity
check.

## §6 Quality gates, rollback, roll-forward

### §6.1 Per-PR forcing functions (unchanged from AR)

  * `lake build` (full project)
  * `lake test`
  * `lake exe count_sorries`
  * `lake exe tcb_audit`
  * `lake exe stub_audit`
  * `lake exe naming_audit`
  * `lake exe deferral_audit`
  * `lake exe lex_lint`
  * `lake exe lex_codegen --check`

### §6.2 Two-reviewer gate

EI.1 if it touches `RBMapLemmas.lean` requires two reviewers
(§13.6).  No other sub-unit triggers the two-reviewer rule
because EI proofs live in non-TCB `Encoding/*.lean` files.

### §6.3 Rollback

Each sub-unit is a single PR.  Rollback is `git revert <sha>`.
Theorems are additive; reverting affects only downstream PRs
(e.g. reverting EI.1 forces revert of all EI.2 – EI.8).

### §6.4 Roll-forward

If a sub-unit lands with a defective proof (audit catches it),
the fix lands in a new PR titled `EI.<n>.fix: <description>`
that supersedes the defective theorem.  Do not amend; preserve
git history per CLAUDE.md policy.

## §7 Risk register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `Std.TreeMap.toList_canonical` (or equivalent) absent from Std core | Medium | Medium | Ship as auxiliary in `RBMapLemmas.lean` under EI.1; triggers two-reviewer gate |
| `LocalPolicyClause.encode_injective` already exists in a place that fights with the EI.5 namespace | Low | Low | Audit during EI.5 implementation; reuse or rename |
| EI.2 template surfaces a structural issue (e.g. nested-map encoder uses a non-canonical inner ordering) | Low | High | EI.2 lands first specifically to surface this; if found, redesign before EI.3 – EI.7 start |
| `PendingWithdrawal.encode_injective` requires per-field carrier proofs that are missing | Medium | Low | Audit `Encoding/*.lean` for shipped atomic injectivity lemmas first; ship missing carriers as EI.7 sub-lemmas |
| Footnote-1 retirement misses one cross-reference (CLAUDE.md, README.md, GENESIS_PLAN.md, audit_remediation_plan.md, fault_proof_design.md, audits/05-encoding.md, audits/09-fault-proof.md) | High | Low | EI.8 checklist explicitly enumerates each file; grep for the footnote text at landing |
| `deferral_audit` regression after footnote-1 removal (the audit doesn't currently scan CLAUDE.md but the project may extend it) | Low | Low | Run `deferral_audit` in the EI.8 PR's CI; the binary's scope is `LegalKernel/`, `Lex/`, `Tools/` per source, not `docs/` |

## §8 Acceptance criteria for the workstream

EI is **complete** when:

  1. Five `*_encode_injective` lemmas ship: `BalanceMap`,
    `NonceState`, `KeyRegistry`, `LocalPolicies`,
    `BridgeState.consumed`, `BridgeState.pending` (six lemmas
    because BridgeState has two sub-trees; the §1.1 schema
    counts them as one workstream item).
  2. `commitExtendedState_subcommits_extensional_eq_under_collision_free`
    ships in `FaultProof/Commit.lean`.
  3. CLAUDE.md footnote 1 is removed; the headline-theorems
    table cites the new composition theorem.
  4. GENESIS_PLAN.md §15B.1 cites the new theorem; §15C.7
    is updated to "Complete".
  5. `audit_remediation_plan.md` §15C.2 status table moves
    AR.4 from "Deferred" to "Complete" and AR.23 from
    "Partial" to "Complete".
  6. `lake exe count_sorries`, `lake exe tcb_audit`,
    `lake exe deferral_audit` all pass.
  7. `#print axioms` on each new theorem prints a subset of
    `[propext, Classical.choice, Quot.sound]`.
  8. Every new theorem has a term-level API-stability test in
    `LegalKernel/Test/Encoding/Injectivity.lean` (or per-file
    test modules).
  9. The `kernelBuildTag` in `LegalKernel.lean` bumps to a new
    value reflecting EI landing; `Test/Umbrella.lean` is
    updated in the same PR.

## §9 Out-of-scope items

  * **Structural map equality** (`m₁ = m₂` as Lean `Eq`).
    Strictly stronger than what EI proves; unnecessary for any
    shipped consumer.  Future work if a consumer ever requires
    it.
  * **`Std.TreeMap` lemma library fork.**  EI uses Std as-is.
  * **Cross-format encoder injectivity** (e.g. proving a
    deployment that swaps CBE for protobuf has the same
    injectivity property).  EI is about the canonical CBE
    encoder; alternative encoders would need their own
    injectivity proofs.
  * **`@[extern]` adaptor swap-out injectivity.**  Production
    deployments may swap `hashBytes` via `@[extern]`.  The
    composition theorem is conditioned on `CollisionFree hashBytes`
    (a hypothesis, not a fact); deployments that swap a
    non-collision-free hash break the conclusion, by design.

## §10 References

  * `docs/audit_remediation_plan.md` §4.4 (original AR.4 spec)
    and §15C.7 (deferral note).
  * `docs/GENESIS_PLAN.md` §15B.1 (state-commitment scheme),
    §15C.7 (encoder injectivity deferral).
  * `CLAUDE.md` footnote 1 (the gap being closed).
  * `LegalKernel/FaultProof/Commit.lean` — the existing bytes-eq
    theorem `commitExtendedState_subcommits_bytes_eq_under_collision_free`.
  * `LegalKernel/Encoding/Encodable.lean` — the existing
    `Encodable` class and per-carrier injectivity lemmas.
  * `LegalKernel/RBMapLemmas.lean` — the TCB-tier RB-map lemma
    library (touched only by EI.1 if `toList_canonical` is
    missing).
  * `docs/std_dependencies.md` — Std-library lemma audit.

---

**End of plan.**  Landing EI closes the headline residual proof
debt of the project and retires CLAUDE.md footnote 1.
