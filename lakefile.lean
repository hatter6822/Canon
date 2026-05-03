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
  -- Per-package Lean options.  Phase 0's hygiene gate:
  --
  -- * `autoImplicit := false` — every universe / type variable must
  --   be declared explicitly; Lean must not auto-introduce them
  --   (Genesis Plan §13.6, "Decidability discipline" in CLAUDE.md).
  -- * `relaxedAutoImplicit := false` — same rule, even for "section
  --   variables", which are otherwise auto-bound under the relaxed
  --   form.
  -- * `linter.unusedVariables := true` — surfaces dead bindings.
  -- * `linter.missingDocs := true` — every public surface must have
  --   a `/-- … -/` docstring.  CLAUDE.md mandates this; promoting it
  --   to a build-time check prevents drift.
  leanOptions := #[
    ⟨`autoImplicit, false⟩,
    ⟨`relaxedAutoImplicit, false⟩,
    ⟨`linter.unusedVariables, true⟩,
    ⟨`linter.missingDocs, true⟩
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
