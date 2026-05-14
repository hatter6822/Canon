<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

# Open Questions — Master Design-Decision Registry

This document is the canonical registry of *open design
questions* for the Canon project: questions that have surfaced
during planning but for which a project-level decision has not
yet been made.  It is the single point of reference for future
workstream planners and for design-review discussions.

Each open question is presented with:
  - **Context** — where it arose, what's at stake.
  - **Options** — the alternatives identified.
  - **Trade-offs** — what each option costs / buys.
  - **Recommendation** — the project's current best guess
    (subject to discussion).
  - **Owner / status** — who's expected to drive the decision.

Open questions are **not** deferred work in the sense of
"someone will implement this later" — they are decisions
prerequisite to *deciding what to implement*.  Once a decision
is made, the relevant workstream plan absorbs the choice and
implementation proceeds.

## Table of contents

  * §1 How to use this document
  * §2 Cross-cutting / architectural questions
  * §3 PA (Parameterized Laws) — forward-roadmap questions
  * §4 LP (Actor-Scoped Policies) — open questions
  * §5 LX (Lex language) — v2 / v3 design questions
  * §6 Workstream H (Fault-Proof) — open questions
  * §7 Phase 7 — portfolio prioritisation questions
  * §8 Documentation / process questions
  * §9 Resolved questions (historical record)
  * §10 References

## §1 How to use this document

  * **For workstream planners.**  Read the relevant section
    (PA, LP, LX, etc.) before writing implementation details.
    A question marked "OPEN" with no recommendation means the
    workstream must surface the trade-off in its plan and
    request a project-level decision.  A question with a
    recommendation may be implemented per the recommendation;
    document the choice in the plan PR.
  * **For reviewers.**  When you see a PR implementing a
    behaviour, check whether that behaviour is governed by an
    open question.  If yes: was the recommendation followed?
    Was an alternative chosen with explicit reasoning?
  * **For maintainers.**  Promote a question from "OPEN" to
    "RESOLVED" when a definitive decision lands; move it to
    §9 with the resolution recorded.

Each question has a sticky identifier (e.g. `OQ-PA-1`) that
PR descriptions can cite.

### §1.1 Urgency matrix — questions by when they must resolve

The columns are *blocking horizon*: when a decision on the
question becomes necessary for a workstream to proceed.

| Horizon | Questions | Drive-by workstream |
|---------|-----------|----------------------|
| **NOW** (blocks an in-flight workstream) | OQ-DOC-4 | CL.1 (cleanup landing) |
| **Before EI.2 commits** | none | EI.2 sets its own design |
| **Before RH lands** | OQ-X-1 (Rust toolchain), OQ-X-2 (corpus format) | RH-H |
| **Before WG lands** | none (WG is documentation) | WG |
| **Before PA lands** | OQ-PA-1 through OQ-PA-8 (most can default to "v1 simpler" recommendation) | PA |
| **Before LX2 lands** | OQ-LX-1 (refinement direction), OQ-LX-5 (deploymentId derivation) | LX2 |
| **Before LX3 lands** | OQ-LX-6 (resource-roles), OQ-LX-7 (LSP scope), OQ-LX-8 (revokeKey kernel) | LX3 |
| **Before Phase 7** | OQ-P7-1 (sub-workstream selection), OQ-X-3 (multi-deployment) | P7 |
| **Long-term** | OQ-H-2 (multi-sequencer), OQ-H-3 (ZK timing), OQ-H-4 (L1Attestation soundness lift) | future H follow-ups |

A question with a clear recommendation may be acted on under
that recommendation without explicit ratification.  A question
without a recommendation or one marked "OPEN" *with* a
trade-off that varies by deployment requires the
deployment / project lead to decide.

## §2 Cross-cutting / architectural questions

### OQ-X-1 — Rust toolchain pinning strategy

**Context.**  `rust_host_runtime_plan.md` pins Rust at stable
1.83 LTS.  Future Rust LTS bumps require workspace updates.

**Options.**

  - (a) **Pin minor version, bump quarterly.**  Stable
    cadence; some maintenance overhead.
  - (b) **Pin patch version, freeze.**  Maximum reproducibility;
    eventual incompatibility with new dependencies.
  - (c) **Track stable, no pin.**  Maximum flexibility; risk
    of CI breakage from upstream changes.

**Recommendation.**  (a).  Pin minor; bump on a quarterly
cadence aligned with Lean toolchain bumps.

