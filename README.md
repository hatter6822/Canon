# Canon - A Legal Kernel

A formally grounded, implementation-oriented constitutional kernel built in
Lean 4. The Legal Kernel is a **proof-carrying state transition system** in
which legality is a type, every state change is accompanied by a
machine-checkable proof of admissibility, and global system properties are
guaranteed by inductive invariants rather than by trust in operators.

The full architectural and mathematical blueprint, including the formal
kernel, mathematical guarantees, threat model, and phased implementation
roadmap, lives in:

- [docs/GENESIS_PLAN.md](docs/GENESIS_PLAN.md)

That document is the canonical source of truth for the project's design
philosophy, formal model, and implementation strategy. Start there.

## Status

| Phase | Title              | Status      |
|-------|--------------------|-------------|
| 0     | Foundations        | Complete    |
| 1     | Kernel completion  | Not started |
| 2+    | (see Genesis Plan) | Not started |

Phase 0 ships the trusted-core kernel module (`LegalKernel/Kernel.lean`,
the literal §4.12 listing), the canonical `transfer` law
(`LegalKernel/Laws/Transfer.lean`, §4.11 with the self-transfer
sequencing fix), a Lake build, a `lake test` driver covering 21 unit
tests across both modules, and a GitHub Actions CI workflow that blocks
on build or test failure.

## Quickstart

Canon depends only on a pinned Lean 4 toolchain — no Mathlib, no
external Lake packages.  The toolchain version is read from
`lean-toolchain`.

```bash
# 1. Install elan (Lean's toolchain manager) once per machine.
curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
  | sh -s -- -y --default-toolchain none

# 2. Pre-fetch the pinned toolchain.
elan toolchain install "$(cat lean-toolchain)"

# 3. Build the project (downloads nothing further).
lake build

# 4. Run the test driver.
lake test
```

A scripted version of the above lives in `scripts/setup.sh`; running
that script makes a fresh checkout buildable without any manual steps.

The CI workflow in `.github/workflows/ci.yml` executes the same `lake
build` and `lake test` on every pull request, so a green CI is the
authoritative signal that Phase-0 acceptance criteria still hold.

## Repository layout

```
canon/
├── lakefile.lean             -- Lake package config (default target +
│                                test driver).
├── lean-toolchain            -- pinned Lean version (Section 13.4).
├── Main.lean                 -- placeholder runtime; replaced in Phase 5.
├── Tests.lean                -- @[test_driver]; runs every test module.
├── LegalKernel.lean          -- umbrella import (kernel + laws).
├── LegalKernel/
│   ├── Kernel.lean           -- §4.12; trusted core (TCB).
│   ├── Laws/
│   │   └── Transfer.lean     -- §4.11; canonical transfer law.
│   └── Test/
│       ├── Framework.lean    -- minimal IO-based test harness.
│       ├── KernelTests.lean  -- value-level kernel tests (10).
│       └── Laws/
│           └── Transfer.lean -- transfer-law tests (11), incl. the
│                                §4.11 self-transfer regression.
├── scripts/
│   └── setup.sh              -- one-shot toolchain + build script.
├── .github/workflows/
│   └── ci.yml                -- lake build + lake test on PR / push.
├── CLAUDE.md                 -- guidance for Claude / coding agents.
└── docs/
    └── GENESIS_PLAN.md       -- canonical design document.
```

## Design invariants enforced in Phase 0

Even at this stage, the build mechanically guarantees:

1. **Determinism** — `step_impl` is a Lean function, so its output is
   uniquely determined by its inputs (§5.1).
2. **No silent illegality** — `impl_noop_if_not_pre` proves a failed
   precondition leaves state untouched (§4.6).
3. **Refinement** — `impl_refines_spec` proves every executed step
   satisfies the relational specification (§4.6).
4. **Invariant preservation theorem** — `invariant_preservation` and
   `invariants_compose` are proved at the abstract `Transition` level
   (§4.10), so future laws inherit the global guarantee for free.

These four properties are not stubs: they are real Lean theorems that
the build will not accept with a `sorry`.  Run `grep -rn 'sorry'
LegalKernel/` to verify.

## Contributing

Read `docs/GENESIS_PLAN.md` end-to-end first — every change beyond the
trivial must reference a work unit (`WU x.y`) and follow the runbooks of
§13.6–§13.9.  Kernel-touching work units require two reviewers.  See
`CLAUDE.md` for the conventions any AI coding agent must follow when
working in this repository.

## License

See [LICENSE](LICENSE).
