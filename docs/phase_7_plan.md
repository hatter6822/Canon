<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

# Phase 7 — Advanced Capabilities — Engineering Plan

This document plans Phase 7, the long-horizon advanced-capability
workstream that GENESIS_PLAN.md §12 lists as "not started"
with a 20.0+ engineer-weeks open-ended estimate.

Phase 7 is **not a single deliverable**; it is a portfolio of
seven independent work units that may be undertaken in any
order, each adding a major capability to the system.  This plan
treats them as seven sub-workstreams, each with its own goals,
non-goals, work-unit decomposition, and acceptance criteria.

## Status

  * **Workstream prefix:** `P7`.  Seven sub-workstreams:
    - **P7.A** Capabilities (object-capability authorisation).
    - **P7.B** Threshold signatures (FROST adaptor).
    - **P7.C** ZK proof of admissibility (Plonk via halo2).
    - **P7.D** Intent solver (constraint-based action search).
    - **P7.E** Cross-shard transition protocol.
    - **P7.F** Schema migration framework.
    - **P7.G** Multi-region replication (CRDT log).
  * **Effort estimate:** 20+ engineer-weeks (open-ended).  Each
    sub-workstream's effort is 2–4 calendar weeks for one
    full-time engineer with relevant domain expertise.
  * **Build-posture target:** every sub-workstream lands behind
    the existing CI gates; introduces zero custom axioms; does
    not touch the TCB without explicit two-reviewer approval.
  * **Dependencies:** each sub-workstream has prerequisites on
    earlier phases (Phase 3 for P7.A / P7.B / P7.D, Phase 5 for
    P7.C / P7.E / P7.F / P7.G).
  * **Trust-assumption delta:** P7.B and P7.C introduce new
    trust assumptions (FROST DKG correctness; SNARK soundness)
    documented in their respective sub-workstream §1.2.

## Table of contents

  * §1 Goals and non-goals for Phase 7 overall
  * §2 Sub-workstream specifications
    * §2.A Capabilities (P7.A)
    * §2.B Threshold signatures (P7.B)
    * §2.C ZK proof of admissibility (P7.C)
    * §2.D Intent solver (P7.D)
    * §2.E Cross-shard transition protocol (P7.E)
    * §2.F Schema migration framework (P7.F)
    * §2.G Multi-region replication (P7.G)
  * §3 Cross-cutting concerns
  * §4 Sequencing recommendations
  * §5 Quality gates
  * §6 Risk register (portfolio-level)
  * §7 Acceptance criteria for Phase 7 as a whole
  * §8 References

## §1 Goals and non-goals (portfolio-level)

### §1.1 Phase 7 goals

  1. **Add seven major capabilities** to the project, each
    additive to the existing kernel + Authority + Bridge +
    Lex + FaultProof surface.
  2. **Preserve TCB invariants.**  Every sub-workstream ships
    under non-TCB modules.  Any kernel touch requires the
    §13.6 two-reviewer rule.
  3. **Preserve zero-custom-axiom discipline.**  Each
    sub-workstream's theorems reduce to a subset of
    `[propext, Classical.choice, Quot.sound]`.

### §1.2 Phase 7 non-goals

  1. **No single big-bang landing.**  Each sub-workstream is
    independent and can land in any order.
  2. **No commitment to ship all seven.**  Phase 7 is a
    capability menu; deployments may pick a subset.
  3. **No retroactive changes to Phases 0–6.**  Each
    sub-workstream extends the surface; existing theorems
    are unchanged.

### §1.3 Reading guide

This document is a *portfolio plan*.  Each sub-workstream's
detailed engineering plan should be lifted out into its own
document at the moment landing begins (e.g.
`docs/phase_7a_capabilities_plan.md`).  Use this document for:
  - Portfolio-level coordination.
  - Pre-implementation cost-benefit triage.
  - Cross-cutting design constraint enumeration.

## §2 Sub-workstream specifications

---

### §2.A Capabilities (P7.A)

**Provenance.**  GENESIS_PLAN.md §12 WU 7.1 + §3.X.