**Status.**  OPEN.  Owner: Rust workstream lead.

---

### OQ-X-2 — Cross-stack fixture-corpus storage format

**Context.**  E-F shipped a Solidity-Lean cross-stack corpus.
RH and SC extend this to include Rust outputs and SMT cell
proofs.  The fixture format and versioning is informal.

**Options.**

  - (a) **CBE-encoded golden files in source.**  Current
    practice; simple but bloats the repo.
  - (b) **Out-of-tree corpus with content-hash pinning.**
    Build references a tarball with a SHA-256 pin; smaller
    repo but external dependency.
  - (c) **In-tree compressed corpus.**  zstd-compressed CBE;
    smaller than (a), no external dependency.

**Recommendation.**  (a) for ≤ 10 MB total; (c) for larger
corpora.  Cross-stack corpus is currently under 5 MB.

**Status.**  OPEN.  Owner: anyone landing a corpus expansion.

---

### OQ-X-3 — Multi-deployment shared infrastructure

**Context.**  The project supports many deployments
(`deploymentId`-distinguished).  Single-deployment-per-binary
is MVP.  Eventually a single binary or a multi-tenant `canon-host`
will serve multiple deployments.

**Options.**

  - (a) **Stay single-deployment.**  Operators run one binary
    per deployment.  Simplest.
  - (b) **Multi-tenant `canon-host`.**  One host process serves
    multiple `canon` subprocesses indexed by `deploymentId`.
  - (c) **Library-mode `canon`.**  Embed the kernel directly in
    a multi-tenant host; no subprocess.

**Trade-offs.**

  - (a): operational simplicity, resource overhead.
  - (b): resource efficiency, isolation question.
  - (c): tightest integration, biggest design change.

**Recommendation.**  (a) for v1.  (b) as a Phase 7-tier
follow-up if demand justifies.

**Status.**  OPEN.  Owner: project lead / operator team.

---

### OQ-X-4 — Project-wide use of `Mathlib`

**Context.**  CLAUDE.md explicitly forbids Mathlib in the TCB.
Non-TCB modules may import "if absolutely necessary, but the
default is Std core only".  No non-TCB module currently
imports Mathlib.

**Options.**

  - (a) **No Mathlib anywhere.**  Current state; preserved.
  - (b) **Mathlib in select non-TCB modules.**  E.g. EI helper
    lemmas that ride on `Mathlib.Data.Finset`.
  - (c) **Mathlib for tests only.**  Tests may use Mathlib
    convenience lemmas; production code may not.

**Trade-offs.**

  - (a): smallest dependency surface, slowest proof velocity
    for advanced math.
  - (b): risk of accidental TCB-coupling if reviewers slip.
  - (c): tests bloat; production stays clean.

**Recommendation.**  (a) until a specific non-TCB proof is
infeasible without Mathlib.  At that point, gate the addition
behind a §13.6 two-reviewer ratification.

**Status.**  OPEN by default; resolved (a) until challenged.

---

## §3 PA (Parameterized Laws) — forward-roadmap questions

Sources: `docs/parameterized_laws_plan.md` §14.2, audit catalog.

### OQ-PA-1 — Stake-weighted / token-weighted quorum

**Context.**  PA v1 uses equal-weight governance signers.
Real-world deployments may want token-weighted quorum.

**Options.**

  - (a) **Equal-weight only.**  v1 design.
  - (b) **Balance-snapshot-weighted.**  Weight signers by
    their resource-0 balance at proposal time.  Requires
    snapshot mechanism.
  - (c) **Delegated weight.**  Signers may delegate; weight
    flows transitively.

**Trade-offs.**

  - (a): trivially implementable, governance-capture risk.
  - (b): requires `getBalance @ time t` infrastructure;
    snapshot-game-ability concern.
  - (c): transitive delegation can mask actual control.

**Recommendation.**  (a) for v1.  (b) as PA-v2 follow-up when
a deployment requests it.

**Status.**  OPEN.  Owner: PA workstream lead.

---

### OQ-PA-2 — Two-stage propose-then-apply

**Context.**  PA v1 applies parameter changes immediately on
admission.  Some deployments want a "proposal queue" with
discussion period before activation.

**Options.**

  - (a) **Immediate application.**  v1.
  - (b) **Two-stage: propose → apply.**  Adds
    `Action.proposeParameterChange` and
    `Action.applyParameterChange`.
  - (c) **Three-stage: propose → ratify → apply.**  Adds an
    explicit ratification stage.

