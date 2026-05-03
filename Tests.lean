/-
Tests — root of the `lake test` driver.

Imports every test module, runs them in sequence, and exits non-zero
if any test failed.  The test driver is wired to this binary via
`@[test_driver]` in `lakefile.lean`.

Phase 0 ships kernel-level, umbrella-level, and transfer-law tests;
later phases will append modules here as new laws and invariants
land.
-/

import LegalKernel.Test.Framework
import LegalKernel.Test.KernelTests
import LegalKernel.Test.Umbrella
import LegalKernel.Test.Laws.Transfer

open LegalKernel.Test

/-- Test-driver entry point.  Returns `0` when every suite passes,
    `1` when any test fails. -/
def main : IO UInt32 := do
  let mut failed : Nat := 0
  failed := failed + (← runAll "kernel"   KernelTests.tests)
  failed := failed + (← runAll "umbrella" Umbrella.tests)
  failed := failed + (← runAll "transfer" Laws.TransferTests.tests)
  if failed = 0 then
    IO.println "ALL TESTS PASSED"
    pure 0
  else
    IO.println s!"{failed} TESTS FAILED"
    pure 1
