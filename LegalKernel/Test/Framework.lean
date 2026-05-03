/-
LegalKernel.Test.Framework — micro test harness.

A deliberately tiny test runner: each test is an `IO Unit` that
throws (via `IO.userError`) on failure.  The umbrella runner
catches errors per test, prints a one-line PASS/FAIL banner, and
returns a non-zero exit code if any test failed.

We do not depend on a third-party test framework (no LSpec, no
Plausible) because Phase 0's core acceptance gate is "no external
deps beyond Lean core".  Phase 1+ may layer property-based testing
on top of this scaffold.

This module also exposes `LegalKernel.Test.emptyState`, the canonical
"no balances anywhere" state.  Test modules build their fixtures on
top of it so that fresh-state construction lives in exactly one place.
-/

import LegalKernel.Kernel

namespace LegalKernel.Test

/-- The empty deployment state: no resource has any actor balance.
    Every `getBalance _ _` query against `emptyState` returns `0`. -/
def emptyState : LegalKernel.State := { balances := ∅ }

/-- A single named test. -/
structure TestCase where
  name : String
  body : IO Unit

/-- Result of running a single test. -/
inductive Outcome
  | pass
  | fail (msg : String)

/-- Run one test, reporting PASS/FAIL to stdout. -/
def runOne (t : TestCase) : IO Outcome := do
  try
    t.body
    IO.println s!"  PASS  {t.name}"
    pure .pass
  catch e =>
    let msg := e.toString
    IO.println s!"  FAIL  {t.name}"
    IO.println s!"        {msg}"
    pure (.fail msg)

/-- Run every test in `ts`, printing a summary banner.  Returns the
    number of failures. -/
def runAll (suite : String) (ts : List TestCase) : IO Nat := do
  IO.println s!"== {suite} =="
  let mut failures := 0
  for t in ts do
    match (← runOne t) with
    | .pass     => pure ()
    | .fail _   => failures := failures + 1
  if failures = 0 then
    IO.println s!"-- {suite}: {ts.length} passed"
  else
    IO.println s!"-- {suite}: {failures}/{ts.length} FAILED"
  pure failures

/-- Throw `IO.userError` if `cond` is false. -/
def assert (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

/-- Throw if `actual ≠ expected`.  `expected` and `actual` must be
    `Repr`-printable. -/
def assertEq {α : Type _} [BEq α] [Repr α]
    (expected actual : α) (where_ : String := "") : IO Unit :=
  if expected == actual then
    pure ()
  else
    throw <| IO.userError <|
      s!"assertEq{if where_.isEmpty then "" else " (" ++ where_ ++ ")"}: " ++
      s!"expected {repr expected}, got {repr actual}"

end LegalKernel.Test