**Recommendation.**  (a) for v1.  (b) when demand justifies
the doubled action count.

**Status.**  OPEN.

---

### OQ-PA-3 — Delta-style parameter updates

**Context.**  PA v1 ships full-parameter-object updates.
A delta-style ("update only this field") variant saves wire
bytes.

**Options.**

  - (a) **Full-object only.**  v1.
  - (b) **Delta encoding additive.**  Both forms supported.

**Recommendation.**  (a).  Wire-byte savings are marginal at
1 governance action per epoch.

**Status.**  OPEN.

---

### OQ-PA-4 — Effective-at-block timelock

**Context.**  PA v1 changes parameters atomically.  Production
deployments may want a delay between admission and effect for
user-notice purposes.

**Options.**

  - (a) **No timelock.**  v1.
  - (b) **`pending : Option (Parameters × Block)` field.**
    Apply at the recorded block.

**Recommendation.**  (a) for v1.  (b) for v2.

**Status.**  OPEN.

---

### OQ-PA-5 — Per-resource parameter caps

**Context.**  v1 has a single `transferCap : Option Amount`.
Different resources may want different caps.

**Options.**

  - (a) **Single cap.**  v1.
  - (b) **`TreeMap ResourceId Amount` cap.**

**Recommendation.**  (a) until a deployment asks.

**Status.**  OPEN.

---

### OQ-PA-6 — Governance / LocalPolicy interaction

**Context.**  A governance signer with a restrictive LocalPolicy
could lock themselves out of governance.  PA v1 documents this
but does not enforce.

**Options.**

  - (a) **Document only.**  v1.
  - (b) **Mechanical enforcement: governance actions exempt
    from LocalPolicy.**  Matches LP's meta-action exemption.
  - (c) **Mechanical enforcement: governance LocalPolicies
    are vacuous.**  Stronger; eliminates the question.

**Recommendation.**  (a) for v1.  (b) for v2 alignment with LP.

**Status.**  OPEN.

---

### OQ-PA-7 — Dispute pipeline and parameter consumption

**Context.**  Disputes may reference parameters in scope at
filing time.  v1 documents this as "out of scope per PA
design".

**Options.**

  - (a) **Parameter-aware verdicts.**  Verdicts re-evaluate
    using parameters at filing time.
  - (b) **Snapshot at filing.**  Filing captures the current
    parameters; the dispute uses that snapshot.
  - (c) **Latest parameters apply.**  Verdicts always use the
    *current* parameters.

**Recommendation.**  (b).  Captures the user's intent at
filing time; immune to mid-dispute parameter changes.

**Status.**  OPEN.

---

### OQ-PA-8 — Parameter migration across `CanonMigration`

**Context.**  When a chain forks via `CanonMigration`, what
happens to the parameter state?

**Options.**

  - (a) **Inherit.**  Successor uses predecessor's parameters
    until explicitly changed.
  - (b) **Reset.**  Successor starts with defaults.
  - (c) **Explicit migration sequence.**  Deployment supplies
    a parameter-migration function.

**Recommendation.**  (a) by default; (c) available for
deployments that want a reset.

**Status.**  OPEN.

---

## §4 LP (Actor-Scoped Policies) — open questions

Sources: `docs/actor_scoped_policies_plan.md` §13.2.

### OQ-LP-1 — `expireAtNonce` clause

**Context.**  LP v1 supports `denyTag`, `requireRecipient`,
`capAmount`.  An `expireAtNonce N` clause would auto-disable
the policy after N actions by the actor.  Requires recursive
wrapper; v1 deferred.

**Options.**

  - (a) **No expiration.**  v1.  Policies are revoke-only.
  - (b) **`expireAtNonce` recursive wrapper.**

**Recommendation.**  (a) until a real user asks.

**Status.**  OPEN.

---

### OQ-LP-2 — Disjunction of clauses (`anyOf`)

**Context.**  LP v1 is per-clause-AND.  An `anyOf` constructor
would give full boolean expressivity.

**Options.**

  - (a) **AND-only.**  v1.
  - (b) **`anyOf` recursive clause variant.**

**Recommendation.**  (a) for v1.  (b) for v2 if a deployment
requests it.

**Status.**  OPEN.

---

### OQ-LP-3 — Cross-actor policies (delegation / authz)

**Context.**  LP v1 lets actor A constrain A's own outgoing
actions.  Cross-actor authz (e.g. Cosmos `authz` module)
is a different concern.

