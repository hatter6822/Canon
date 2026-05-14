<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

# Ethereum Integration — Workstream G (Documentation + Amendment)

This document plans Workstream E-G, the documentation amendment
that ratifies Workstreams E-A through E-F (Ethereum integration)
into the project's canonical design documents.

E-G is currently the **only "Not started" workstream** in the
project's roadmap (per CLAUDE.md status table).  The Lean and
Solidity code shipped in E-A through E-F is complete; this
workstream's job is to surface that work in `GENESIS_PLAN.md`,
`README.md`, `CLAUDE.md`, `docs/abi.md`, `docs/extraction_notes.md`,
and `docs/std_dependencies.md`.

E-G is pure documentation; there are no code changes.  However,
because it amends `GENESIS_PLAN.md`, the **§14.4 two-reviewer
Genesis-Plan-amendment rule** applies.

## Status

  * **Workstream prefix:** `WG` (Workstream G).  Five sub-units:
    - **WG.1** GENESIS_PLAN amendment (new chapter §15).
    - **WG.2** README + CLAUDE.md status updates.
    - **WG.3** ABI document additions (new §12).
    - **WG.4** Extraction notes update (new §2 entries).
    - **WG.5** Std-dependency audit refresh.
  * **Effort estimate:** 8–14 engineer-days for one engineer
    familiar with the Ethereum workstream.
  * **Two-reviewer requirement:** WG.1 and WG.5 (anything that
    amends GENESIS_PLAN.md or `tcb_allowlist.txt` /
    `docs/std_dependencies.md`).
  * **Build-posture target:** all existing CI gates green.  No
    `.lean` or `.sol` source changes, so source builds are
    unchanged.  The `deferral_audit` may surface previously-
    invisible "deferred" claims if any sub-unit accidentally
    leaves a "deferred" phrase in its prose; the audit runs over
    docs/ only via its existing scope rule.

## Table of contents

  * §1 Goals and non-goals
  * §2 Background
  * §3 Work-unit dependencies
  * §4 Work-unit specifications (WG.1 – WG.5)
  * §5 Sequencing and PR structure
  * §6 Quality gates
  * §7 Risk register
  * §8 Acceptance criteria
  * §9 Out-of-scope items
  * §10 References

## §1 Goals and non-goals

### §1.1 Goals

  1. **Ratify the Ethereum integration into the Genesis Plan.**
    A new chapter §15 documents the deployment scenario, trust
    assumptions, action/event extensions, bridge accounting
    equation, dispute pipeline integration, and the full
    architecture.
  2. **Synchronise top-level documents.**  README, CLAUDE.md,
    `abi.md`, `extraction_notes.md`, and `std_dependencies.md`
    all carry references to the Ethereum surfaces; ensure they
    are consistent.
  3. **Document trust assumptions.**  EUF-CMA on secp256k1,
    collision-resistance of keccak256, L1 finality
    assumptions, Solidity-side soundness, EIP-1271 correctness
    — each gets a named entry in `extraction_notes.md`.
  4. **Audit `tcb_allowlist.txt`.**  The bridge modules added
    Std imports; WG.5 verifies the allowlist matches the
    realised import set and that `tcb_audit` is green.
  5. **Zero source change.**  No `.lean`, `.sol`, or `.rs` file
    changes (except possibly tiny docstring tweaks to cite the
    new GENESIS_PLAN sections).

### §1.2 Non-goals

  1. **No new theorems.**  The integration's correctness is
    already proven in E-A through E-F.  WG documents it.
  2. **No retroactive design change.**  The wire formats, ABI,
    and trust model are what they are; WG records them.
  3. **No Rust integration documentation.**  WG is about Lean +
    Solidity.  Rust ports are documented in the
    `rust_host_runtime_plan.md` follow-on.
  4. **No `solidity/README.md` rewrite.**  That document is
    operator-facing and lives separately; WG adds cross-references
    if needed but does not own its content.

