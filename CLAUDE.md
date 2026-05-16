<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

<!--
  Canon — A Legal Kernel
  Adapted from the structure of Orbcrypt's CLAUDE.md
  (https://github.com/hatter6822/Orbcrypt/blob/main/CLAUDE.md)
  with project-specific guidance for Canon's Std-only, kernel-centric
  Lean 4 codebase.
-->

# CLAUDE.md — Canon project guidance

This file owns engineering conventions and the day-to-day developer /
agent workflow.  The design specification lives in
`docs/GENESIS_PLAN.md`; the top-level introduction lives in
`README.md`.  Where this file disagrees with the Genesis Plan, the
Genesis Plan wins.

## What this project is

Canon is a **proof-carrying state transition system** built in Lean 4.
It implements the Genesis Plan (`docs/GENESIS_PLAN.md`): a small,
parametric, law-free kernel where "legality" is a Lean type, every
state change is accompanied by a machine-checkable proof of
admissibility, and global system properties (determinism, refinement,
no-silent-illegality, invariant preservation) are guaranteed by
inductive theorems rather than by trust in operators.

**Current status.** Phases 0 – 6 complete; Ethereum integration
Workstreams A – F complete (Lean side); Workstream LP (actor-scoped
policies) complete; Workstream LX (Lex law-declaration language)
milestones M1 / M2 / M3 complete; Workstream H (fault-proof
migration) complete (Lean side; Rust off-chain observer deferred).
Workstream G (Ethereum documentation + amendment) and Phase 7
(Advanced Capabilities) are the next scoped work.  See
`docs/GENESIS_PLAN.md` §12 / §15B and
`docs/planning/ethereum_integration_plan.md` / `docs/planning/fault_proof_migration_plan.md`
for the per-phase deliverables; see "Implementation roadmap" below
for the status table.

## Build and run

```bash
# Recommended: SHA-256-verified setup.  Pins the Lean toolchain,
# verifies every download, and records a binary integrity snapshot.
./scripts/setup.sh            # idempotent
./scripts/setup.sh --build    # full setup + lake build
./scripts/setup.sh --quiet    # suppress informational logs

# Manual alternative (skip integrity verification):
curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
  | sh -s -- -y --default-toolchain none
elan toolchain install "$(cat lean-toolchain)"

# Daily commands.
source ~/.elan/env
lake build                          # full project build
lake build LegalKernel.<Module>     # one module (fastest feedback)
lake test                           # ~1907 tests across ~100 suites
lake exe count_sorries              # zero-sorry kernel gate
lake exe tcb_audit                  # TCB allowlist gate
lake exe stub_audit                 # stub-detection gate
lake exe naming_audit               # content-name discipline gate
lake exe deferral_audit             # no-deferrals policy gate
lake exe lex_lint                   # Lex registry + sidecar gate
lake exe lex_codegen --check        # Lex codegen-consistency gate
                                    #   (also: --canonical for full-body
                                    #   regeneration, --gen-property-tests)
lake exe lex_diff <before> <after>  # Lex semantic-diff binary
                                    #   (also: --git <ref-a> <ref-b>)
lake exe lex_format <file>          # Lex pretty-printer

# Runtime smoke test.
.lake/build/bin/canon info
.lake/build/bin/canon bootstrap /tmp/test.log
.lake/build/bin/canon-replay /tmp/test.log

# Workstream E (Solidity contracts) — see solidity/README.md.
cd solidity && ./scripts/vendor-deps.sh   # one-time
cd solidity && forge build
cd solidity && forge test
cd solidity && make test-cross-stack          # F.1.x equivalence suite
cd solidity && make testnet-acceptance-dryrun # F.3 local fork dry-run

# Workstream RH (Rust host runtime) — see runtime/README.md.
# Toolchain pin: runtime/rust-toolchain.toml (stable 1.83).
cd runtime && cargo build --workspace --all-targets
cd runtime && cargo test --workspace
cd runtime && cargo clippy --workspace --all-targets -- -D warnings
cd runtime && cargo fmt --all -- --check
```

`lakefile.lean` is the source of truth for every build target,
executable, and `lean_lib`; consult it before adding new targets.

**Toolchain.** Lean 4 v4.29.1 (pinned in `lean-toolchain`).  Bumping
the toolchain requires recomputing the four
`LEAN_TOOLCHAIN_SHA256_*` archive constants (one per
`(format, architecture)` pair: zst/zip × x86_64/aarch64) in
`scripts/setup.sh` and landing both changes in the same PR.

## Module build verification (mandatory)

Before committing any `.lean` file, build the specific module:

```bash
lake build LegalKernel.<Module.Path>
lake build Lex.<Module.Path>           # for Lex DSL / tools / examples / tests
```

After any source change, also run:

* `lake test` — runs the `@[test_driver]` declared in `Tests.lean`.
  Catches semantic regressions that elaboration-only checks miss
  (e.g. the §4.11 self-transfer fix would silently survive a build
  but break a test).  Each post-Phase-0 theorem additionally has a
  term-level API-stability test whose elaboration fails if the
  theorem signature changes.
* `lake exe count_sorries` — fails on any `sorry` in proof position
  in a kernel-adjacent module (`Kernel.lean`, `RBMapLemmas.lean`,
  `Laws/Transfer.lean` — the `Tools.Common.kernelTcbFiles` list).
  The detector masks `--` comments, `/- -/` blocks, and `"..."`
  string literals, so the word "sorry" in prose is fine; only the
  *term* in proof position is forbidden.
* `lake exe tcb_audit` — fails if a TCB-core module
  (`Kernel.lean`, `RBMapLemmas.lean` — the `Tools.Common.tcbCoreFiles`
  list) imports anything not on `tcb_allowlist.txt` *or* in
  `Tools.Common.tcbInternalImports` (the explicit, enumerated list
  of project-internal modules a TCB-core file may import).
* `lake exe stub_audit` — catches placeholder-body stubs
  (`:= ByteArray.empty`, `:= []`, etc.) accompanied by red-flag
  docstring tokens.  Allowlist: `tools/stub_allowlist.txt`.
* `lake exe lex_lint` + `lake exe lex_codegen --check` — enforce
  the Lex action-index registry's append-only discipline and the
  byte-stability of codegen-input sidecars.

CI (`.github/workflows/ci.yml`) runs all of the above on every PR.

## Source layout

```
canon/
├── lakefile.lean              -- Lake config (lean_lib, lean_exe, plus
│                                  input_file/input_dir build deps for the Lex
│                                  registry and codegen-input directory)
├── lean-toolchain             -- pinned Lean version
├── tcb_allowlist.txt          -- TCB import allowlist
├── Main.lean                  -- `canon` runtime CLI
├── Replay.lean                -- `canon-replay` audit binary
├── Tests.lean                 -- @[test_driver]; imports every test module
├── LegalKernel.lean           -- umbrella module (re-exports everything)
├── Lex.lean                   -- umbrella module for the Lex language
├── Deployments.lean           -- umbrella for the `Deployments` lean_lib
├── LegalKernel/
│   ├── Kernel.lean            -- §4.12 trusted core (TCB)
│   ├── RBMapLemmas.lean       -- §8.3 RBMap proof library (TCB)
│   ├── Conservation.lean      -- §8.1 / §5.3 economic invariants + LX classification typeclasses
│   ├── Laws/                  -- one law per file (transfer, mint, burn, freeze,
│   │                             reward, distributeOthers, proportionalDilute,
│   │                             deposit, withdraw, replaceKey, registerIdentity,
│   │                             dispute pipeline, local-policy laws).  Lex
│   │                             re-expressions live alongside the hand-written
│   │                             law; Lex-only demonstration laws live under
│   │                             `Lex/Examples/`.
│   ├── Authority/             -- Crypto, Action, Identity, Nonce, LocalPolicy,
│   │                             LocalPolicySemantics, SignedAction
│   ├── Encoding/              -- CBE codec (CBOR, Encodable, Action, SignedAction,
│   │                             State, SignInput, Disputes, LocalPolicy,
│   │                             StateInjective, LocalPolicyInjective,
│   │                             BridgeInjective).  The `*Injective.lean`
│   │                             siblings host the EI.2 – EI.7 encoder-
│   │                             injectivity theorems: `StateInjective`
│   │                             covers the nested-map `State` / `BalanceMap`
│   │                             carrier plus the flat `NonceState` and
│   │                             `KeyRegistry` maps; `LocalPolicyInjective`
│   │                             covers `LocalPolicies`; `BridgeInjective`
│   │                             covers the bridge consumed / pending maps
│   │                             plus the concat-form `BridgeState.encode`.
│   ├── DSL/                   -- Law.mk + `law` macro (base DSL).  The Lex
│   │                             extension (`lexlaw`, `lex_*` clauses) lives
│   │                             under the top-level `Lex/DSL/`.
│   ├── Events/                -- §8.9.2 Event inductive + extractEvents
│   ├── Runtime/               -- Hash, LogFile, Replay, Snapshot, Loop (Phase 5)
│   ├── Disputes/              -- §8.4 four-stage pipeline (Phase 6) + incentive amendment
│   ├── LocalPolicy/           -- Workstream LP classification typeclasses
│   ├── Bridge/                -- Workstreams A–D: crypto adaptors, identity,
│   │                             bridge laws, withdrawal proofs
│   ├── FaultProof/            -- Workstream H: state-commitment scheme,
│   │                             kernel-step type, bisection-game state
│   │                             machine, convergence / honesty / settlement
│   │                             theorems, witness construction, observer
│   │                             reference
│   └── Test/                  -- IO-based test harness; one suite per module
├── Lex/                       -- Workstream LX — the Lex programming language.
│   ├── IndexRegistry.txt      -- frozen action-index registry (append-only; LX.1)
│   ├── DSL/                   -- Lex DSL macros (`lex_law`, `lexlaw`, properties,
│   │                             deployments).  PreGrammar, ImplCalculus,
│   │                             ImplLowering, Events, Shim, Law, Property,
│   │                             Deployment.
│   ├── Tools/                 -- Lex audit-binary libraries (Common, Lint,
│   │                             Codegen, Diff, Format).
│   ├── Bin/                   -- Lake `lean_exe` entry-point wrappers
│   │                             (Lint, Codegen, Diff, Format).
│   ├── Inputs/                -- Lex codegen-input JSON sidecars (one per
│   │                             Lex law) plus the canonical manifest and the
│   │                             property-test coverage file.
│   ├── Examples/              -- Lex-only demonstration laws (ExampleLex).
│   └── Test/                  -- Lex test modules (DSL, Tools, Properties,
│                                 AutoGenProperties, ExampleLex, M2).
├── Deployments/Examples/      -- LX-M3 worked example deployments (UsdClearing)
├── Tools/                     -- non-Lex audit binaries (TcbAudit, CountSorries,
│                                  StubAudit, NamingAudit, DeferralAudit) +
│                                  shared `Common` library.  (Lex audit
│                                  binaries live under `Lex/Tools/` and
│                                  `Lex/Bin/`.)
├── solidity/                  -- Workstreams E + H: L1 mirror (10 contracts,
│                                  5 libraries, 20+ forge test suites).
│                                  See solidity/README.md.
├── runtime/                   -- Workstream RH (Rust host runtime).
│   ├── Cargo.toml             --   workspace manifest
│   ├── rust-toolchain.toml    --   pinned Rust channel (stable 1.83)
│   ├── canon-hash-fallback.c  --   AR.10 default fallback (lake-built)
│   ├── canon-cli-common/      --   shared CLI / logging helpers (RH-H)
│   ├── canon-cross-stack/     --   dev-dep fixture loader (RH-H)
│   ├── canon-verify-secp256k1/ --  RH-A.1 ECDSA secp256k1 verifier
│   ├── canon-hash-keccak256/  --   RH-A.2 keccak-256 hash adaptor
│   ├── canon-host/            --   RH-C skeleton (network adaptor)
│   ├── canon-l1-ingest/       --   RH-B skeleton (L1 watcher)
│   ├── canon-event-subscribe/ --   RH-D skeleton (event server)
│   ├── canon-storage/         --   RH-E.0 skeleton (DB layer)
│   ├── canon-indexer/         --   RH-E.1 skeleton (SQLite indexer)
│   ├── canon-faultproof-observer/ -- RH-G skeleton (off-chain observer)
│   ├── canon-bench/           --   RH-F skeleton (10k tx/sec bench)
│   └── tests/cross-stack/     --   shared fixture corpus (.cxsf files)
├── scripts/setup.sh           -- SHA-256-verified toolchain + Foundry installer
├── .github/workflows/ci.yml   -- Lean build + test + audits on PR / push
├── .github/workflows/ci-rust.yml -- Rust workspace build + test + clippy +
│                                  fmt on PR / push (path-filtered to
│                                  runtime/**)
├── README.md                  -- project entry point
├── CLAUDE.md                  -- this file
└── docs/
    ├── GENESIS_PLAN.md                  -- canonical design document
    ├── law_language_design.md           -- Lex DSL design notes
    ├── lex_amendment_walkthrough.md     -- LX-M3 worked walkthrough
    ├── decidability_discipline.md       -- decPre discipline
    ├── std_dependencies.md              -- Std lemma audit
    ├── economic_invariants.md           -- Phase-2 + monotonicity-tier design
    ├── extraction_notes.md              -- Lean → runtime erasure / persistence
    ├── fault_proof_design.md            -- Workstream H design rationale
    ├── fault_proof_runbook.md           -- Workstream H operator runbook
    ├── abi.md                           -- on-disk frame format + CLI ABI
    ├── audits/                          -- per-area Lean audit reports
    └── planning/                        -- engineering / workstream plans
        ├── ethereum_integration_plan.md     -- Workstreams A – G
        ├── actor_scoped_policies_plan.md    -- Workstream LP
        ├── lex_implementation_plan.md       -- Workstream LX
        ├── parameterized_laws_plan.md       -- (planning)
        ├── fault_proof_migration_plan.md    -- Workstream H engineering plan
        ├── audit_remediation_plan.md        -- audit-remediation workstream
        ├── chain_level_accounting_plan.md   -- §7.6.4 / §7.6.5 inductive promotion
        ├── cleanup_and_consolidation_plan.md -- documentation / visibility tidy-up
        ├── deferred_work_index.md           -- navigator across deferred-work plans
        ├── encoder_injectivity_plan.md      -- EI proof-track plan (complete)
        ├── ethereum_workstream_g_plan.md    -- E-G documentation amendment
        ├── lex_v2_v3_roadmap_plan.md        -- Lex v2 / v3 forward roadmap
        ├── open_questions.md                -- master design-decision registry
        ├── parameterized_laws_landing_plan.md -- PA landing plan
        ├── phase_7_plan.md                  -- advanced-capability portfolio
        ├── rust_host_runtime_plan.md        -- Phase 5 + E-A/B + H.10.5 Rust host
        └── smt_cell_proofs_plan.md          -- SMT cell-proof cross-stack plan
```

Per-file purpose lives in each file's `/-! ... -/` module docstring,
not duplicated here.

### Module dependency graph

```
LegalKernel.RBMapLemmas        (TCB; Std-only)
LegalKernel.Kernel             (TCB; imports RBMapLemmas)

LegalKernel.Conservation       (non-TCB; imports Kernel + RBMapLemmas)
LegalKernel.Laws.*             (non-TCB; imports Conservation + Kernel)

LegalKernel.Authority.*        (non-TCB; intra-Authority layering is
                                Crypto → Action → Identity → Nonce →
                                LocalPolicy{,Semantics} → SignedAction.
                                Note that `Authority.Action` also imports
                                every `Laws.*` module plus `Bridge.AddressBook`,
                                `Bridge.State`, and `Disputes.Types` because
                                the `Action` inductive has constructors that
                                reference those types — the linear chain above
                                shows the intra-Authority order only.)

LegalKernel.Encoding.*         (non-TCB; CBOR / Encodable foundation, then
                                Action → SignedAction → State → SignInput;
                                Disputes / LocalPolicy add their own variants;
                                Encoding.StateInjective extends State with
                                the EI.2 – EI.4 encoder-injectivity theorems
                                for BalanceMap / State / NonceState /
                                KeyRegistry plus the State.Equiv relation;
                                Encoding.LocalPolicyInjective hosts EI.5
                                (LocalPolicies map injectivity);
                                Encoding.BridgeInjective hosts EI.6 + EI.7
                                (consumed / pending map injectivity plus
                                the concat-form BridgeState.encode).)

LegalKernel.DSL.{Law, LawSyntax}              (non-TCB; base law DSL; depends
                                               on Kernel + Authority)

Lex.DSL.{PreGrammar, ImplCalculus, ImplLowering,
          Events, Shim, Law, Property,
          Deployment}                         (non-TCB; Lex language extension
                                               of the base DSL; depends on
                                               LegalKernel.DSL + Authority +
                                               Lex.Tools.Common)
Lex.Examples.ExampleLex                       (non-TCB; LX.21 acceptance demo)
Lex                                           (umbrella; re-exports the Lex
                                               DSL surface)

LegalKernel.Events.{Types, Extract}            (non-TCB; depends on Authority)
LegalKernel.Runtime.{Hash, LogFile, Replay,
                      Snapshot, AttestedSnapshot,
                      Loop}                    (non-TCB; depends on Encoding + Events)

LegalKernel.Disputes.{Types, Filing, Evidence,
                       Verdict, LawClassification,
                       MonotonicDeployment,
                       Rewards, Staking}       (non-TCB; depends on Authority + Runtime)

LegalKernel.LocalPolicy.LawClassification     (non-TCB)
LegalKernel.Bridge.*                          (non-TCB; Workstreams A – D)

LegalKernel                                   (umbrella; re-exports everything)
Main / Replay / Tests                         (executables)

Tools.Common                                  (lean_lib `ToolsCommon`; shared
                                               helpers for the TCB / stub audits)
Lex.Tools.Common                              (lean_lib `LexCommon`; shared
                                               helpers for the Lex audit binaries)
Tools.{TcbAudit, CountSorries, StubAudit,
       NamingAudit, DeferralAudit}            (non-Lex audit binaries; no
                                               Lean-level dependency on the kernel)
Lex.Tools.{Lint, Codegen, Diff, Format}       (Lex audit-binary libraries;
                                               their `def main` entry-point
                                               glue lives at `Lex.Bin.*`)
Lex.Bin.{Lint, Codegen, Diff, Format}         (Lake `lean_exe` entry-point
                                               wrappers for the Lex audit
                                               binaries)
```

The kernel has **zero** external Lean-package dependencies.
`Std.Data.TreeMap` is part of Lean core (since Lean ≥ 4.10), not a
separate Lake package, so the TCB equals exactly the Lean core
distribution plus `Kernel.lean` + `RBMapLemmas.lean`.  Every other
module is non-TCB deployment-facing infrastructure: bugs there are
scoped to deployment-level claims, not kernel invariants.

**Trust assumptions.**  Two non-Lean assumptions surface through
opaque declarations rather than axioms (so `#print axioms` stays at
exactly `propext`, `Classical.choice`, `Quot.sound`):

1. `Authority.Crypto.Verify` — the deployment-supplied signature
   scheme is EUF-CMA secure.
2. `Runtime.Hash.hashBytes` — the production hash function (BLAKE3
   in production via `@[extern]`; FNV-1a-64 fallback for tests) is
   collision-resistant.

The kernel's authority and replay guarantees are conditional on
these.

## Reading large files

`docs/GENESIS_PLAN.md` is ~4200 lines / ~180 KB.  Read in chunks with
`Read(file_path, offset=…, limit=500)` rather than the whole file.
The table of contents at the top of the document maps section numbers
to the line ranges you actually need.

When editing, read the specific region around the target lines first
(e.g., `offset=2580, limit=80`) so the `old_string` matches exactly,
including indentation and whitespace.

## Writing and editing files

The Write tool replaces an entire file in one call.  For files over
~100 lines this is error-prone: the tool may time out, drop content,
or fill the context window.  **Prefer the Edit tool for all changes
to existing files**, regardless of size.

**Rules for large-file changes:**

1. **Never rewrite a large file with Write.**  Use Edit with a
   precise `old_string`/`new_string` pair targeting only the lines
   that change.
2. **One logical change per Edit call.**  Three separate edits beat
   one giant cross-section replacement.
3. **Read before you edit.**  Always Read the specific region first
   so the `old_string` matches exactly.
4. **Adding large new sections.**  If you must insert more than ~80
   new lines, break the insertion into multiple sequential Edit
   calls, anchoring each to context already present.
5. **Creating new large files.**  Build incrementally: an initial
   Write (under 100 lines) followed by Edit appends, *or* a Bash
   heredoc (`cat <<'EOF' > path/to/file.lean ... EOF`) which has no
   content-size timeout.
6. **Post-write verification.**  After any large write or edit
   sequence, spot-check by reading the modified region and the
   file's last few lines.

## Handling large search and command output

- **Grep**: cap with `head_limit` (e.g., `head_limit=30`); use
  `output_mode: "files_with_matches"` first, then drill in.
- **Glob**: scope with `path` instead of searching the whole repo.
- **Bash output**: pipe through `head` / `tail` (e.g.,
  `lake build 2>&1 | tail -80`).  For very large output, redirect
  to a temp file and `Read` it in chunks.

**Rule of thumb:** if a command might return more than ~100 lines,
limit it upfront.

## Background-agent file-change protection

Background agents (Task tool with `run_in_background: true`) run
concurrently and may finish after the foreground agent has already
modified the same files.  Their stale writes will silently overwrite
foreground progress.  Prevent this proactively:

1. **Never delegate file writes to a background agent for files you
   may also edit.**  Identify every file the agent may create or
   modify before launching.
2. **Partition files strictly.**  If parallel work is genuinely
   needed, assign each agent a disjoint set of files and document
   the partition in the agent's prompt ("you own `Foo.lean` only —
   do not modify any other file").
3. **Use background agents only for read-only or independent-file
   tasks.**  Safe: builds, tests, searches, research.  Unsafe:
   editing shared sources or configs.
4. **Check background results before acting on shared state.**  If
   the agent wrote to a file you have since modified, discard the
   agent's version and redo on top of your current state.
5. **When in doubt, run in foreground.**  Sequential correctness
   beats parallel speed.

## Key conventions

- **Two-reviewer rule for kernel-touching changes (ABSOLUTE).**  Any
  change to `LegalKernel/Kernel.lean` or
  `LegalKernel/RBMapLemmas.lean` requires two reviewers per Genesis
  Plan §13.6.  Law modules and tests require one reviewer.

  `.github/CODEOWNERS` (AR.20) is the request-for-review surface
  for the TCB-core file set: any PR touching `Kernel.lean` or
  `RBMapLemmas.lean` auto-requests the listed reviewers.
  CODEOWNERS is NOT a merge-block; full mechanical enforcement
  requires a GitHub branch-protection rule, which is repository-
  administrator territory and outside the scope of a code-only
  PR.  The two-reviewer rule remains a process rule enforced by
  the team.

- **No `sorry` in kernel-adjacent code (ABSOLUTE).**  The
  kernel-adjacent files (`Kernel.lean`, `RBMapLemmas.lean`,
  `Laws/Transfer.lean` — strictly wider than the TCB core, which
  is just `Kernel.lean` + `RBMapLemmas.lean`) must not contain a
  `sorry` in proof position.  `lake exe count_sorries` is the
  mechanical check; CI blocks the merge on a non-zero count.
  Comments referencing the *word* "sorry" are allowed; only the
  *term* in proof position is forbidden.

- **No custom axioms (ABSOLUTE).**  The kernel may use Lean's
  built-in axioms (`propext`, `Classical.choice`, `Quot.sound`) but
  must not introduce its own.  Adding an `axiom` declaration is a
  Genesis-Plan amendment and triggers the two-reviewer gate.

- **Std-core only in the kernel TCB.**  The kernel imports
  `Std.Data.TreeMap` (Lean core, not batteries) plus the sibling
  TCB module `LegalKernel.RBMapLemmas`.  `lake exe tcb_audit`
  compares each TCB module's direct-import set against
  `tcb_allowlist.txt` and `Tools.Common.tcbInternalImports`.
  Adding Mathlib or batteries is a TCB expansion and must go
  through the §13.6 amendment process.  Non-TCB law modules may
  import other things if absolutely necessary, but the default is
  "Std core only" until a specific need is justified.

- **Strict linters project-wide.**  `lakefile.lean` sets:
  - `autoImplicit := false` (and `relaxedAutoImplicit := false`) —
    Lean must not silently introduce universe / type variables.
  - `linter.missingDocs := true` — public surfaces (def, theorem,
    structure field, inductive constructor) must carry a
    `/-- … -/` docstring or the build warns.
  - `linter.unusedVariables := true` — surfaces dead bindings.
  - CI's strict-warnings gate fails the build on any `: warning:`
    line, so these are forcing-functions, not advisories.

- **Decidability discipline (§13.6 step 2).**  Every
  `Transition.decPre` field should be definable as
  `fun _ => inferInstance` whenever the precondition is built from
  arithmetic comparisons, `Nat` operations, and finite conjunctions.
  A law needing a hand-written `Decidable` derivation is a signal to
  security-review the law (§14.8): preconditions that resist
  `inferInstance` often hide an unbounded quantifier or a
  non-computable predicate that breaks the executable path.

- **Naming conventions:**
  - Theorems and lemmas: `snake_case` (Lean / Mathlib style) —
    `impl_refines_spec`, `transfer_conserves`.
  - Structures and types: `CamelCase` — `Transition`, `Legal`,
    `CertifiedTransition`.
  - Type variables: capital letters by role — `α`, `β`, `γ` for
    generic types; `s`, `s'` for states; `t` for transitions.
  - Hypothesis names: `h`-prefixed — `hpre`, `hreach`, `h_init`,
    `h_step`.
  - Namespaces: `LegalKernel`, `LegalKernel.Laws`,
    `LegalKernel.Test`.
  - **Names describe content, never provenance.**  An identifier
    must describe *what the declaration is or proves*, never *which
    work unit, audit, phase, or session produced it*.  Forbidden
    tokens in declaration names include, non-exhaustively:
    - work-unit labels: `wu`, `wu1`, `wu_2_5`, `phase`, `phase0`
    - audit / finding ids: `audit`, `finding`, `f02`, `cve`
    - session / branch references: `claude_`, `session_`, `pr23`
    - temporal markers: `old`, `new`, `v2`, `legacy`, `tmp`, `todo`,
      `fixme`

    Process markers may appear in *docstrings* (a `/-- ... -/`
    block can say "added in WU 2.5") and in commit messages,
    branch names, and planning documents.  The boundary is sharp:
    the docstring may carry a process tag, the identifier may not.

  - **Enforcement.**  Before landing any new declaration, scan the
    diff:
    ```bash
    git diff --cached -U0 -- '*.lean' \
      | grep -E '^\+(def|theorem|structure|class|instance|abbrev|lemma|noncomputable)' \
      | grep -iE 'workstream|\bws[0-9]|\bwu[0-9]|\bphase[0-9_]|audit|\bf[0-9]{2}\b|\btmp\b|\btodo\b|\bfixme\b|claude_|session_|_v[2-5]\b'
    ```
    A non-empty result is a review-blocking naming violation.
    AR.8 / M-9: the `_v2` / `_v3` / `_v4` / `_v5` family is also
    enforced mechanically by `naming_audit`'s `forbiddenTokens`
    list — the grep above mirrors the CI gate.

- **Proof style:**
  - Prefer tactic mode (`by …`) for non-trivial proofs.
  - Use `calc` blocks for equational reasoning chains.
  - Use `have` for intermediate steps with descriptive names.
  - Comment proof strategy at the top of each non-obvious theorem.
  - Avoid `decide` on large finite types (performance trap).

- **Documentation:**
  - Every `.lean` file begins with a `/-! ... -/` module docstring
    naming the Genesis-Plan section it implements.
  - Every public `def` / `theorem` / `structure` / `instance` has a
    `/-- ... -/` docstring.
  - Where a definition tracks a Genesis-Plan section (e.g.
    `transfer` is §4.11), say so in the docstring so future readers
    can cross-reference.

- **Import discipline:**  Import by full path within the project
  (`import LegalKernel.Kernel`).  Re-export top-level definitions
  via `LegalKernel.lean` (the umbrella module) so downstream
  consumers can `import LegalKernel` and get everything.

- **Git practices:**  One commit per completed work unit.  Commit
  messages may reference the WU number (`"WU 0.2: Kernel module
  skeleton"`).  All commits must pass `lake build` AND `lake test`
  — never commit broken or untested code.

- **Patch-version bumps (DEFAULT).**  Each pull request bumps the
  patch component of the relevant package version unless the
  user explicitly says otherwise.  This is the default release
  discipline; deviations require explicit instruction in the
  task or commit message.  Scope:

  | Surface        | Bump location                                    |
  |----------------|--------------------------------------------------|
  | Lean kernel    | `lean-toolchain` *is not* a version; the kernel  |
  |                | does not have a per-package version.  No bump.   |
  | Rust workspace | `runtime/Cargo.toml`'s `[workspace.package]      |
  |                | version` field (every member crate inherits      |
  |                | via `version.workspace = true`).                 |
  | Solidity       | `solidity/foundry.toml` if a `version` field is  |
  |                | present (typically tracked at the contract /     |
  |                | release level rather than per-package).          |

  *Semantics.*  Use semver:
    - **Patch** (default): bug fixes, internal refactors,
      documentation-only changes, additional tests, performance
      improvements that don't change observable behaviour.
      Example: `0.1.0 → 0.1.1`.
    - **Minor**: new functionality that is backwards compatible
      (new public API, new feature flag, new optional config).
      Example: `0.1.5 → 0.2.0`.
    - **Major**: backwards-incompatible changes to the public
      API or wire format.  Example: `0.2.3 → 1.0.0`.
    The user opts into a non-patch bump explicitly (e.g.,
    "bump minor for this PR" or "this is a 1.0 release").

  *Mechanics for the Rust workspace.*  Bumping the workspace
  version requires updating exactly one line in
  `runtime/Cargo.toml`:

  ```toml
  [workspace.package]
  version = "0.1.0"     # <-- bump this
  ```

  Every member crate inherits via `version.workspace = true`.
  `Cargo.lock` is regenerated automatically by `cargo build`;
  the new lockfile must be committed in the same PR.

  *Mechanics for the Lean side.*  The Lean kernel has no
  per-package version (the kernel is identified by its
  `kernelBuildTag` string and the pinned `lean-toolchain`).
  Lean-only PRs do not require a version bump.

  *When NOT to bump.*  Pure documentation edits (typo fixes,
  README updates) within an in-progress workstream do not need
  their own patch bump if the workstream itself already has an
  in-flight PR that will bump.  Use judgement: a standalone
  doc-only PR still bumps; a doc tweak added mid-PR does not.

## Type-level design properties

The Genesis Plan promises a small set of type-level guarantees
(§1, §5).  As of Phases 0 – 6 + Workstreams A – D + LP + LX + H,
every guarantee is mechanised by a real Lean theorem (no `sorry`,
no custom axioms — only `propext`, `Classical.choice`, `Quot.sound`).
Selected headline theorems by tier:

| Tier  | Property                                | Headline theorem                  | File                                    |
|-------|-----------------------------------------|-----------------------------------|-----------------------------------------|
| TCB   | Determinism                             | typing of `step_impl`             | `Kernel.lean`                           |
| TCB   | No silent illegality                    | `impl_noop_if_not_pre`            | `Kernel.lean`                           |
| TCB   | Refinement                              | `impl_refines_spec`               | `Kernel.lean`                           |
| TCB   | Invariant preservation                  | `invariant_preservation`          | `Kernel.lean`                           |
| TCB   | Compositionality of invariants          | `invariants_compose`              | `Kernel.lean`                           |
| TCB   | Certified ≡ executable                  | `apply_certified_eq_step_impl`    | `Kernel.lean`                           |
| TCB   | Reachability is reflexive-transitive    | `Reachable.refl`, `Reachable.trans` | `Kernel.lean` (§4.9)                  |
| TCB   | Per-law-set invariant preservation      | `invariant_preservation_via_laws` | `Kernel.lean` (§4.10)                   |
| TCB   | RBMap fold / insert lemmas              | `find?_insert_*`, `sumValues_*`   | `RBMapLemmas.lean` (§8.3)               |
| Phase 2 | Per-resource accounting on `setBalance` | `totalSupply_setBalance`        | `Conservation.lean`                     |
| Phase 2 | Transfer preserves total supply       | `transfer_conserves`              | `Laws/Transfer.lean` (§4.11.1)          |
| Phase 2 | Conservation classification typeclass | `IsConservative`                  | `Conservation.lean`                     |
| Phase 2 | Type-level firewall for conservation  | `ConservativeLawSet`              | `Conservation.lean` (§6.2)              |
| Phase 2 | Global supply preservation            | `total_supply_global[_via_law_set]` | `Conservation.lean` (§5.3)            |
| Phase 2 | Frozen-resource preservation          | `*_preserves_freeze`              | `Laws/Freeze.lean` (§4.10)              |
| 4-prelude | Monotonicity classification + firewall | `IsMonotonic`, `MonotonicLawSet` | `Conservation.lean`                    |
| 4-prelude | Per-resource non-decrease            | `total_supply_globally_nondecreasing` | `Conservation.lean`                |
| 4-prelude | `proportionalDilute` dust bound      | `proportionalDilute_distributed_le_totalReward` | `Laws/ProportionalDilute.lean` |
| Phase 3 | Action compilation is injective       | `Action.compile_injective`        | `Authority/Action.lean` (§4.13)         |
| Phase 3 | Per-actor nonce is strictly monotonic | `expectsNonce_strict_mono`        | `Authority/Nonce.lean` (§8.5)           |
| Phase 3 | Nonce uniqueness across admissibility | `nonce_uniqueness`                | `Authority/SignedAction.lean` (§8.5.2)  |
| Phase 3 | Replay is type-level impossible       | `replay_impossible`               | `Authority/SignedAction.lean` (§8.5.2)  |
| Phase 3 | Key-rotation registry mutation        | `replaceKey_updates_registry`     | `Authority/SignedAction.lean`           |
| Phase 4 | CBE round-trip + injectivity          | `*_roundtrip`, `*_encode_injective` | `Encoding/*.lean`                     |
| Phase 4 | Domain-separated sign inputs          | `signInput_*` (cross-deployment)  | `Encoding/SignInput.lean` (§8.8.5)      |
| EI.2    | Inner-map encoder injectivity         | `BalanceMap.encode_injective`     | `Encoding/StateInjective.lean`          |
| EI.2    | Nested-state encoder injectivity      | `State.encode_injective`          | `Encoding/StateInjective.lean`          |
| EI.3    | Nonce-ledger encoder injectivity      | `NonceState.encode_injective`     | `Encoding/StateInjective.lean`          |
| EI.4    | Key-registry encoder injectivity      | `KeyRegistry.encodeMap_injective` | `Encoding/StateInjective.lean`          |
| EI.5    | Local-policies map encoder injectivity | `LocalPolicies.encodeMap_injective` | `Encoding/LocalPolicyInjective.lean`  |
| EI.6    | Bridge-consumed map encoder injectivity | `Bridge.BridgeState.encodeConsumed_injective` | `Encoding/BridgeInjective.lean` |
| EI.7    | Bridge-pending map encoder injectivity | `Bridge.BridgeState.encodePending_injective` | `Encoding/BridgeInjective.lean`   |
| EI.7    | Bridge full-state encoder injectivity | `Bridge.BridgeState.encode_injective` | `Encoding/BridgeInjective.lean`     |
| EI.8    | State-commit sub-state extensional eq under CR | `commitExtendedState_subcommits_extensional_eq_under_collision_free` | `FaultProof/Commit.lean` (§15B.1) |
| Phase 6 | Dispute filing rejects malformed inputs | `fileDispute_rejects_*`         | `Disputes/Filing.lean`                  |
| Phase 6 | `disputeWithdraw` is idempotent       | `applyWithdraw_idempotent`        | `Disputes/Filing.lean`                  |
| Phase 6 | Evidence verifiers are deterministic  | `checkEvidence_deterministic`     | `Disputes/Evidence.lean`                |
| Phase 6 | `applyVerdict` is provably total under witness | `applyVerdict_under_witness_succeeds` | `Disputes/Verdict.lean` (Option-C) |
| Phase 6 | Dispute pipeline composes with monotonic deployments | `disputable_monotonic_total_supply_nondecreasing` | `Disputes/MonotonicDeployment.lean` |
| LP    | Local policies cannot lock out meta-actions | `localPolicy_meta_action_independent` | `Authority/SignedAction.lean`     |
| E-A   | EIP-712 wrap injectivity              | `eip712Wrap_injective`            | `Bridge/Eip712.lean`                    |
| E-B   | Bridge actor policy authorises only registry actions | `bridgePolicy_*` family | `Bridge/BridgeActor.lean`             |
| E-C   | Deposit / withdraw replay impossible  | `deposit_replay_blocked_by_consumed`, `withdraw_bumps_nextWdId` | `Bridge/Admissible.lean` |
| E-D   | SMT verifier completeness + soundness | `verifyProof_complete`, `verifyProof_sound` | `Bridge/WithdrawalRoot.lean` |
| E-D   | Finalisation is monotonic in L1 block | `isFinalised_monotonic_in_currentBlock` | `Bridge/Finalisation.lean`        |
| LX    | Locality / freeze-preservation typeclass firewalls | `LocalTo`, `FreezePreserving`, `FreezePreservingLawSet` | `Conservation.lean` |
| LX    | Registry-preservation classification  | `RegistryPreserving`              | `Authority/SignedAction.lean`           |
| H     | State-commit sub-state byte equality under CR | `commitExtendedState_subcommits_bytes_eq_under_collision_free` | `FaultProof/Commit.lean` (§15B.1) |
| H     | Kernel step coherent with kernelOnlyApply | `recomputeCommitment_coherent_with_kernelOnlyApply` | `FaultProof/Coherence.lean` (§15B.2) |
| H     | Multi-step coherence with kernelOnlyReplay | `recomputeCommitment_chain_coherent_with_kernelOnlyReplay` | `FaultProof/Coherence.lean` (§15B.2) |
| H     | Bisection narrows under any response  | `range_narrows_on_response_{agree,disagree}` | `FaultProof/Game.lean` (§15B.3) |
| H     | Bisection converges after enough rounds | `bisection_converges_after_enough_rounds` | `FaultProof/Convergence.lean` (§15B.3) |
| H     | Disagreement persists along honest trace | `disagreement_persists_along_trace` | `FaultProof/Honesty.lean` (§15B.4)     |
| H     | Honest challenger wins at settlement  | `honest_challenger_wins_against_invalid_state_root` | `FaultProof/Settlement.lean` (§15B.4) |
| H     | Witness implies state-root wrong       | `faultProof_challenger_won_implies_state_root_wrong` | `FaultProof/Witness.lean` (§15B.6)¹ |

¹ The shipped theorem decomposes a `FaultProofChallengerWon` witness's L1 attestation against an explicit `L1AttestationSemantics` deployment assumption (the operational implication "L1 watcher confirms ⇒ sequencer's claim ≠ canonical commit").  The L1 contract enforces this operationally; cross-stack verification (WU H.10.1 corpus) ratifies it.

The full per-theorem catalogue lives in source — each module's
`/-! ... -/` docstring names the Genesis-Plan section it
implements, and `#print axioms` confirms each theorem depends only
on the canonical three Lean built-ins (or a strict subset, e.g.
many encoding theorems use only `propext` and `Quot.sound`).

Modifying any TCB-tier property is a TCB change and triggers the
two-reviewer gate; modifying any non-TCB property needs one
reviewer.  The Phase-3, Workstream E-A, and Workstream E-D
properties additionally depend on trust assumptions about
deployment-supplied crypto (see "Trust assumptions" above).

## Std core integration

Canon's kernel uses **Lean core only**, no Mathlib or batteries.
Familiarity with these Std definitions is essential before
modifying the kernel:

| Std name              | Type                          | Role in Canon            |
|-----------------------|-------------------------------|--------------------------|
| `Std.TreeMap α β cmp` | structure                     | balanced ordered map (RB)|
| `TreeMap.empty`       | `TreeMap α β cmp`             | empty map                |
| `TreeMap.insert`      | `… → α → β → TreeMap …`       | insert / overwrite       |
| `m[k]?` / `find?`     | `… → α → Option β`            | lookup                   |
| `m[k]?.getD v`        | `… → α → β → β`               | lookup with default      |
| `TreeMap.foldl`       | `(δ → α → β → δ) → δ → … → δ` | order-determined fold    |

The TCB imports `Std.Data.TreeMap` only.  The full per-lemma audit
lives in `docs/std_dependencies.md`; reviewers consult it during
toolchain bumps.  Each addition to the kernel's import set must
update **both** `tcb_allowlist.txt` and `docs/std_dependencies.md`
in the same PR; CI blocks on un-allowlisted imports.

**Version strategy.**  Pin the Lean toolchain in `lean-toolchain`;
`scripts/setup.sh` validates archive SHA-256s against the
per-architecture pin baked into the script.  Bump only when a
specific feature is needed, and recompute the SHAs in the same PR.

## Implementation roadmap

Genesis Plan §12 lays out eight phases (0–7) plus cross-cutting
work units.  Status:

| Phase     | Title                              | Status   |
|-----------|------------------------------------|----------|
| 0         | Foundations                        | Complete |
| 1         | Kernel completion                  | Complete |
| 2         | Economic invariants                | Complete |
| 3         | Authority layer                    | Complete |
| 4-prelude | Positive-incentive mechanisms      | Complete |
| 4         | DSL and serialization              | Complete |
| 5         | Runtime and extraction             | Complete (Lean side; Rust-host WUs 5.4 / 5.7 / 5.8 / 5.11 deferred) |
| 6         | Disputes and adjudication          | Complete |
| 6-amend   | Phase-6 incentive integration      | Complete |
| E-A       | Ethereum: cryptographic adaptors   | Complete (Lean side; Rust adaptor crates deferred) |
| E-B       | Ethereum: identity and authority   | Complete (Lean side; Rust ingestor deferred) |
| E-C       | Ethereum: bridge laws              | Complete (Lean side; chain-level §7.6.4 / §7.6.5 follow-up) |
| E-D       | Ethereum: withdrawal proofs        | Complete |
| E-E       | Ethereum: Solidity contracts       | Complete |
| E-F       | Ethereum: cross-stack verification | Complete |
| LP        | Actor-scoped policies              | Complete (Lean side; Solidity mirror future work) |
| LX-M1     | Lex: macro skeleton + synthesizer  | Complete |
| LX-M2     | Lex: re-express 17 kernel laws     | Complete |
| LX-M3     | Lex: deployment manifests + governance | Complete |
| H         | Fault-proof migration              | Complete (Lean side; Rust off-chain observer deferred) |
| RH-H      | Rust host: workspace + CI harness  | Complete |
| RH-A.1    | Rust host: secp256k1 verify adaptor | Complete |
| RH-A.2    | Rust host: keccak256 hash adaptor  | Complete |
| RH-B      | Rust host: L1 event ingestor       | Not started (skeleton landed under RH-H) |
| RH-C      | Rust host: network adaptor         | Not started (skeleton landed under RH-H) |
| RH-D      | Rust host: event subscription      | Not started (skeleton landed under RH-H) |
| RH-E.0    | Rust host: storage abstraction     | Not started (skeleton landed under RH-H) |
| RH-E.1    | Rust host: SQLite indexer          | Not started (skeleton landed under RH-H) |
| RH-F      | Rust host: 10k tx/sec benchmark    | Not started (skeleton landed under RH-H) |
| RH-G      | Rust host: fault-proof observer    | Not started (skeleton landed under RH-H) |
| E-G       | Ethereum: documentation + amendment | Not started |
| 7         | Advanced capabilities              | Not started |

Read the Genesis Plan's per-phase work-unit breakdown and the
relevant workstream plan in `docs/` before starting new work.
Each WU has explicit deliverables, acceptance criteria, and
dependencies.

## Documentation rules

When changing behaviour, theorems, or formalisation status, update
in the same PR:

1. `docs/GENESIS_PLAN.md` — if the change affects the architecture,
   the formal model, the threat model, or the roadmap.  Bump the
   "Phase X status" subsection at the bottom of the relevant phase.
2. `README.md` — if project status, build commands, or quickstart
   change.
3. `CLAUDE.md` (and `AGENTS.md` — keep them byte-identical) — if
   conventions, build commands, or current-status summary change.

Canonical ownership: `docs/GENESIS_PLAN.md` owns the design; this
file owns engineering conventions and the day-to-day developer /
agent workflow; `README.md` owns the top-level introduction.

**Don't extend audit narratives in this file.**  Per-audit and
per-WU completion details belong in commit messages and PR
descriptions, where they have permanent provenance via git history.
This file describes the *current state*, not the path that got us
here.

## Pull request authoring policy (ABSOLUTE)

**Forbidden in PR summaries / descriptions / bodies:** session URLs
of the shape `https://claude.ai/code/session_*` (or any equivalent
agent-harness session permalink).  Examples of the forbidden form:

* `https://claude.ai/code/session_019S9v23eC235cqr76MNWe5S`
* `claude.ai/code/session_<any-id>`
* Any other URL whose path identifies a private agent-harness
  conversation.

**Why this rule exists.**

1. *Privacy / opacity.*  A session URL points at a private workspace
   artefact: full transcript, tool calls, intermediate code.  PR
   readers cannot open it; the link is dead from their perspective.
2. *Link rot.*  Sessions expire, compress, or get archived behind
   authentication.  A PR description that points at one will break
   in days or weeks.
3. *Provenance leakage.*  Session URLs embed harness internals
   (Claude Code vs Web vs Action, session-id format) that the PR's
   *content* (theorems, build posture) needn't disclose.
4. *Citation discipline.*  Per the "Names describe content, never
   provenance" rule, release-facing prose must describe what it
   documents, not the workflow that produced it.

**Allowed alternatives — what to cite instead.**

* The Genesis-Plan section number (e.g. `§4.12`, `§12 WU 0.2`).
* The headline theorem name + file path (e.g. `impl_refines_spec`
  in `LegalKernel/Kernel.lean`).
* The relevant workstream-plan document under `docs/`.

**Scope of the rule.**

* **In scope (forbidden):** PR descriptions / bodies; PR review
  comments; PR-edit `body` arguments to
  `mcp__github__update_pull_request`; cross-link inserts via
  `mcp__github__add_issue_comment`,
  `mcp__github__add_reply_to_pull_request_comment`.
* **Out of scope:** local commit messages (the agent harness's
  default `gh commit` template may auto-append a session footer to
  *commits*; this policy concerns *PR-level* surfaces).

**Enforcement.**  Before invoking
`mcp__github__create_pull_request` or
`mcp__github__update_pull_request`, scan the prepared `body` for
the regex
`https?://(?:www\.)?claude\.ai/code/session_[A-Za-z0-9]+` and strip
every match before submission.

## Current development status

**Build tag** (`kernelBuildTag` in `LegalKernel.lean`):
`"canon-encoder-injectivity"` (EI.8.i).  `Test/Umbrella.lean`,
`Lex/Test/M2.lean`, and `Lex/Test/ExampleLex.lean` all pin this
value in regression tests, so any phase / milestone bump must
update the constant and every pinning test in the same PR.

**Test count.**  ~1986 tests across ~100 suites at the time of
the EI milestone (Workstream EI), up from 1907 at the AR
milestone (+79 — 78 of which are the augmented
`encoding-injectivity` suite; the rest are scattered API-
stability checks alongside the new theorems).  The exact number
drifts with every PR; `lake test` is the canonical query.
Unlike the build tag, the test count is not pinned — only its
monotonic growth is
enforced by individual regression tests landing alongside new
theorems.

**Rust-side test count.**  110 tests across 11 non-empty suites at
the RH-A landing (up from 44 at the RH-H baseline — +66 tests
across the two new crypto crates).  `cargo test --workspace` from
`runtime/` is the canonical query.  Test mass breakdown:

  * `canon-cross-stack` — 31 tests (29 unit + 2 integration);
    unchanged since RH-H.
  * `canon-cli-common` — 8 tests; unchanged since RH-H.
  * `canon-verify-secp256k1` — 36 tests (19 unit + 8 known-vector
    + 7 property + 2 cross-stack).
  * `canon-hash-keccak256` — 32 tests (13 unit + 10 known-vector
    + 5 property + 3 cross-stack + 1 integration).
  * Remaining skeleton crates contribute one crate-name
    regression test each (5 total).

The count will continue growing as RH-B onward materialises.

**Workstream RH-H (Rust host workspace + CI harness).**
**Complete.**  Lands the workspace under `runtime/` (11 member
crates: 10 from the plan §2.2 layout plus `canon-cross-stack`
hosting the fixture loader as a separate dev-dep, per the plan
§4 RH-H step 4 "thin Rust helper that other crates import as a
dev-dependency") per `docs/planning/rust_host_runtime_plan.md`
§RH-H.
Headlines:

  * Two fully-implemented crates: `canon-cli-common` (shared
    logging / exit-code / paths helpers) and `canon-cross-stack`
    (cross-stack fixture loader + file-format spec; the
    load-bearing RH-H deliverable that downstream crates dev-dep
    on for byte-equivalence assertions).
  * Eight skeleton crates (RH-A.1, RH-A.2, RH-B, RH-C, RH-D,
    RH-E.0, RH-E.1, RH-F, RH-G — nine if you count RH-E.0 +
    RH-E.1 separately) ready for the implementing work units to
    fill in.  Skeleton binaries exit code `3 = NotImplemented`
    with a deferral message; no C-ABI symbols exported (no
    silently-incorrect fallback verifier / hash adaptor).
  * `runtime/rust-toolchain.toml` pins stable 1.83;
    `workspace.package.rust-version = "1.83"` documents the MSRV
    at the package level.
  * `.github/workflows/ci-rust.yml` runs four gates
    (`cargo build --workspace --all-targets`, `cargo test
    --workspace`, `cargo clippy --workspace --all-targets --
    -D warnings`, `cargo fmt --all -- --check`) on every PR
    that touches `runtime/**`; Lean-only PRs do not trigger the
    Rust workflow.  Third-party action SHAs verified against
    upstream release tags (actions/checkout v4.3.1,
    Swatinem/rust-cache v2.7.7).
  * `unsafe_code = "forbid"`, `missing_docs = "warn"`,
    `clippy::pedantic` enabled workspace-wide.
  * Cross-stack fixture format: 16-byte "CXSF" header (magic +
    version + kind tag + count), per-record `(u32 BE input-len,
    input, u32 BE expected-len, expected)`.  Self-describing,
    bounded-length, byte-deterministic.  Parser is panic-free in
    all non-trivial code paths: `read_u32_be_at` returns
    `Option<u32>` rather than `expect`-on-precondition, and
    every error path returns a typed [`LoaderError`] variant.
  * `Cargo.lock` committed (workspace contains binaries; lockfile
    is a reproducibility requirement).
  * `tempfile` pinned at `~3.14` (newer versions transitively
    require Rust 1.85+ for `edition2024`; pin coupled to
    `rust-toolchain.toml`'s 1.83 channel).

**Workstream RH-A (Cryptographic adaptors).**
**Complete.**  Materialises the two `cdylib` adaptors a Lean
deployment links against to wire the kernel's crypto opaques:
`canon-verify-secp256k1` (RH-A.1) and `canon-hash-keccak256`
(RH-A.2).  See `docs/planning/rust_host_runtime_plan.md` §RH-A.1
/ §RH-A.2 for the closeouts.  Headlines:

  * **RH-A.1 — `canon-verify-secp256k1`.**  Production ECDSA
    secp256k1 verification adaptor.  Exposes the `canon_verify_ecdsa`
    C ABI symbol; a Lean deployment with a matching
    `@[extern "canon_verify_ecdsa"]` declaration on
    `Authority.Crypto.Verify` links here at runtime.  Strict
    input validation (33-byte SEC1-compressed pubkey with 0x02 /
    0x03 prefix, 32-byte pre-hashed message, 64-byte `(r ‖ s)`
    signature), `1 ≤ r < n` and `1 ≤ s < n` bounds (via k256's
    `Signature::from_slice`), and the load-bearing EIP-2 / BIP-62
    low-s canonicalisation enforced via `k256::IsHigh`.  Built
    on `k256 = "0.13"` (no `std`, no signing in the production
    cdylib).  210 cross-stack fixture vectors generated by a
    deterministic RFC-6979 signer (60 valid + 30 high-s + 150
    tampered) committed to
    `runtime/tests/cross-stack/ecdsa_secp256k1.cxsf`.  Property
    tests via `proptest` (256 cases × 7 properties); fresh-sign
    + verify roundtrip is one of them.

  * **RH-A.2 — `canon-hash-keccak256`.**  Production Keccak-256
    (Ethereum-flavoured, NOT FIPS-202 SHA3-256) hash adaptor.
    Exposes three C ABI symbols matching Lean's `@[extern]`
    declarations in `Runtime/Hash.lean`: `canon_hash_bytes`,
    `canon_hash_stream`, `canon_hash_identifier`.  Each
    production binary links the cdylib AHEAD of the
    `canon-hash-fallback.o` forwarder to override the FNV-1a-64
    fallback with the production keccak-256.  Identifier string:
    `"keccak256/EVM-compatible/v1"`.  Built on `sha3 = "0.10"`.
    51 cross-stack fixture vectors covering boundary cases (0,
    1, 31, 32, 33 bytes), block-rate boundaries (135, 136, 137
    bytes — the keccak rate), well-known test vectors (`""`,
    `"abc"`, "the quick brown fox..."), repeated bytes, xorshift-
    seeded pseudorandom data, and a multi-megabyte input.
    Property tests via `proptest` exercise the streaming context
    against the one-shot path on random inputs and random
    chunkings.

  * **C ABI shim design.**  Lean's `lean.h` exposes most of its
    runtime API as `static inline` C functions
    (`lean_sarray_size`, `lean_sarray_cptr`, `lean_dec`, etc.),
    which Rust cannot call directly via `extern "C"`.  Each
    crate ships a tiny C shim (`c/lean_shim.c`) that wraps these
    inlines as non-inline `canon_lean_*` symbols Rust binds to.
    The actual Lean ABI entry point lives in Rust
    (`#[no_mangle] pub unsafe extern "C" fn canon_verify_ecdsa`
    etc.) so `rustc`'s cdylib export discipline keeps the
    symbol in the dynamic-symbol table.  `build.rs` discovers
    `lean.h` via `LEAN_INCLUDE_DIR` → `LEAN_SYSROOT` → `lean
    --print-prefix` → soft-skip; the cfg `canon_lean_ffi` gates
    the Rust-side FFI code, so CI environments without Lean
    still produce a working rlib (without the Lean-facing C
    symbols).  Verified via `nm -D` that the production cdylib
    exports the expected symbol set.

  * **Workspace dependency additions.**  `k256 = "0.13"` (ECDSA),
    `sha3 = "0.10"` (Keccak), `subtle = "2.6"` (constant-time
    primitives), `hex = "0.4"` (dev-only fixture hex), `proptest
    = "1.5"` (dev-only property tests), and `cc = "1.0"`
    (build-script C compiler driver).  All pinned at the
    workspace level; `base64ct` transitively pinned to 1.6.0
    (newer requires Rust 1.85), `proptest` to 1.5.0 (same
    constraint).

  * **Audit posture at landing.**
    - `cargo build --workspace --all-targets` — green.
    - `cargo test --workspace` — 110 tests across 11 non-empty
      suites, all passing.
    - `cargo clippy --workspace --all-targets -- -D warnings` —
      clean.
    - `cargo fmt --all -- --check` — clean.
    - `unsafe_code = "deny"` workspace lint (narrowed from
      `"forbid"` in the two crypto crates; the `unsafe` blocks
      are tightly scoped to the FFI shims with documented
      `# Safety` contracts).
    - Production cdylibs verified to export the expected C ABI
      symbols (`canon_verify_ecdsa`, `canon_hash_bytes`,
      `canon_hash_stream`, `canon_hash_identifier`) via `nm -D`.

**Workstream AR (Audit Remediation, see
`docs/planning/audit_remediation_plan.md`)** is the most recent landing.
Highlights of the AR remediation pass:

  * AR.1: shared `Authority.signedActionDomain` constant (M-7).
  * AR.2: `RuntimeState.deploymentId` field threaded through
    `processSignedAction` / `bootstrap` / `replayWith` /
    `checkSignatureInvalidWith` plus `--deployment-id <hex>` CLI
    flag on both `canon` and `canon-replay` (the audit binary
    refuses to run without it).  Closes M-1 + M-5.
  * AR.2.5: parameterised `checkEvidenceWith verify d`
    dispatcher in `Disputes/Evidence.lean` so the
    `signatureInvalid` claim arm routes through
    `checkSignatureInvalidWith` with an explicit deploymentId.
    Plain `checkEvidence` is preserved as the back-compat alias
    `checkEvidenceWith Verify ByteArray.empty`.  Closes the
    cross-deployment-replay observability gap surfaced by the
    third audit pass at the dispute pipeline's Stage 2.
  * AR.3: `bootstrapFromSnapshot` chain-anchor check
    (`.anchorMismatch`) + `bootstrapFromAttestedSnapshot` wrapper.
    Closes M-2.
  * AR.5 / AR.6: regression pins for all 19 `Action` and 16 `Event`
    constructor indices (M-8, m-7).  New `Event.tag` projection.
  * AR.7: `Lex.Tools.Diff` widened to compare type + kind + tactic
    body, not just names (M-6).
  * AR.9: new `mock_import_audit` binary mechanically enforces
    "no production module imports `Test/*`" (M-10).
  * AR.10: real `@[extern]` annotations on `hashBytes` /
    `hashStream` / `hashImplementationIdentifier`, with default
    `runtime/canon-hash-fallback.c` forwarder + Lake `extern_lib`
    `canonHashFallback`.  Closes the cross-verification M+1
    finding.
  * AR.11: `synth_local_kindOnly` now refuses to admit
    resource-bearing statements without resource info; the new
    `dispatchSynthesizerResourceAware` is the production entry.
    Closes M+2.
  * AR.12: `lexlaw`'s `renderSyntax` uses `Syntax.reprint` for
    byte-fidelity with user source.  L010 / L022 lints exempted
    for kernel-built-in laws (`legalkernel.*` prefix).  Closes
    m-13.
  * AR.16 + AR.17: `Verdict.decode` enforces explicit
    signers/sigs length-match (m-17); `kernelOnlyApply`'s wildcard
    arm replaced by an exhaustive per-`Action`-constructor match
    (m-14).
  * AR.19: `fileDispute_rejects_indexOutOfRange` /
    `_duplicateDispute` theorems.
  * AR.20: `.github/CODEOWNERS` request-for-review surface for
    TCB-core files.
  * AR.21: `withdraw.pre` strengthened with positivity (`0 <
    amount`).  Closes m-4.

**Workstream EI (Encoder Injectivity).**  **Complete.**  The
AR.4 deferral closed.  The fault-proof chain now lifts from
bytes-equality to extensional state equality via
`commitExtendedState_subcommits_extensional_eq_under_collision_free`
(`FaultProof/Commit.lean`, EI.8.b).  All eight sub-units (EI.0 –
EI.8) shipped under their respective branches; the engineering
plan and per-sub-unit retrospectives live in
`docs/planning/encoder_injectivity_plan.md`.

**Deferred from AR:**

    **EI.0 pre-flight + scaffolding complete** on
    `claude/review-encoder-plan-0p5MI`
    (`docs/planning/encoder_injectivity_plan.md` §4.0): Std-core
    lemma audit confirms the proof recipe's preconditions are
    present in the pinned toolchain (`docs/std_dependencies.md`'s
    "EI.0.a" subsection), module-placement decision recorded in
    Appendix D OQ-EI-1, and the test scaffolding lives at
    `LegalKernel/Test/Encoding/Injectivity.lean` (wired into
    `Tests.lean` under the `"encoding-injectivity"` suite name).

    **EI.1 helper / atomic-injectivity foundation complete** on
    `claude/atomic-injectivity-foundation-yHSwQ`
    (`docs/planning/encoder_injectivity_plan.md` §4.1).  Eight
    non-conditional sub-sub-units shipped (EI.1.a was dropped at
    EI.0.a per the Std-core audit, so the §13.6 two-reviewer gate
    is **not** triggered):

      - **EI.1.b** `Encodable.Encodable_via_decode_inj` +
        `_append` residual-suffix variant
        (`LegalKernel/Encoding/Encodable.lean`).
      - **EI.1.c** `cborHeadEncode_injective`
        (`LegalKernel/Encoding/CBOR.lean`) — extracts
        `major₁ = major₂ ∧ n₁ = n₂` under both `< 2^64` bounds.
      - **EI.1.d** `encodeAsBytes_eq_injective_of_encode_eq_injective`
        (in `Encodable.lean`) + `encodeAsBytes_equiv_injective_of_encode_equiv_injective`
        (in `State.lean`, where `Std.TreeMap.Equiv` is in scope).
      - **EI.1.e** `encodeSortedPairs_injective` (universal
        round-trip variant) + `encodeSortedPairs_injective_bounded`
        (per-list round-trip variant) + private
        `decodeNPairs_encode_foldr` / `decodeNPairs_encode_foldr_in`
        helpers (`LegalKernel/Encoding/State.lean`) — the headline
        polymorphic map-level injectivity lemma EI.2 – EI.7 consume.
        The `_bounded` variant is the one downstream sub-states
        actually use, because their pair lists key on `Nat` (via
        `.toNat`) where `Nat`'s round-trip is conditional on
        `< 2^64`.  The unbounded variant covers UIntN-typed pair
        lists (unconditional round-trip).
      - **EI.1.f** `uInt8_encode_injective` /
        `uInt16_encode_injective` / `uInt32_encode_injective` /
        `uInt64_encode_injective` quartet
        (`LegalKernel/Encoding/Encodable.lean`).
      - **EI.1.g** Project-wrapper injectivity sweep
        (`LegalKernel/Encoding/State.lean`): `actorId_*`,
        `resourceId_*` (unconditional, delegated to UInt64);
        `amount_*`, `nonce_*`, `depositId_*`, `withdrawalId_*`,
        `publicKey_*` (conditional on `< 2^64`).  `EthAddress` is
        EI.7.a, not EI.1.g.
      - **EI.1.h** `list_encode_injective` (conditional on length
        bound) + `option_encode_injective` (unconditional)
        (`LegalKernel/Encoding/Encodable.lean`).
      - **EI.1.i** `Encodable.HasInjective` ergonomic class with
        six instances (Bool, BoundedNat, UInt8/16/32/64;
        ActorId / ResourceId resolve through UInt64 via
        `abbrev`).  Conditional types intentionally lack
        instances — they keep their bound-quantified
        explicit-hypothesis lemmas.

    Audit posture: `lake build` / `lake test` / every audit
    binary green; `#print axioms` ⊆ `[propext, Classical.choice,
    Quot.sound]` on every shipped lemma; no new opaques, no new
    axioms, no TCB-tier change.

    **EI.2 nested-map template complete** on
    `claude/implement-state-encode-nested-nbXhh`
    (`docs/planning/encoder_injectivity_plan.md` §4.2).  Six
    sub-sub-units shipped:

      - **EI.2.a** `BalanceMap.encode_injective`
        (`LegalKernel/Encoding/StateInjective.lean`) — inner-map
        injectivity (conditional on length + per-amount bounds),
        concluding `Std.TreeMap.Equiv` on the inner map.  Uses
        `encodeSortedPairs_injective_bounded` (EI.1.e) at
        `(Nat, Amount)`; lifts the `a.toNat` projection through
        `UInt64.toNat_inj` and `List.map_inj_right`, then via
        `Std.TreeMap.equiv_iff_toList_eq` to `Equiv`.
      - **EI.2.b** `BalanceMap.encode_injective_to_equiv` —
        explicit `Equiv`-shaped alias (EI.2.a already concludes
        `Equiv`, so this collapses to a re-export).
      - **EI.2.c** `BalanceMap.encodeAsBytes_injective` —
        framing injectivity for the byte-wrapped inner encoder.
        OQ-EI-2 resolved to option (a): `BalanceMap.encodeAsBytes`
        promoted from `private` to non-private so framing-
        injectivity can co-locate with EI.2.a / EI.2.d in
        `StateInjective.lean`.
      - **EI.2.d** `State.Equiv` (custom nested extensional
        relation) + `State.encode_injective` (the headline
        nested theorem).  `State.Equiv` asserts outer-key
        agreement (via `Iff` on `r ∈ s.balances`) plus
        per-resource inner-`BalanceMap` `Equiv`, since
        `Std.TreeMap.Equiv` on the outer `balances` map would
        require structural `Eq` on inner `BalanceMap`s — too
        strong, since the encoder canonicalises away RB-tree
        shape.  Helpers: `outer_keys_agree` (`Iff` form),
        `outer_isSome_eq` (`Bool` form), `inner_equiv`, `refl`,
        `symm`, and the flat `getBalance_eq` corollary.
      - **EI.2.e** 17 new test cases in
        `LegalKernel/Test/Encoding/Injectivity.lean` covering
        term-level API stability, positive injectivity
        (distinct inputs → distinct encodings), negative
        determinism (structurally-distinct extensionally-equal
        inputs → identical encodings), and value-level smoke
        checks on the `State.Equiv` corollaries (`refl`, `symm`,
        `outer_isSome_eq`, `getBalance_eq`).  Total
        `encoding-injectivity` suite: 49 cases (was 32 pre-EI.2).
      - **EI.2.f** Retrospective recorded in
        `docs/planning/encoder_injectivity_plan.md` §4.2 closeout
        block: `Equiv`-as-target was a net win; EI.3 – EI.7
        should follow the inline-framing pattern (rather than
        EI.1.d's universal-quantifier helper) for their
        conditional-bounds injectivity proofs.

    Axiom posture: `#print axioms` ⊆ `[propext,
    Classical.choice, Quot.sound]` on every EI.2 theorem;
    `lake build` / `lake test` / every audit binary green.

  * **EI.3 – EI.8 status (flat-map sub-states + composition).**
    **Complete.**  All landed on
    `claude/encoder-injectivity-implementation-UggQv`.

      - **EI.3** `NonceState.encode_injective` +
        `expectedNonce_eq_of_encode_eq` corollary
        (`LegalKernel/Encoding/StateInjective.lean`).
      - **EI.4** `KeyRegistry.encodeMap_injective`
        (`LegalKernel/Encoding/StateInjective.lean`).
      - **EI.5** `LocalPolicy.encodeAsBytes_injective` +
        `LocalPolicies.encodeMap_injective` +
        `LocalPolicies.lookup_eq_of_encode_eq` corollary
        (`LegalKernel/Encoding/LocalPolicyInjective.lean`).
        Inner-record injectivity (`localPolicy_encode_injective`,
        `localPolicyClause_encode_injective`) was already shipped
        in `Encoding/LocalPolicy.lean` and is reused as-is.
      - **EI.6** `Bridge.DepositRecord.encode_injective` +
        `Bridge.DepositRecord.encodeAsBytes_injective` +
        `Bridge.BridgeState.encodeConsumed_injective`
        (`LegalKernel/Encoding/BridgeInjective.lean`).
      - **EI.7** `Bridge.EthAddress.toBytes_injective` +
        `Bridge.PendingWithdrawal.encode_injective` +
        `Bridge.PendingWithdrawal.encodeAsBytes_injective` +
        `Bridge.BridgeState.encodePending_injective` +
        `Bridge.BridgeState.encode_injective`
        (`LegalKernel/Encoding/BridgeInjective.lean`).
        Precursors `pendingWithdrawal_roundtrip` and
        `encodeSortedPairs_self_delim_split` ship alongside in
        `LegalKernel/Encoding/State.lean`.
      - **EI.8.a/b** `ExtendedState.extEq` definition +
        `ExtendedState.extEq.refl` + `ExtendedState.CanonicalBounds`
        bundle + headline composition theorem
        `commitExtendedState_subcommits_extensional_eq_under_collision_free`
        (`LegalKernel/FaultProof/Commit.lean`).  Retires
        CLAUDE.md footnote 1.
      - **EI.8.i** `kernelBuildTag` bumped to
        `"canon-encoder-injectivity"`; `Test/Umbrella.lean`,
        `Lex/Test/M2.lean`, and `Lex/Test/ExampleLex.lean` all
        updated to pin the new value.

    Visibility note: `LocalPolicy.encodeAsBytes`,
    `Bridge.DepositRecord.encodeAsBytes`, and
    `Bridge.PendingWithdrawal.encodeAsBytes` were promoted from
    `private` to non-private (per OQ-EI-2 option (a)) so the
    per-sub-state framing-injectivity lemmas can co-locate with
    their headline siblings in the `*Injective.lean` files rather
    than being forced inside the encoder definitions.

    Axiom posture: `#print axioms` ⊆ `[propext, Classical.choice,
    Quot.sound]` on every EI.3 – EI.8 theorem; `lake build` /
    `lake test` / every audit binary green.  29 new test cases
    bring the `encoding-injectivity` suite from 49 to 78 cases.

  * **AR.18 mechanical visibility** (the `private`-modifier
    promotion for `applyVerdictUnchecked`) is documented in the
    function's docstring but not lexically enforced — Lean 4's
    `private` is file-local, and the legitimate cross-file
    callers (`Rewards.applyVerdictWithRewardsUnchecked`,
    `Rewards.applyVerdictWithRewardsMultiUnchecked`) would need to
    be moved into `Verdict.lean` to make `private` work.  AR.18's
    review-gate contract (a clearly-labelled "UNCHECKED — TESTING
    ONLY" docstring) remains the operational guard.  See
    `docs/GENESIS_PLAN.md` §15C.6 for the deferral rationale.

**TCB audit (latest run).**  `#print axioms` on every kernel,
Phase-2, Phase-3, Phase-4, Phase-5, Phase-6, and Workstream-H
theorem returns a subset of `[propext, Classical.choice,
Quot.sound]`.  No custom axioms have been introduced in any phase.
`Verify` and `hashBytes` are `opaque`, not `axiom`, so they do
not appear in the audit output of theorems that mention them.
Workstream H adds one new opaque (`l1FaultProofVerifier` in
`LegalKernel/FaultProof/Witness.lean`) for the deployment-side L1
event watcher; per the same opaque pattern as `Verify` / `hashBytes`,
it does not appear in `#print axioms` output.

**TCB import discipline.**  `Tools.Common.tcbInternalImports`
enumerates the project-internal modules each TCB-core file
(`Kernel.lean`, `RBMapLemmas.lean`) may import — only
`LegalKernel.Kernel` and `LegalKernel.RBMapLemmas` themselves.
This is a *specific allowlist*, not a `LegalKernel.*` namespace
pattern: a TCB-core file that tries to import e.g.
`LegalKernel.Laws.Transfer` fails the audit and blocks the merge.

**Test patterns.**  Tests use two complementary patterns:

1. **Value-level**: assert `==` between expected and actual results
   (catches definitional drift / Std-API renames at runtime).
2. **Term-level API stability**: ascribe a `let _proof : T :=
   theorem ...` binding whose type uses the theorem's exact
   signature (catches signature changes at elaboration time,
   before the `IO Unit` body runs).

The `Authority.SignedAction` suite uses term-level API checks for
`nonce_uniqueness` and `replay_impossible` (rather than value-level
admissibility witness construction) because the `Verify` opaque
cannot be reduced at the Lean level — the runtime adaptor wires
the actual cryptographic implementation.  The algebraic core of
the theorems (the post-advance nonce inequality) is value-level
checked separately.  The shared `LegalKernel/Test/MockCrypto.lean`
module supplies `mockVerify` / `mockSign` for happy-path coverage
that the production opaque `Verify` (which returns `false` at the
Lean level) cannot exercise.

**Active development history.**  Per-audit and per-WU completion
narratives live in git history (see `git log --grep="WU"` /
`git log --grep="audit"`), not in this file.  Each major audit
pass produces both a commit and (typically) a Genesis-Plan
amendment in `docs/GENESIS_PLAN.md`; consult that document for the
formal status of every property.

## Vulnerability reporting

Canon is research-stage software.  If you discover a logic bug in
the kernel module (e.g. a counterexample to `impl_noop_if_not_pre`,
or a state advance that bypasses the `if` in `step_impl`), open an
issue with the `kernel-soundness` label.  Such reports gate any
in-flight PR; the two-reviewer rule applies to the fix.

For non-kernel issues (laws, tooling, documentation), the standard
issue tracker workflow applies.