**Options.**

  - (a) **No cross-actor policies.**  v1; out-of-scope.
  - (b) **Cross-actor authz as a separate workstream.**
    Possibly Phase 7.A (Capabilities) overlap.

**Recommendation.**  (a).  Cross-actor delegation is
capabilities territory (Phase 7.A), not LP.

**Status.**  RESOLVED in favour of (a); cross-reference Phase
7.A.

---

### OQ-LP-4 — Policy versioning

**Context.**  Policies have no version field.  A deployment
might want to enforce "minimum policy version N".

**Options.**

  - (a) **No versioning.**  v1.
  - (b) **`version : Nat` field on `LocalPolicy`.**

**Recommendation.**  (a) until requested.  Trivially additive.

**Status.**  OPEN.

---

### OQ-LP-5 — Policy commitments / hashes

**Context.**  Policies are stored full-text on-chain.  A
space-efficient alternative: store `hash(policy)`; provide the
full policy on revoke.

**Options.**

  - (a) **Full storage.**  v1.
  - (b) **Hash commitments.**  Saves on-chain bytes; auditor
    visibility trade-off.

**Recommendation.**  (a).  Policies are small (typically <
1 KB); savings marginal.

**Status.**  OPEN.

---

### OQ-LP-6 — Solidity-side LP mirror

**Context.**  LP is Lean-only.  L1 contracts could mirror the
policy check for L1-visible audit.

**Options.**

  - (a) **No L1 mirror.**  Operators audit policy off-chain.
  - (b) **L1 mirror as future Workstream-E follow-up.**

**Recommendation.**  (b) when an Ethereum deployment requests
it.

**Status.**  OPEN.  Owner: Workstream-E follow-up.

---

## §5 LX (Lex language) — v2 / v3 design questions

Sources: `docs/law_language_design.md` §14, audit catalog.

### OQ-LX-1 — Refinement direction policy

**Context.**  v1 admits only `pre` strengthening across
versions.  v2 may admit weakening under opt-in.

**Options.**

  - (a) **Strengthening only.**  v1.
  - (b) **Weakening allowed under `@weakening_allowed`.**
    v2 / LX2.1.

**Recommendation.**  (b) in v2 with `lex_diff` flagging.

**Status.**  OPEN until LX2.1 lands.

---

### OQ-LX-2 — In-flight signed actions across amendments

**Context.**  When a deployment amends a law, what happens
to signed actions in-flight (signed under the old law's
admissibility)?

**Options.**

  - (a) **Reject.**  Old actions become inadmissible
    immediately.
  - (b) **Accept under old law for one epoch.**
  - (c) **Deployment chooses.**  Each amendment specifies
    behaviour.

**Recommendation.**  (c).  Deployment-level policy.

**Status.**  OPEN.

---

### OQ-LX-3 — Cross-law invariant synthesis

**Context.**  v3 may synthesize cross-law invariants
("no two laws grant minting authority").  N² scaling.

**Options.**

  - (a) **No cross-law invariants.**  v1 / v2.
  - (b) **Limited cross-law (mint authority only).**
  - (c) **Full cross-law (arbitrary user-supplied
    predicates).**

**Recommendation.**  (a) until v3 establishes a clear use
case.

**Status.**  OPEN until LX3.5.

---

### OQ-LX-4 — Property-test seed reproducibility

**Context.**  v1 property tests use a non-reproducible seed.

**Options.**

  - (a) **No seed reproducibility.**  v1.
  - (b) **Seed printed and replayable.**  v3 / LX3.6.

**Recommendation.**  (b).

**Status.**  OPEN until LX3.6.

---

### OQ-LX-5 — Deployment-ID derivation sub-language

**Context.**  v1 hard-codes `deploymentId`.  v2 / LX2.3 may
introduce a derivation language.

**Options.**

  - (a) **Hard-coded.**  v1.
  - (b) **Derivation function.**  v2.

**Recommendation.**  (b) in v2; derivation function is small.

**Status.**  OPEN until LX2.3.

---

### OQ-LX-6 — Resource-role wrappers (typed-flow enforcement)

**Context.**  v3 / LX3.1 introduces `Roled ρ` phantom-typed
wrappers.

**Options.**

  - (a) **Untyped flat `ResourceId`.**  v1.
  - (b) **Phantom-typed wrappers; opt-in per law.**  v3.
  - (c) **Phantom-typed wrappers; mandatory across all laws.**
    Most disruptive; rejects existing flat-resource laws.

