import Lake
open Lake DSL

/--
Canon — A Legal Kernel.

Phase 0 of the Genesis Plan (`docs/GENESIS_PLAN.md`, §12) lays down the
build skeleton: a pinned Lean toolchain, a Lake package, the trusted-core
kernel module, the canonical `transfer` law, and a CI pipeline.  The
kernel is intentionally `Std`-only — no Mathlib dependency, no external
Lean packages — so that the trusted computing base equals exactly the
Lean core distribution plus this repository.
-/
package canon where
  -- Treat all warnings as errors; the kernel must compile cleanly.
  -- Per-module overrides may relax this for tests if absolutely needed.
  leanOptions := #[
    ⟨`autoImplicit, false⟩,
    ⟨`relaxedAutoImplicit, false⟩,
    ⟨`linter.unusedVariables, true⟩,
    ⟨`linter.missingDocs, false⟩
  ]

/-- The trusted core: kernel module, plus the law set that the deployment
    chooses to admit.  See `LegalKernel.lean` for the umbrella import. -/
@[default_target]
lean_lib LegalKernel where
  roots := #[`LegalKernel]

/-- Test driver: a thin executable that imports every test module and
    fails (non-zero exit) if any property check raises. `lake test`
    invokes this binary via the `@[test_driver]` attribute. -/
@[test_driver]
lean_exe Tests where
  root := `Tests
  supportInterpreter := true

/-- Placeholder driver executable.  Phase 5 of the Genesis Plan
    (`Runtime/Loop.lean`) will replace this with the real runtime. -/
lean_exe canon where
  root := `Main
