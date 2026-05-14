<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

# Parameterized Laws (PA) — Landing Plan

This document plans the landing of Workstream PA (Parameterized
Laws), whose specification is already drafted in
`docs/parameterized_laws_plan.md` but has not landed in the
canonical phase-status table.  PA introduces deployment-tunable
parameters (transfer caps, mint quorums, withdrawal windows,
etc.) governed by an on-chain `governance` actor set, while
keeping all proven invariants intact.

This is the "finish the drafted workstream" plan: it does not
re-do PA's design work; it organises the implementation,
review, and landing.

## Status

  * **Drafted on:** branch `claude/add-law-voting-0jBAh` (per
    audit, drafted but not landed in main).
  * **Workstream prefix:** `PA` (Parameters).  Adopts the
    existing `parameterized_laws_plan.md` work-unit
    decomposition: PA.1 through PA.12 (the drafted plan's
    enumeration).  Confirm and adopt by reading the drafted
    plan §3 work-unit specifications.
  * **Effort estimate:** 6–10 calendar weeks for one full-time
    Lean engineer.  The drafted plan estimates per-WU effort;
    sum here is conservative (~30 engineer-days).
  * **Build-posture target:** all existing CI gates green;
    new `Parameters` substrate adds an `ExtendedState` field
    plus an `Action.setParameters` constructor (which freezes
    its index per the AR.5 regression pattern).
  * **TCB delta:** zero.  Parameters substrate lives in
    `LegalKernel/Parameters/` (new non-TCB sub-tree).
  * **Trust-assumption delta:** zero.  Parameter governance
    uses the existing `Verify` opaque.

## Table of contents

  * §1 Goals and non-goals
  * §2 Background
  * §3 Work-unit landing strategy
  * §4 Per-WU landing checklist (PA.1 – PA.12)
  * §5 Sequencing and PR structure
  * §6 Quality gates
  * §7 Risk register
  * §8 Acceptance criteria
  * §9 Out-of-scope items (the §14.2 deferrals stay deferred)
  * §10 References

## §1 Goals and non-goals

### §1.1 Goals

  1. **Land PA in main.**  Every PA WU spec'd in
    `parameterized_laws_plan.md` ships behind the existing CI
    gates, with two reviewers for any kernel-touching change
    (none expected for PA per the drafted plan's TCB-delta-zero
    posture).
  2. **Reserve `Action` / `Event` indices.**  PA adds at least
    `Action.setParameters` and `Event.parametersChanged`.  The
    AR.5 / AR.6 regression suites must extend in the same PR
    that introduces each constructor.
  3. **Ship the parameter-monotonicity firewall.**  PA's
    headline type-level guarantee:
    `ParameterMonotonicLawSet` — any law set declared
    parameter-monotonic mechanically rejects laws whose
    behaviour depends adversarially on a parameter change.
  4. **Update the project status surface.**  Add `PA` row to
    CLAUDE.md and README's phase-status tables.

### §1.2 Non-goals

  1. **No re-design.**  The drafted plan is the contract.
    Implementation deviations require updating the drafted plan
    in the same PR.
  2. **No §14.2 deferrals.**  The drafted plan's "Open
    questions / future work" remain deferred (stake-weighted
    voting, two-stage propose-then-apply, delta-style updates,
    timelock activation, per-resource caps, governance-actor
    LP interaction, dispute-pipeline interaction, fork
    parameter migration).  These are listed in the project's
    `open_questions.md` for future design decisions.
  3. **No Solidity mirror.**  Solidity-side governance is
    Workstream E-future; PA is Lean-only.
  4. **No retroactive law parameterisation.**  Existing laws
    stay un-parameterised; PA adds the parameter substrate
    *alongside* them.  A future workstream may parameterise
    `transfer` etc., but not under PA.

### §1.3 Reading guide

  * Read `docs/parameterized_laws_plan.md` first (the drafted
    plan).
  * This document supplements with landing-specific
    sequencing, CI gate alignment with the AR remediation
    pass's standards, and post-landing status updates.

### §1.4 Glossary

  * **Parameter substrate.**  The `ExtendedState.parameters`
    field holding deployment-tunable values.
  * **Parameter-monotonic.**  A law whose behaviour respects
    the partial order on parameter changes (e.g. a cap that
    can only loosen, not tighten retroactively).
  * **Governance signer set.**  The actors whose threshold
    signatures may issue `Action.setParameters`.

## §2 Background

`docs/parameterized_laws_plan.md` (drafted, ~3000 lines)
specifies:

  * **§3 Parameter substrate** — `ExtendedState.parameters`
    field; CBE encoding; deployment-genesis initialisation.
  * **§4 Governance** — `governanceSigners` set;
    `setParameters` action with multi-signature precondition.
  * **§5 Per-law parameter consumption** — read access via
    `s.parameters.X`; no write access from non-governance
    laws.
  * **§6 Monotonicity discipline** — `IsParameterMonotonic`
    typeclass + `ParameterMonotonicLawSet` firewall.
  * **§7 Event surface** — `Event.parametersChanged`.
  * **§8 Disputes integration** — verdicts may reference
    parameters in scope at filing time.
  * **§9 Lex-DSL surface** — `parameters { … }` clause in
    `lexlaw` macros.
  * **§10 Test plan** — value- and term-level coverage.
  * **§14.2 Open questions** — deferred items (see §9 below
    and `open_questions.md`).