**Recommendation.**  (b) in v3.

**Status.**  OPEN until LX3.1.

---

### OQ-LX-7 — LSP integration scope

**Context.**  v3 / LX3.2.  How much LSP functionality is in scope?

**Options.**

  - (a) **Error squiggles only.**  Cheapest.
  - (b) **Squiggles + hovers + go-to-impl.**  Recommended.
  - (c) **Full IDE support: refactorings, completions,
    code actions.**  Expensive.

**Recommendation.**  (b).

**Status.**  OPEN until LX3.2.

---

### OQ-LX-8 — `Action.revokeKey` kernel addition

**Context.**  v3 / LX3.3.  Kernel amendment requires §13.6
two-reviewer rule.

**Options.**

  - (a) **No `revokeKey`.**  v1.  Workaround: `replaceKey`
    with a known-burnt key.
  - (b) **Ship `Action.revokeKey`.**  v3.

**Recommendation.**  (b).  `replaceKey`-with-burnt-key is
fragile.

**Status.**  OPEN until LX3.3 begins.

---

### OQ-LX-9 — Signer-identity strengthening lift to kernel

**Context.**  v1 ships a shim-layer signer-identity check.
v2 / LX2.5 may lift to the kernel.

**Options.**

  - (a) **Shim only.**  v1 / v2.
  - (b) **Kernel-level lift.**  Triggers §13.6 two-reviewer.

**Recommendation.**  (a).  Shim is sufficient; kernel touch
adds risk.

**Status.**  OPEN until LX2.5.

---

## §6 Workstream H (Fault-Proof) — open questions

### OQ-H-1 — SMT cell-proof scheme variants

**Context.**  `smt_cell_proofs_plan.md` specifies a depth-256
SMT.  Alternative: depth-bounded by actual key range.

**Options.**

  - (a) **Depth 256 (uniform).**
  - (b) **Depth-bounded by max-key.**  Smaller proofs, more
    complex verifier.

**Recommendation.**  (a).  Uniform depth simplifies the
verifier.

**Status.**  RESOLVED in favour of (a); see SC.1.

---

### OQ-H-2 — Multi-sequencer support (OQ3, deferred)

**Context.**  Single-sequencer is MVP.  Multi-sequencer
(round-robin or permissionless) is a deployment-level scaling
question.

**Options.**

  - (a) **Single-sequencer.**  MVP.
  - (b) **Round-robin among configured set.**
  - (c) **Permissionless sequencing (with cryptoeconomic
    backing).**

**Recommendation.**  (a) for MVP.  (b) when demand justifies.

**Status.**  OPEN.

---

### OQ-H-3 — ZK Phase 3 timing

**Context.**  Workstream H ships optimistic disputes; Phase 3
ZK validity proofs are a separate workstream.

**Options.**

  - (a) **No ZK.**  Stay optimistic.
  - (b) **Add ZK alongside optimistic.**  Hybrid.
  - (c) **Replace optimistic with ZK.**  Long-horizon.

**Recommendation.**  (a) for v1.  (b) once Phase 7.C ships
production-grade SNARK infrastructure.

**Status.**  OPEN.

---

### OQ-H-4 — L1AttestationSemantics deployment model

**Context.**  CLAUDE.md footnote 2: the
`faultProof_challenger_won_implies_state_root_wrong` theorem
relies on `L1AttestationSemantics` (a deployment-level
assumption).  Today: cross-stack corpus ratifies operationally.

**Options.**

  - (a) **Operational ratification only.**  Current state.
  - (b) **Mechanical L1-side verifier soundness theorem.**
    Promotes the assumption to a proven property over the
    Solidity contract source.

**Recommendation.**  (a) for v1.  (b) is a longer-term
research project (Solidity verification).

**Status.**  OPEN.

---

## §7 Phase 7 — portfolio prioritisation questions

Phase 7 is a portfolio.  Each sub-workstream's "should we ship"
question is itself an open question.

### OQ-P7-1 — Which Phase 7 sub-workstreams to prioritise

**Context.**  Phase 7 has seven sub-workstreams (P7.A – P7.G).
Resources rarely allow all seven.

**Options.**  Any 2–3 of P7.A – P7.G per release cycle.

**Recommendation.**  Demand-driven.  P7.A (Capabilities) and
P7.F (Schema migration) are recommended first by
`phase_7_plan.md` §4 due to low risk and high demand pattern.

**Status.**  OPEN.  Owner: project lead.