### §1.3 Reading guide

  * **Implementer:** WG.1 first (the substantive amendment),
    then WG.3 (ABI), then WG.2 / WG.4 / WG.5 in any order.
  * **Reviewer:** check cross-document consistency at landing
    time.  The reviewer-checklist for each sub-unit lists
    specific consistency invariants.

### §1.4 Glossary

  * **Genesis Plan §X.**  A specific section of
    `docs/GENESIS_PLAN.md`.  WG.1 introduces a new chapter §15
    "Ethereum Integration" (distinct from the existing §15B
    "Fault-Proof Migration" — both numbered §15 but addressed by
    sub-section).  **NOTE for the implementer:** before landing
    WG.1, verify whether the existing §15B numbering must shift
    (e.g. rename §15B to §16) to make room for the new §15.
    The project's history may already accommodate the new §15;
    grep the document during WG.1's first-day audit.
  * **Trust assumption.**  A property of an external (non-Lean)
    component that some Lean theorem's conclusion depends on.
    Documented in `extraction_notes.md` §2.

## §2 Background

The Ethereum workstreams shipped:

  * **E-A** (cryptographic adaptors): ECDSA-secp256k1 +
    keccak256 swap-points (Lean side).
  * **E-B** (identity + authority): bridge actor signing,
    EIP-1271 verification.
  * **E-C** (bridge laws): `deposit` / `withdraw` admissibility
    laws with chain-level accounting deltas.
  * **E-D** (withdrawal proofs): sparse-Merkle-tree withdrawal
    proofs with `verifyProof_complete` / `verifyProof_sound`
    theorems.
  * **E-E** (Solidity contracts): 10 contracts, 5 libraries.
  * **E-F** (cross-stack verification): byte-equivalence
    fixture corpus.

Each workstream has its own plan and audit history.  WG ties
them together into a single coherent narrative in the project's
canonical documents.

## §3 Work-unit dependencies

```
WG.1 (GENESIS_PLAN §15) ──► WG.3 (abi.md §12)
                       └──► WG.4 (extraction_notes.md §2)
                       └──► WG.2 (README + CLAUDE.md)
                       └──► WG.5 (std_dependencies + tcb_allowlist)
```

WG.1 ships the substantive content.  WG.2 – WG.5 are
downstream consistency updates.

## §4 Work-unit specifications

---

### WG.1 — Genesis Plan amendment: new chapter §15 "Ethereum Integration"

**Finding map.**  E-G primary deliverable.

**Scope.**  `docs/GENESIS_PLAN.md` only.  Net additions
~1500–2500 lines.  The amendment requires two reviewers per
§14.4 of the existing Genesis Plan.

**Implementation steps.**

  1. **Pre-audit** (day 1).  Read GENESIS_PLAN.md end-to-end
    to identify all existing Ethereum-touching references
    (search: "Ethereum", "bridge", "L1", "secp256k1",
    "keccak256", "EIP-1271", "EIP-712", "withdrawal proof").
    Map each to a destination section in the new §15.
  2. **Decide the chapter number.**  Either:
     (a) Append §15 as the next top-level chapter (if §14 is
       the last existing chapter and §15B is a sub-section of
       a different chapter that historically used the §15B
       label informally), or
     (b) Insert §15 and renumber §15B → §16 (more disruptive;
       requires updating every cross-reference).
    The implementer should choose (a) unless §15B is already
    a top-level chapter, in which case (b).
  3. **Draft §15** (days 2–7).  Sections:
     - **§15.1 Deployment scenario.**  L1 + L2 + bridge model;
       single-sequencer baseline; off-chain observer; dispute
       game.
     - **§15.2 Trust assumptions.**  EUF-CMA, keccak256
       collision-resistance, L1 finality, Solidity correctness,
       EIP-1271 correctness.  Each with its rationale and the
       Lean theorems that depend on it.
     - **§15.3 Action and Event extensions.**  The 6+ new
       `Action` constructors (`deposit`, `withdraw`, etc.) and
       6+ new `Event` constructors.  Frozen-index table.
     - **§15.4 Bridge state and accounting equation.**  The
       chain-level identities and the per-action delta theorems.
       Cross-reference to `chain_level_accounting_plan.md` for
       the deferred inductive lift.
     - **§15.5 Withdrawal-proof scheme.**  SMT depth-64
       construction; `verifyProof_complete` / `verifyProof_sound`
       theorems.
     - **§15.6 Dispute-pipeline integration.**  Bridge laws
       under disputes; verdict semantics.
     - **§15.7 EIP-712 signing surface.**  Domain separator,
       struct hashes, signature normalisation.
     - **§15.8 Solidity contract surface.**  10 contracts + 5
       libraries; immutability discipline; no admin / pausable.
     - **§15.9 Cross-stack verification corpus.**  E-F design.
     - **§15.10 Non-goals and v2 deferrals.**  Inherits the
       `ethereum_integration_plan.md` §2.2 list verbatim with
       cross-references.
  4. **Cross-reference every existing GENESIS_PLAN section** in
    the new §15 (e.g. §4.x laws, §6.x type-level firewalls).
  5. **Update the GENESIS_PLAN table of contents** at the top
    of the document.