PA Landing's job is to take that drafted plan, implement it,
test it, and ship.

## §3 Work-unit landing strategy

The drafted plan has 12 WUs (PA.1 – PA.12 per the drafted plan
numbering).  Recommended landing order, with two clusters:

```
Cluster A — substrate first (lands fully before B starts):
  PA.1 (Parameters type)
  PA.2 (ExtendedState extension)
  PA.3 (CBE encoding)
  PA.4 (Genesis initialisation)

Cluster B — governance and laws (parallelisable internally):
  PA.5 (governanceSigners + setParameters action)
  PA.6 (action admissibility + nonce integration)
  PA.7 (event emission)
  PA.8 (monotonicity typeclass)
  PA.9 (firewall law set)
  PA.10 (parameter consumption examples)

Cluster C — DSL and tests (final):
  PA.11 (Lex parameters clause)
  PA.12 (end-to-end regression suite)
```

Cluster A is the foundation: every other WU depends on the
parameters substrate.  Cluster B may parallelise across two
contributors after PA.5 lands.  Cluster C is integration.

## §4 Per-WU landing checklist

For each PA.k, the landing PR must:

  - [ ] Implement the spec from
    `docs/parameterized_laws_plan.md` §3.<k> verbatim
    (deviations require updating the drafted plan).
  - [ ] Pass `lake build`, `lake test`, and all audit binaries.
  - [ ] Include term-level API-stability tests for every new
    theorem.
  - [ ] If introducing an `Action` or `Event` constructor,
    extend `Authority/Action.lean` + `Encoding/Action.lean` +
    AR.5 (Action.tag) regression test + AR.6 (Event.tag)
    regression test in the same PR.
  - [ ] If introducing a new `LocalPolicyClause` variant,
    extend `Authority/LocalPolicy.lean` + LP regression tests.
  - [ ] Update `docs/parameterized_laws_plan.md` "Status"
    section to mark the WU "complete".
  - [ ] One reviewer (per CLAUDE.md "law modules require one
    reviewer").

Specific WU sketches (consult drafted plan for full
specifications):

### PA.1 — `Parameters` substrate type

  * `LegalKernel/Parameters/Types.lean`.
  * `structure Parameters` with fields like
    `transferCap : Option Amount`, `mintQuorum : Nat`,
    `withdrawalWindow : Nat`, plus extension hook.
  * `Inhabited Parameters` with deployment defaults.

### PA.2 — `ExtendedState.parameters` field

  * Add `parameters : Parameters` to `ExtendedState`.
  * Update `ExtendedState.mk` constructors and all destructuring
    pattern matches.
  * Migration note: existing test fixtures need a default
    `parameters` value; supply via `ExtendedState.empty`.

### PA.3 — CBE encoding

  * `LegalKernel/Encoding/Parameters.lean`.
  * `Encodable Parameters` instance with deterministic order.
  * Round-trip lemma `parameters_roundtrip`.
  * Encoder-injectivity lemma `parameters_encode_injective` —
    follows the EI workstream's template (see
    `docs/encoder_injectivity_plan.md` §2.4 "proof recipe").
    `Parameters` is a flat structure (not map-backed) so the
    proof is simpler than EI.2 – EI.7: discharge each field's
    atomic encoder injectivity, then conclude structurally.
    If EI has not landed when PA.3 lands, the proof still
    stands (it does not consume EI's helper lemmas; the
    template is the *shape*, not a dependency).

### PA.4 — Genesis initialisation

  * Update `LegalKernel/Runtime/Loop.lean` boot sequence to
    accept a `Parameters` value from genesis config.
  * CLI flag: `--initial-parameters <hex>` on the `canon`
    binary.

### PA.5 — `governanceSigners` + `setParameters` action

  * `Action.setParameters (newParams : Parameters)
     (signers : List ActorId) (sigs : List Signature)`.
  * Precondition: threshold-many valid signatures from
    `s.parameters.governanceSigners`.
  * Frozen index: reserve the next available integer; pin
    via AR.5 regression test.

### PA.6 — Admissibility + nonce integration

  * Each signer's per-actor nonce bumps on a successful
    `setParameters`.  The kernel's existing per-actor nonce
    machinery in `Authority/Nonce.lean` handles this; PA.6
    threads the action through.

### PA.7 — `Event.parametersChanged`

  * `Event.parametersChanged (oldParams newParams : Parameters)
     (signers : List ActorId)`.
  * Extracted by `Events.extractEvents` for the
    `setParameters` action.
  * Frozen index: reserve via AR.6 regression test.

