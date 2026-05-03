/-
LegalKernel.Test.Umbrella — value-level tests for the umbrella module.

Tests that target `LegalKernel.lean` directly (the umbrella
re-export), as opposed to the trusted-core `LegalKernel.Kernel`.  In
Phase 0 the only umbrella-level surface that warrants a runtime test
is `kernelBuildTag`, which is consumed by `Main.lean` and serves as
a link-time confirmation that the kernel module compiled.

Future phases will add tests here when the umbrella grows additional
non-TCB conveniences.
-/

import LegalKernel
import LegalKernel.Test.Framework

open LegalKernel
open LegalKernel.Test

namespace LegalKernel.Test.Umbrella

/-- Tests for the umbrella module's non-TCB surface. -/
def tests : List TestCase :=
  [ { name := "kernelBuildTag is non-empty"
    , body := do
        assert (kernelBuildTag.length > 0) "kernel build tag empty"
    }
  ]

end LegalKernel.Test.Umbrella