**Acceptance criteria.**

  * §15 chapter lands; structure as above.
  * Two reviewers sign off (Genesis Plan amendment rule).
  * No `deferred to follow-up` or other forbidden phrases per
    `deferral_audit` (the audit doesn't scan `.md` files in
    `docs/` today, but the prose should still avoid the markers
    on principle).
  * Every cross-reference (file:line or §N.M) actually resolves
    on a follow-up read.

**Reviewer checklist.**

  * Trust assumptions match `extraction_notes.md` (WG.4).
  * Frozen-index table matches the actual `Action` /
    `Event.tag` regression tests (AR.5 / AR.6).
  * Headline theorems mentioned (e.g.
    `verifyProof_complete`) match actual file:line in source.
  * No PR / session URL slip-throughs (CLAUDE.md
    "Pull-request authoring policy" applies in spirit to
    documentation prose too).
  * Two reviewers explicitly named in the PR.

**Risk.**  Medium-low.  Long write; easy to introduce
inconsistency.

**Effort.**  ~5–7 engineer-days.

---

### WG.2 — README + CLAUDE.md status updates

**Finding map.**  E-G consistency deliverable.

**Scope.**  `README.md`, `CLAUDE.md`.

**Implementation steps.**

  1. **README.md updates:**
     - "Phase and workstream status" table: add explicit "E-G"
       row showing "Complete".
     - "How correctness is enforced" section: cite the new
       GENESIS_PLAN §15.
     - "Headline theorems" table: ensure every Ethereum
       headline theorem is listed (cross-check against the
       §15 amendment).
     - Bump README's build-tag display to match current
       `LegalKernel.lean:285`.  As of audit date, README shows
       `canon-fault-proof-migration` but the code has
       `canon-audit-remediation`; WG.2 must update this
       (separate from any future EI build-tag bump).
     - Update test count if drifted significantly.
  2. **CLAUDE.md updates:**
     - "Phase and workstream status" sub-table: E-G from "Not
       started" to "Complete".
     - "Documentation rules" section: keep canonical
       ownership pointing to GENESIS_PLAN.md §15.
     - Update "Current development status" if any new
       deferrals or open items were introduced (none expected;
       WG is a documentation pass).

**Acceptance criteria.**

  * README build-tag matches `LegalKernel.lean:285`.
  * CLAUDE.md E-G row says "Complete".
  * Both files reference GENESIS_PLAN §15.
  * No session URLs / process tokens in the prose.

**Reviewer checklist.**

  * Build tag in README equals `kernelBuildTag` in
    `LegalKernel.lean:285`.
  * CLAUDE.md phase table fully consistent with README.
  * No phantom references to closed deferrals.

**Risk.**  Low.

**Effort.**  ~1 engineer-day.

---

### WG.3 — ABI document: new §12 "Ethereum ABI surfaces"

**Finding map.**  E-G ABI documentation.

**Scope.**  `docs/abi.md`.