**Goal.**  Introduce object-capability authorisation alongside
the existing identity + nonce + signature scheme.  Capabilities
are unforgeable tokens that grant scoped permission (e.g. "may
mint resource R up to amount A until block B").

**Dependencies.**  Phase 3 (Authority layer) complete (✓).

**Design sketch.**

```lean
structure Capability where
  issuer    : ActorId
  scope     : ScopeSpec      -- inductive: resource, amount cap, time bound
  delegates : List ActorId   -- transitive delegation
  nonce     : Nonce
  issuerSig : Signature

inductive ScopeSpec where
  | mintAuthority (resource : ResourceId) (cap : Amount) (validUntil : Block)
  | transferAuthority (from : ActorId) (allow : Set ResourceId) ...
  | spend (capId : Hash) (amount : Amount)
  ...
```

A new `Action.applyCapability (cap : Capability) (use : ApplyUse)`
constructor takes a capability + a usage record, validates that:
  1. The capability's issuer signature is valid.
  2. The capability has not expired (block bound, nonce-burn).
  3. The usage is within scope.
  4. The capability has not been revoked (registry check).

**Work-unit decomposition.**

  * P7.A.1 `Capability` type + scope inductive.
  * P7.A.2 CBE encoding (round-trip + injective).
  * P7.A.3 Issuance law: `Action.issueCapability`.
  * P7.A.4 Use law: `Action.applyCapability`.
  * P7.A.5 Revocation law: `Action.revokeCapability` (registry
    bumps; collides with existing `replaceKey` machinery; reuse).
  * P7.A.6 Type-level capability firewall: `CapabilitySafeLawSet`
    rejects laws that bypass the capability check.
  * P7.A.7 Test suite.
  * P7.A.8 Lex DSL extension for capability-grant clauses.

**Headline theorem.**

```lean
theorem capability_use_admissible_iff_scope_match :
  ∀ s cap use, Action.applyCapability cap use ∈ admissible s ↔
    capability_in_scope cap use ∧ capability_not_revoked s cap ∧
    capability_signature_valid cap
```

**Effort.**  2.0 calendar weeks.

**Risks.**

  * Capability revocation interacts with the existing nonce
    machinery; design carefully.
  * Transitive delegation can lead to exponential authority
    chains; bound by depth.

---

### §2.B Threshold signatures — FROST adaptor (P7.B)

**Provenance.**  GENESIS_PLAN.md §12 WU 7.2.

**Goal.**  Replace single-signer `Verify` with a threshold-
signature scheme (FROST over secp256k1) for governance and
multi-actor admission flows.

**Dependencies.**  Phase 3.4 complete (✓); ideally PA (parameter
governance) landed first.

**Design sketch.**

Two integration points:
  1. **Aggregated signature opaque.**  A new `verifyThreshold :
    List PublicKey → ByteArray → Signature → Nat → Bool` opaque
    (alongside the existing `Verify`).  The implementation
    expects a FROST-aggregated `Signature` and a threshold `Nat`.
  2. **Distributed key generation (DKG).**  The DKG protocol
    runs off-chain; only the aggregated public key lands on-chain.
    `Action.registerThresholdGroup (pk_agg, members, threshold)`
    publishes the group.

**Work-unit decomposition.**

  * P7.B.1 `verifyThreshold` opaque + `runtime/canon-verify-frost`
    Rust adaptor (parallel to RH-A.1).
  * P7.B.2 `Action.registerThresholdGroup`.
  * P7.B.3 `Action.applyThresholdSigned` (wraps a non-threshold
    `Action` with a threshold signature).
  * P7.B.4 Replay-prevention for threshold groups (nonce per
    group, not per member).
  * P7.B.5 Lex DSL clause: `threshold_signed_by { group: G,
    threshold: K }`.
  * P7.B.6 Test suite with cross-stack FROST vectors.

**Headline theorem.**

```lean
theorem threshold_signature_replay_impossible :
  ∀ s s' wrapped, AdmissibleThreshold s wrapped →
                  ApplyThreshold s wrapped = .ok s' →
                  ¬ AdmissibleThreshold s' wrapped
```

(Same structure as the existing `replay_impossible` but lifted
to threshold-wrapped actions.)

**Effort.**  2.0 calendar weeks.

**Trust-assumption delta.**  Adds: "FROST DKG produces an
honestly-generated aggregated public key when at least `threshold`
of the participants follow the protocol."  Documented in
`extraction_notes.md` §2 under WG.4 pattern.

---

### §2.C ZK proof of admissibility — Plonk / halo2 (P7.C)

**Provenance.**  GENESIS_PLAN.md §12 WU 7.3.

**Goal.**  Allow `Action` admissibility to be proved via a
SNARK rather than via in-line precondition evaluation, reducing
L1 verification cost and enabling private inputs.

**Dependencies.**  Phase 5 (Runtime + extraction) complete (✓).

**Design sketch.**

The SNARK circuit encodes:
  - Public input: pre-state hash, action ID, post-state hash.
  - Witness: full pre-state, action body, admissibility proof
    trace.
  - Constraint: `step_impl` agrees with the public inputs.

**Work-unit decomposition.**

  * P7.C.1 Circuit specification (a Plonkish IR of `step_impl`
    for a single law, starting with `transfer`).
  * P7.C.2 `halo2` proof generator (Rust crate).
  * P7.C.3 On-chain verifier (Solidity contract).
  * P7.C.4 `Action.applyWithZkProof` constructor + admissibility.
  * P7.C.5 Cross-stack verifier corpus.
  * P7.C.6 Performance: target ≤ 100k gas per verification.

**Headline theorem.**

```lean
theorem zk_proof_completeness :
  ∀ s action s', step_impl action.toTransition hpre s = .ok s' →
                  ∃ π, verifyZkProof (commitState s) action.id (commitState s') π = true

theorem zk_proof_soundness :
  SnarkSoundness verifyZkProof →
  ∀ s action s' π, verifyZkProof (commitState s) action.id (commitState s') π = true →
                    ∃ hpre, step_impl action.toTransition hpre s = .ok s'
```

`SnarkSoundness` is a new opaque deployment-supplied predicate
capturing the SNARK's cryptographic soundness assumption.

**Effort.**  4.0 calendar weeks.

**Trust-assumption delta.**  Adds: "Plonk over BN254 is sound
under the AGM and the discrete-log assumption."

---

### §2.D Intent solver (P7.D)

**Provenance.**  GENESIS_PLAN.md §12 WU 7.4.

**Goal.**  A constraint-based action-sequence search engine:
given a desired post-state predicate (`P : ExtendedState → Prop`)
and a starting state `s`, search the action space for a
sequence of admissible actions producing a state satisfying
`P`.

**Dependencies.**  Phase 3 (Authority) complete (✓).

**Design sketch.**

```lean
def IntentSolve (s : ExtendedState) (P : ExtendedState → Prop) :
                IO (Option (List Action))
```

The solver is *not* part of the kernel; it lives in
`LegalKernel/Intent/Solver.lean` as a non-TCB synthesis
helper.  It produces a candidate action sequence; the kernel's
admissibility predicate still verifies each step.

**Work-unit decomposition.**

  * P7.D.1 Constraint language (a small predicate DSL).
  * P7.D.2 Solver core (best-first search over `Action`
    constructors with depth bound).
  * P7.D.3 Heuristic pruning (parameter-aware).
  * P7.D.4 Test suite over toy intents.
  * P7.D.5 Lex DSL: `intent { from: X, achieves: P, by: ... }`.

**Headline property** (not a theorem; the solver is a tool):

```
If IntentSolve s P returns Some seq, then applying seq to s
produces a state satisfying P.
```

This is *operationally* verified: the solver's output is fed
through the standard admissibility chain; bugs in the solver
produce rejected actions, not unsoundness.

**Effort.**  3.0 calendar weeks.

---

### §2.E Cross-shard transition protocol (P7.E)

**Provenance.**  GENESIS_PLAN.md §12 WU 7.5.

**Goal.**  Allow a single logical state to span multiple
`canon` instances (shards), with cross-shard transitions
mediated by a shard-coordination protocol.

**Dependencies.**  Phase 5.5 (replay tool) complete (✓).

**Design sketch.**

Two-phase commit over `n` shards.  Each shard runs its own
`canon`; cross-shard actions are split into:
  1. A "prepare" phase on every shard touching its substate.
  2. A "commit" phase that finalises all shards atomically.

**Work-unit decomposition.**

  * P7.E.1 `Action.crossShardPrepare` + `Action.crossShardCommit`.
  * P7.E.2 Per-shard `crossShardCoordinator` opaque (the
    deployment-supplied 2PC implementation).
  * P7.E.3 Type-level atomicity lemma: a successful commit
    on shard `i` implies a successful commit on every other
    shard.
  * P7.E.4 Two-shard demonstration (the GENESIS_PLAN §12 WU
    7.5 acceptance criterion).

**Headline theorem.**

```lean
theorem crossShard_atomic :
  ∀ shards s_init s_final action,
    CrossShardCommitted shards action →
    ∀ s ∈ shards, s.committed action
```

**Effort.**  4.0 calendar weeks.

**Risks.**  Distributed systems are hard.  Failure modes
include partial commits under coordinator faults; the design
must surface these explicitly as deployment-level concerns.

---

### §2.F Schema migration framework (P7.F)

**Provenance.**  GENESIS_PLAN.md §12 WU 7.6.

**Goal.**  Allow a running deployment to migrate to a new
`ExtendedState` schema (e.g. add a new sub-state) without log
truncation.

**Dependencies.**  Phase 5.12 (`CanonMigration` infrastructure)
complete (✓).

**Design sketch.**

A migration is a function
`migrate : ExtendedState_old → ExtendedState_new` plus a
provable invariant `migrate_preserves_admissibility`.  Live
deployments execute the migration at a designated `Block`;
the transition appears as a new `Action.migrate` constructor
in the log.

**Work-unit decomposition.**

  * P7.F.1 `MigrationSpec` type with `oldSchema` /
    `newSchema` / `migrate` / `preservation_proof`.
  * P7.F.2 `Action.migrate` constructor.
  * P7.F.3 Type-level guarantee:
    `migration_preserves_law_set_admissibility`.
  * P7.F.4 Demo: add a `tags : Set Tag` field to a synthetic
    state schema.

**Effort.**  2.0 calendar weeks.

---

### §2.G Multi-region replication (CRDT log) (P7.G)

**Provenance.**  GENESIS_PLAN.md §12 WU 7.7.

**Goal.**  Replicate the canonical log across geographically
distributed `canon` instances using CRDT-style convergent
operations.

**Dependencies.**  Phase 5.12 (replay infrastructure) complete
(✓).

**Design sketch.**

A *commutative* operation set: only kernel `Action`s that
admit commutative composition can be replicated.  Non-commutative
actions (e.g. `setParameters`) require explicit anchoring to
the primary region.

The CRDT layer is *outside* the kernel; the kernel sees a single
deterministic log per region.  The CRDT log is the cross-region
synchronisation primitive.

**Work-unit decomposition.**

  * P7.G.1 Commutativity classification: `IsCommutative
    (action : Action) : Prop`.
  * P7.G.2 CRDT merge function over commutative actions.
  * P7.G.3 Anchor protocol for non-commutative actions.
  * P7.G.4 Multi-region demo (two regions, latency-injected
    test harness).

**Headline theorem.**

```lean
theorem crdt_convergence :
  ∀ region_logs : List Log,
    pairwise_commutative region_logs →
    ∃ merged : Log,
      ∀ r ∈ region_logs, Reachable r.final_state merged.final_state
```

**Effort.**  3.0 calendar weeks.

---

## §3 Cross-cutting concerns

### §3.1 Action index reservations

Each sub-workstream reserves a frozen range of `Action`
constructor indices.  Coordinate via `Lex.IndexRegistry.txt`
(append-only registry):

| Sub-workstream | Reserved range |
|---|---|
| P7.A Capabilities | 30–35 (5 constructors) |
| P7.B Threshold sigs | 36–38 (3 constructors) |
| P7.C ZK proofs | 39 (1 constructor) |
| P7.D Intent solver | none (solver is non-Action) |
| P7.E Cross-shard | 40–41 (2 constructors) |
| P7.F Schema migration | 42 (1 constructor) |
| P7.G Multi-region | none (CRDT is layer-above) |

Indices are illustrative; consult the actual registry before
implementation.

### §3.2 Opaque expansion

Sub-workstreams that introduce new opaques (P7.B, P7.C, P7.E)
must document them in `extraction_notes.md` §2 (the
trust-assumption catalogue) at landing time.

### §3.3 TCB discipline

No sub-workstream is expected to touch the TCB.  If a kernel
extension is necessary (e.g. for P7.A's capability machinery),
the two-reviewer rule and Genesis-Plan amendment process apply.

### §3.4 Lex DSL extensions

P7.A, P7.B, and P7.D each introduce new Lex clauses
(`capability_grant`, `threshold_signed_by`, `intent`).  These
should land alongside the kernel-side work, with `lex_lint`
diagnostic codes reserved (deferred-set in
`Lex/Test/Tools/DiagnosticCoverage.lean`).

## §4 Sequencing recommendations

Phase 7 has no single critical path.  Recommended ordering
(based on dependency, demand, and risk):

```
Highest priority (demand-driven, low risk):
  P7.A Capabilities       (2.0w, depends on Phase 3)
  P7.F Schema migration   (2.0w, depends on Phase 5.12)

Medium priority (capability-expanding):
  P7.B Threshold sigs     (2.0w, depends on Phase 3.4 + PA)
  P7.D Intent solver      (3.0w, depends on Phase 3)

Lower priority (high research, high impact):
  P7.G Multi-region       (3.0w, depends on Phase 5.12)
  P7.E Cross-shard        (4.0w, depends on Phase 5.5)
  P7.C ZK proofs          (4.0w, depends on Phase 5.1)
```

Total: **20 calendar weeks** for one full-time engineer
working serially; **8–10 weeks** for two engineers working
in parallel (P7.A + P7.F first as low-risk parallel landings).

## §5 Quality gates

Standard project gates plus:
  * Each sub-workstream's `#print axioms` reduces to a subset
    of the three Lean built-ins, plus any explicitly-documented
    sub-workstream-specific opaques.
  * `Action` / `Event` index reservations honoured (extends
    AR.5 / AR.6 regression tests in the same PR).
  * Cross-stack fixture corpus extended for sub-workstreams
    with Solidity counterparts (P7.B, P7.C, P7.F).
  * `extraction_notes.md` §2 updated for new opaques.

## §6 Risk register (portfolio-level)

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Sub-workstreams interact unexpectedly (e.g. P7.A capabilities + P7.B threshold-signed actions) | Medium | Medium | Land sub-workstreams behind feature flags; integration tests at cross-cuts |
| Action-index space exhausts | Low | Low | Index space is 256-wide today; Phase 7 reserves ~13 slots; plenty of headroom |
| Phase 7 capability creep absorbs project bandwidth indefinitely | High | High | Treat as a menu; pick 2–3 sub-workstreams per release cycle; do not commit to all seven upfront |
| New opaque expansion is forgotten in `extraction_notes.md` | Medium | Medium | Pre-merge checklist includes "extraction_notes.md updated" |
| TCB change required for an unforeseen sub-workstream | Low | High | Treat any TCB-touching change as a Genesis-Plan amendment; pause sub-workstream until §13.6 + §14.4 process complete |

## §7 Acceptance criteria for Phase 7 as a whole

Phase 7 is **complete** when:

  1. Each shipped sub-workstream has:
     - Implementation complete in `LegalKernel/<area>/`.
     - Tests passing.
     - Headline theorem(s) shipped with clean `#print axioms`.
     - Cross-stack corpus extended (where applicable).
     - Lex DSL extension (where applicable).
     - `Action` / `Event` indices frozen via AR.5 / AR.6 pattern.
  2. CLAUDE.md status table:
     - "Phase 7 | 7 WUs | 20.0+ | partial — `<n>` of 7
       shipped" until all seven ship.
     - When all seven ship: "Phase 7 | 7 WUs | 20.0+ | complete".
  3. `docs/GENESIS_PLAN.md` §12 phase table updated to reflect
    each landing.
  4. Each sub-workstream's detailed plan exists as its own
    document under `docs/phase_7<letter>_<topic>_plan.md`.

**Note:** Phase 7 may *never* fully complete in the absolute
sense; deployments may legitimately ship without (e.g.) ZK
proofs.  "Complete" means "every sub-workstream's spec is
realised", not "every deployment uses every capability".

## §8 References

  * `docs/GENESIS_PLAN.md` §12 (phase roadmap).
  * `docs/lex_implementation_plan.md` — pattern for new Lex
    DSL extensions.
  * `docs/audit_remediation_plan.md` — AR.5 / AR.6 pattern for
    Action / Event index freezing.
  * `Lex/IndexRegistry.txt` — frozen action-index registry.
  * `LegalKernel/Authority/Action.lean` — action constructor
    set.

---

**End of plan.**  Phase 7 is a portfolio.  Each sub-workstream's
detailed implementation plan is lifted at landing time; this
document is the portfolio-level coordination contract.