---

### OQ-P7-2 — Capability-Threshold-signature interaction

**Context.**  P7.A (Capabilities) and P7.B (Threshold sigs)
overlap conceptually: a capability with a threshold-signature
issuance.  Should P7.A subsume P7.B?

**Options.**

  - (a) **Independent workstreams.**  Land separately.
  - (b) **Capabilities subsume threshold sigs.**  P7.A's
    `issuerSig` slot accepts a threshold-aggregated signature.
  - (c) **Composable: capabilities + threshold sigs as
    orthogonal extensions.**

**Recommendation.**  (c).  Both ship; the user composes them
per deployment need.

**Status.**  OPEN.

---

### OQ-P7-3 — Cross-shard atomicity model

**Context.**  P7.E (Cross-shard) requires a 2PC-like atomicity
protocol.  Coordinator-based vs coordinator-free.

**Options.**

  - (a) **Coordinator-based 2PC.**
  - (b) **Coordinator-free (Paxos / Raft on the commit set).**

**Recommendation.**  (a).  Simpler; the coordinator is itself
a `canon` instance with its own log.

**Status.**  OPEN until P7.E begins.

---

## §8 Documentation / process questions

### OQ-DOC-1 — `kernelBuildTag` bump cadence

**Context.**  AR.22 set the tag to `canon-audit-remediation`.
Future major workstream landings (EI, RH, SC, WG, CA, PA, P7)
will each want to bump.

**Options.**

  - (a) **Bump per workstream landing.**
  - (b) **Bump per release cycle (semver).**
  - (c) **No bump; remove the tag.**

**Recommendation.**  (a).  Each workstream's PR includes the
bump; `Test/Umbrella.lean` regression test enforces.

**Status.**  RESOLVED in favour of (a).

---

### OQ-DOC-2 — Single canonical "Headline theorems" location

**Context.**  README has a list; CLAUDE.md has a fuller table;
some plan docs have their own headline-theorem subsections.

**Options.**

  - (a) **CLAUDE.md canonical; README and plans cross-
    reference.**
  - (b) **Multiple sources, accept drift.**

**Recommendation.**  (a).

**Status.**  RESOLVED in favour of (a) (per CLAUDE.md
documentation rules).

---

### OQ-DOC-3 — `Test/Umbrella.lean` build-tag pin lift

**Context.**  Currently `Test/Umbrella.lean` pins
`kernelBuildTag` in a regression test.  This means a bump must
update both the constant and the test in the same PR.

**Options.**

  - (a) **Keep the pin.**  v1.
  - (b) **Remove the pin (rely on review discipline).**

**Recommendation.**  (a).  The pin is a forcing function.

**Status.**  RESOLVED in favour of (a).

---

### OQ-DOC-4 — `audits/19-findings-and-followups.md` post-AR refresh

**Context.**  The synthesis doc's "Open follow-ups" section
predates AR remediation.  Should it be regenerated, annotated,
or left as a historical record?

**Options.**

  - (a) **Annotate in place.**  Add an "as of audit date"
    header; strike closed items.
  - (b) **Full rewrite.**  Regenerate from current state.
  - (c) **Add a new doc.**  Leave old doc historical; new doc
    tracks current state.

**Recommendation.**  (a).  Lightest touch; preserves audit
trail.  This is the recommended approach in
`cleanup_and_consolidation_plan.md` CL.1.

**Status.**  OPEN until CL.1 lands.

---

## §9 Resolved questions (historical record)

Resolved questions stay here for traceability.  Each carries
the original context, options, resolution, and the workstream /
PR that ratified it.

(Move questions here once resolved.  Currently empty: the
audit identified them today; resolutions will accrue over
time.)

---

## §10 References

  * `docs/encoder_injectivity_plan.md`
  * `docs/rust_host_runtime_plan.md`
  * `docs/smt_cell_proofs_plan.md`
  * `docs/ethereum_workstream_g_plan.md`
  * `docs/chain_level_accounting_plan.md`
  * `docs/parameterized_laws_landing_plan.md`
  * `docs/phase_7_plan.md`
  * `docs/lex_v2_v3_roadmap_plan.md`
  * `docs/cleanup_and_consolidation_plan.md`
  * `docs/GENESIS_PLAN.md`
  * `docs/audit_remediation_plan.md`

---

**End of document.**  This registry is *living*: every PR that
makes a design decision should update this file in the same
landing.  Decisions left implicit are decisions left
unauditable.