**Implementation steps.**

  1. Append §12 with sub-sections:
     - **§12.1 Action constructor encodings** (indices 12–14;
       confirm via `Encoding/Action.lean` and AR.5 regression
       tests).
     - **§12.2 Event constructor encodings** (indices 9–10).
     - **§12.3 BridgeState CBE.**
     - **§12.4 PendingWithdrawal CBE.**
     - **§12.5 WithdrawalProof CBE.**
     - **§12.6 Bridge-actor ActorId 0 reservation.**
     - **§12.7 keccak256 trailer format.**
     - **§12.8 Contract event ABIs** (Solidity-emitted events
       with their Lean `Event` translation).
  2. Cross-reference §12 from GENESIS_PLAN §15 and from
    `solidity/README.md`.

**Acceptance criteria.**

  * All Ethereum-relevant ABIs documented.
  * Constructor indices match the AR.5 / AR.6 regression
    fixtures.
  * Solidity event ABIs match `solidity/src/contracts/*.sol`.

**Reviewer checklist.**

  * Cross-stack equivalence implied by the ABI is reflected
    in the E-F fixture corpus.
  * No phantom constructors (every index has a corresponding
    `Action` / `Event` variant).

**Risk.**  Low.

**Effort.**  ~2 engineer-days.

---

### WG.4 — Extraction notes: new trust assumptions

**Finding map.**  E-G trust assumption catalogue.

**Scope.**  `docs/extraction_notes.md` §2.

**Implementation steps.**

  1. For each of the five Ethereum trust assumptions, add a
    `trust_assumption_X.Y` block:
     - **TA-2.1 EUF-CMA secp256k1.**  Used by `Verify` opaque
       in deployments that select secp256k1.  Runtime adaptor:
       `runtime/canon-verify-secp256k1`.
     - **TA-2.2 keccak256 collision-resistance.**  Used by
       `hashBytes` in Ethereum deployments.  Runtime adaptor:
       `runtime/canon-hash-keccak256`.
     - **TA-2.3 L1 finality.**  Used by withdrawal-proof
       finalisation (`isFinalised_monotonic_in_currentBlock`).
       12-block confirmation depth is the deployment default.
     - **TA-2.4 Solidity correctness.**  The cross-stack
       fixture corpus is the operational defence; pin the
       solidity compiler version.
     - **TA-2.5 EIP-1271 correctness.**  Used by smart-contract
       wallet support; the verifier delegates to the wallet's
       `isValidSignature` callback.
  2. Update the trust-assumption summary at the top of
    `extraction_notes.md`.

**Acceptance criteria.**

  * Five new TA entries.
  * Cross-references to the relevant Lean theorems and Rust
    adaptor crates.
  * Each TA names its specific Lean opaque / @[extern]
    swap-point.

**Reviewer checklist.**

  * No duplication with the existing §1 trust assumptions
    (Verify, hashBytes).
  * Each TA's deployment-scope is precise.

**Risk.**  Low.

**Effort.**  ~1–2 engineer-days.

---

### WG.5 — Std-dependency audit refresh + `tcb_allowlist.txt`

**Finding map.**  E-G TCB-import audit.

**Scope.**  `docs/std_dependencies.md`, `tcb_allowlist.txt`.

**Implementation steps.**

  1. Re-run `lake exe tcb_audit` and capture the import set.
  2. Compare against `tcb_allowlist.txt`.  Any bridge-module
    imports not on the allowlist must either:
     (a) be added to the allowlist (with reviewer sign-off; this
       expands the TCB surface), or
     (b) be replaced by a non-TCB equivalent.
  3. Update `docs/std_dependencies.md` with any new
    Std-library lemmas the bridge modules consume.
  4. Audit the `Tools.Common.tcbInternalImports` enumeration
    in `Tools/Common.lean`: each entry should still be a TCB-
    core module.

**Acceptance criteria.**

  * `lake exe tcb_audit` is green.
  * `docs/std_dependencies.md` lists every Std lemma the TCB
    consumes (no orphaned entries).
  * No new `tcb_allowlist.txt` entries unless reviewer-
    justified.

