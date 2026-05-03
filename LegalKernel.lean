/-
LegalKernel — umbrella module.

Re-exports the trusted core (`Kernel.lean`) and the law set the
deployment chooses to admit.  Phase 0 ships exactly one law: the
canonical `transfer` of §4.11.  Phase 2 adds `mint`, `burn`, and
`freeze`; Phase 3 layers an authority module above this point.

Importing `LegalKernel` is the recommended entry point for downstream
modules and tests; do *not* import `LegalKernel.Kernel` directly except
when you specifically need the trusted-core surface in isolation
(e.g. the `tcb_audit` tool of WU 1.11).
-/

import LegalKernel.Kernel
import LegalKernel.Laws.Transfer
