<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

# Deferred Work — Master Index

This document is the navigator for the nine deferred-work
planning documents authored after the 2026-05-14 comprehensive
audit of deferred work.  It captures the dependency graph
between the workstreams, the recommended landing order, the
total effort estimate, and the connection points to the open-
questions registry.

## Workstream catalogue

| Plan | Workstream | Effort | Status | Dependencies |
|------|-----------|--------|--------|--------------|
| `encoder_injectivity_plan.md` | EI — 8 sub-units; map-backed sub-state encoder injectivity | ~9–16 days | residual proof debt; retires CLAUDE.md footnote 1 | independent (Lean-only) |
| `rust_host_runtime_plan.md` | RH — 8 sub-streams; Phase 5 + E-A + E-B + H.10.5 Rust | ~14–22 wks | the largest workstream; interop deliverables | independent (Rust-only) |
| `smt_cell_proofs_plan.md` | SC — 3 sub-units; cross-stack soundness for cell proofs | ~6–9 wks | closes the only documented soundness gap | independent of EI (uses the same `CollisionFree hashBytes` predicate) |
| `ethereum_workstream_g_plan.md` | WG — 5 sub-units; E-G documentation amendment | ~8–14 days | the only "Not started" workstream | independent (documentation) |
| `chain_level_accounting_plan.md` | CA — 3 sub-units; §7.6.4 / §7.6.5 inductive promotion | ~5–8 days | retires m-16, the only AR "Defer / n/a" finding | independent (Lean-only) |
| `parameterized_laws_landing_plan.md` | PA — 12 WUs; land the drafted parameter substrate | ~6–10 wks | already drafted in `parameterized_laws_plan.md` | benefits from EI; not strictly blocking |
| `phase_7_plan.md` | P7 — 7 sub-workstreams (A–G); advanced capabilities | 20+ wks (open-ended) | menu workstream; pick sub-workstreams per release | varies; see plan §4 |
| `lex_v2_v3_roadmap_plan.md` | LX2 / LX3 — 13 items; Lex v2 + v3 evolution | ~25 wks total | forward-roadmap; demand-driven | LX3.3 triggers kernel amendment |
| `cleanup_and_consolidation_plan.md` | CL — 5 sub-units; documentation + visibility tidy-up | ~4–8 days | the project's "tidy-up" PR sequence | CL.4 depends on EI.8 |
| `open_questions.md` | (registry) | n/a | living design-decision document | referenced by every plan |

## Dependency graph

```
            EI (encoder injectivity)
              │
              │ EI.8 closes footnote 1 + lifts
              │ AR.23 to "Complete" status
              ▼
            CL.4 (AR.23 lift; awaits EI.8)
              ▲
            CL.1, CL.2, CL.3, CL.5 (parallel; no EI dependency)


            CA (chain-level accounting)            independent


            SC (SMT cell proofs)                   independent


            WG (E-G documentation)                 independent


            PA (parameterized laws landing)        independent
              │
              │ PA encoder injectivity follows EI's template
              │ (parameter substrate encoder); not blocking
              ▼

            LX2 / LX3 (Lex roadmap)
              │
              │ LX3.3 (Action.revokeKey) is a kernel touch;
              │ §13.6 two-reviewer rule + Genesis-Plan amendment
              ▼
            kernel TCB delta (only if LX3.3 lands)


            RH (Rust host runtime)
              │
              │ Closes Phase 5 WUs 5.4 / 5.7 / 5.8 / 5.11;
              │ closes E-A / E-B Rust crates;
              │ closes Workstream H WU H.10.5 (observer);
              │ RH-A.1 / RH-A.2 swap-points work alongside SC
              │ (both validated by the same cross-stack corpus
              │ extension)
              ▼

            P7 (Phase 7 portfolio)
              │
              ├── P7.A Capabilities          (depends on Phase 3)
              ├── P7.B Threshold sigs        (depends on Phase 3.4 + PA)
              ├── P7.C ZK proofs             (depends on Phase 5.1)
              ├── P7.D Intent solver         (depends on Phase 3.7)
              ├── P7.E Cross-shard           (depends on Phase 5.5)
              ├── P7.F Schema migration      (depends on Phase 5.12)
              └── P7.G Multi-region          (depends on Phase 5.12)
```

## Recommended landing order (cost-prioritised)

The following ordering minimises blocked work and front-loads
the headline deliverables:

```
Tier 0 (small, parallel, immediate):
  CL.1 documentation drift                              (0.5 day)
  CL.5 LP open-questions registry                       (0.5 day)
  WG.2 README + CLAUDE.md status                        (1 day, can wait for WG.1)

Tier 1 (medium, parallel, weeks):
  CA chain-level accounting                             (5–8 days; closes m-16)
  WG Workstream G documentation                         (8–14 days; closes "Not started")
  CL.2 stale comments                                   (2 days; parallel to others)
  CL.3 AR.18 visibility                                 (1 day)

Tier 2 (substantive, parallel-after-precursors, weeks):
  EI encoder injectivity                                (~9–16 days; retires footnote 1)
  SC SMT cell proofs                                    (~6–9 weeks; closes soundness gap)

Tier 3 (large, post-EI, parallel-when-resources-allow):
  PA parameterized laws landing                         (~6–10 weeks)
  CL.4 AR.23 lift to "Complete"                         (0.5 day; gated on EI.8)
  RH Rust host runtime                                  (~14–22 weeks)

Tier 4 (forward-roadmap, demand-driven):
  LX2 Lex v2                                            (~8 weeks)
  LX3 Lex v3                                            (~18 weeks)
  P7 Phase 7 (pick sub-workstreams)                     (20+ weeks)
```

Total minimum effort (Tier 0 + Tier 1 + Tier 2 + CL.4): ~14–22
calendar weeks for one full-time engineer.  Tier 3 (PA + RH)
adds ~20–32 weeks.  Tier 4 is open-ended.

## What this index does *not* track

  * **Detailed acceptance criteria.**  Each plan owns its
    acceptance criteria; this index is navigation only.
  * **Reviewer assignments.**  Per-workstream.
  * **Open questions resolutions.**  Owned by
    `open_questions.md`; resolved questions move to its §9.
  * **PR-by-PR status.**  Live in PR labels and the
    `audit_remediation_plan.md` §15C.2-style status tables of
    the relevant plan.

## Status-tracking rule

Each plan's "Status" section is the single source of truth for
that workstream.  When a sub-unit lands:
  1. Update the plan's status (mark sub-unit "Complete").
  2. If the sub-unit is the last in the workstream, update
    this index's "Status" column.
  3. If the workstream closes a CLAUDE.md or GENESIS_PLAN
    deferral note, retire that note in the same PR.

## Connection to CLAUDE.md / GENESIS_PLAN.md status tables

| Plan completes | Updates in CLAUDE.md | Updates in GENESIS_PLAN.md |
|----------------|----------------------|----------------------------|
| EI | footnote 1 retired; headline-theorem row added | §15B.1 / §15C.7 |
| RH | "Phase 5 ... Rust-host WUs ... deferred" note retired; "Rust off-chain observer deferred" note retired; E-A / E-B Rust adaptor notes retired | §12 Phase 5 table; §15B (observer) |
| SC | "Rust off-chain observer deferred" note partially retired (operator-mitigation portion); cell-proof headline row added | §15B (deferral note) |
| WG | "E-G | Not started" → "Complete" | new §15 chapter |
| CA | "Workstream E-C ... chain-level §7.6.4 / §7.6.5 follow-up" note retired; new headline rows | §7.6.4 / §7.6.5 / m-16 |
| PA | new "PA | Complete" row in phase table | new §14 or §15.X chapter for parameter substrate |
| LX2 | "Lex roadmap" v2 entry "Complete" | none direct |
| LX3 | "Lex roadmap" v3 entry "Complete" | kernel amendment for LX3.3 |
| CL | various comment / docstring cleanup | minor §15C.6 retirement (post-CL.3) |
| P7 | per-sub-workstream rows | §12 / new chapters |

## References

  * `docs/encoder_injectivity_plan.md`
  * `docs/rust_host_runtime_plan.md`
  * `docs/smt_cell_proofs_plan.md`
  * `docs/ethereum_workstream_g_plan.md`
  * `docs/chain_level_accounting_plan.md`
  * `docs/parameterized_laws_landing_plan.md`
  * `docs/phase_7_plan.md`
  * `docs/lex_v2_v3_roadmap_plan.md`
  * `docs/cleanup_and_consolidation_plan.md`
  * `docs/open_questions.md`
  * `CLAUDE.md` — canonical status tables.
  * `docs/GENESIS_PLAN.md` — canonical design + roadmap.

---

**End of index.**  Each workstream plan stands alone; this
document weaves them into a single landing strategy.