### PA.8 — `IsParameterMonotonic` typeclass

  * `class IsParameterMonotonic (t : Transition) : Prop where
     mono : ∀ s s', s.parameters ≤ s'.parameters →
                       t.pre s → t.pre s'`
  * Witness instances for each kernel law that consumes
    parameters: ParameterMonotonic on `transfer` w/ cap, etc.

### PA.9 — `ParameterMonotonicLawSet` firewall

  * `def ParameterMonotonicLawSet : List Transition → Prop :=
     ∀ t ∈ ls, IsParameterMonotonic t`
  * Type-level firewall: a `ParameterMonotonicLawSet`
    declaration won't elaborate if the law set contains a
    non-monotonic law.

### PA.10 — Parameter consumption: example laws

  * Demonstrate consumption by parameterising `transfer.pre`
    with a `transferCap` from `s.parameters`.  Ship as a
    new law `parameterizedTransfer` alongside the existing
    `transfer`; do not modify existing laws.

### PA.11 — Lex `parameters` clause

  * `parameters { transferCap : Option Amount, ... }` block
    in `lex_law` macros.  Synthesises the appropriate
    `s.parameters.X` reads.
  * Extension to the `Lex.DSL.Law` macro.

### PA.12 — End-to-end regression suite

  * Cross-validation: genesis parameter set → ApplyAction →
    parametersChanged event → second action constrained by new
    parameters.  Replay determinism preserved across the
    chain.

## §5 Sequencing and PR structure

```
Sprint 1 (week 1–2)            PA.1, PA.2, PA.3, PA.4 (Cluster A)
Sprint 2 (week 3–4)            PA.5, PA.6, PA.7
Sprint 3 (week 5)              PA.8, PA.9
Sprint 4 (week 6)              PA.10, PA.11
Sprint 5 (week 7)              PA.12 + status updates
```

Total: ~7 calendar weeks for one full-time engineer (10–14
calendar weeks if part-time or in parallel with other work).

## §6 Quality gates

Standard project gates:

  * `lake build`
  * `lake test`
  * `lake exe count_sorries`
  * `lake exe tcb_audit`
  * `lake exe stub_audit`
  * `lake exe naming_audit`
  * `lake exe deferral_audit`
  * `lake exe lex_lint`
  * `lake exe lex_codegen --check`

Plus PA-specific:

  * AR.5 / AR.6 regression tests extended for each new
    `Action` / `Event` constructor.
  * `#print axioms` on every new theorem reduces to a subset
    of the three Lean built-ins.

## §7 Risk register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `ExtendedState` extension breaks existing tests | High | Low | Add `parameters` field with `Inhabited` default; update test fixtures in PA.2 PR |
| New `Action` index collides with E-future reservation | Low | Medium | Audit `Action.lean` for reserved-but-unused indices before PA.5 |
| Monotonicity typeclass too restrictive (rejects sensible laws) | Medium | Medium | Provide an `IsParameterMonotonic.weaken` escape hatch with deployment-level justification |
| Lex `parameters` clause complexity creep | Medium | Low | Defer advanced features (typed-parameter wrappers) to LX v3 per existing roadmap |
| Drafted plan revisions during landing | High | Low | Land plan-revision PR before resuming WU PRs; never silently deviate |

## §8 Acceptance criteria

PA is **complete** when:

  1. All 12 PA WUs land.
  2. `lake build` and `lake test` green across the full
    project.
  3. Headline theorems shipped:
     - `parameters_roundtrip`
     - `parameters_encode_injective` (post-EI; otherwise
       parameters substate gets a future encoder-injectivity
       follow-up registered alongside EI)
     - `setParameters_admissible_iff_quorum_met`
     - `parameter_monotonic_law_set_preserves_admissibility`
  4. `Action.setParameters` and `Event.parametersChanged`
    indices reserved and frozen.
  5. CLAUDE.md status table adds "PA" row marked "Complete".
  6. README phase-table updated.
  7. `docs/parameterized_laws_plan.md` "Status" section says
    "Landed in PR #..." with the merge SHA.
  8. `docs/parameterized_laws_plan.md` §14.2 "Open questions"
    forwarded to `docs/open_questions.md`.

## §9 Out-of-scope items (these stay deferred — see open_questions.md)

  * Stake-weighted / token-weighted quorum.
  * Two-stage propose-then-apply.
  * Delta-style parameter updates.
  * Effective-at-block timelock.
  * Per-resource parameter caps.
  * Governance-actor / LocalPolicy interaction enforcement.
  * Parameter migration across `CanonMigration` forks.
  * Solidity-side governance mirror.

Each is registered in `docs/open_questions.md` under "PA forward
roadmap".

## §10 References

  * `docs/parameterized_laws_plan.md` — the drafted spec.
  * `docs/audit_remediation_plan.md` — AR.5 / AR.6 patterns.
  * `docs/actor_scoped_policies_plan.md` — LP pattern for
    actor-scoped behavioural specs.
  * `docs/lex_implementation_plan.md` — Lex macro extension
    pattern.

---

**End of plan.**  Landing PA closes the only "drafted but not
landed" workstream and adds parameter-tuning capability to
deployments while preserving every shipped invariant.