**Reviewer checklist.**

  * Each allowlist addition (if any) is documented in the PR
    body.
  * `std_dependencies.md` is byte-stable across re-audit (no
    drift due to formatting).
  * Two reviewers if `tcb_allowlist.txt` is changed.

**Risk.**  Low-medium.  An allowlist change is a TCB-touching
event and triggers the two-reviewer gate even though no `.lean`
file in the TCB-core is touched.

**Effort.**  ~1 engineer-day.

---

## §5 Sequencing and PR structure

```
PR-1 (WG.1)        Genesis Plan §15 amendment              (2 reviewers)
PR-2 (WG.3)        abi.md §12                              (1 reviewer)
PR-3 (WG.4)        extraction_notes §2                     (1 reviewer)
PR-4 (WG.2)        README + CLAUDE.md                      (1 reviewer)
PR-5 (WG.5)        tcb_allowlist + std_dependencies        (2 reviewers if allowlist changes)
```

WG.1 first (substantive content); the others reference it.

## §6 Quality gates

  * `lake build` and `lake test` remain green (no source
    change expected).
  * `lake exe tcb_audit` green (WG.5).
  * `lake exe deferral_audit` green (no new forbidden phrases
    introduced in `.lean` files; the audit doesn't scan `.md`
    files but `.lean` docstrings may be edited).
  * For WG.1 + WG.5: two reviewers per §14.4 / §13.6.

## §7 Risk register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| GENESIS_PLAN §15 chapter conflicts with existing §15B label | High | Medium | Pre-audit (WG.1 step 1); explicitly choose append vs renumber |
| Cross-references to file:line drift after a future PR | Medium | Low | Use section identifiers (§15.5) instead of line numbers where possible |
| Two-reviewer rule slips for WG.1 | Low | High | PR title must say "Genesis Plan amendment"; CODEOWNERS will request the second reviewer |
| WG.5 surfaces an un-allowlisted bridge import | Medium | Medium | Either justify the addition or refactor; WG.5 is the right place to find this |
| WG.2 misses the stale README build-tag (separate from any later EI bump) | Medium | Low | Verification step: `grep kernelBuildTag README.md` matches `LegalKernel.lean:285` |

## §8 Acceptance criteria

WG is **complete** when:

  1. GENESIS_PLAN.md ships chapter §15 covering the eleven
    sub-sections of §15 above; two reviewers signed off.
  2. README.md and CLAUDE.md show "E-G | complete" in the phase
    status table.
  3. README.md build-tag matches `LegalKernel.lean:285`.
  4. `docs/abi.md` §12 is complete with all Ethereum surfaces.
  5. `docs/extraction_notes.md` §2 documents the five
    Ethereum trust assumptions.
  6. `docs/std_dependencies.md` is current; `tcb_allowlist.txt`
    is current; `lake exe tcb_audit` is green.
  7. The CLAUDE.md "Phase and workstream status" section moves
    E-G from "Not started" to "Complete".

## §9 Out-of-scope items

  * **Genesis Plan §15B "Fault-Proof Migration" rewrite.**
    Already shipped; WG does not re-audit.
  * **Rust integration documentation.**  Owned by
    `rust_host_runtime_plan.md`.
  * **`solidity/README.md` rewrite.**  Operator-facing
    documentation, owned separately.
  * **EIP-1271 v2 (recursive cross-contract auth).**  Out of
    scope for the v1 documentation; v2 specifics are a future
    workstream.
  * **Deployment runbooks for the bridge.**  Operator team.

## §10 References

  * `docs/ethereum_integration_plan.md` — the per-workstream
    plan that E-A through E-F implemented.
  * `docs/audits/08-bridge.md` — audit notes for the bridge
    modules.
  * `LegalKernel/Bridge/*.lean` — Lean bridge surfaces.
  * `solidity/src/contracts/*.sol` — Solidity bridge surfaces.

---

**End of plan.**  Landing WG retires the project's only
"Not started" workstream and produces a single canonical
narrative for the Ethereum integration.
