/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Test.Runtime.Loop — Phase-5 WU 5.1 tests for the
runtime main loop (`processSignedAction` and `bootstrap`).

We exercise:

  * `bootstrap` of an empty log returns a fresh runtime with
    `logIndex = 0` and `prevHash = zeroHash`.
  * `processSignedAction` rejects an inadmissible action (the
    Verify stub returns false) with `notAdmissible`.
  * `processBatch` threads the runtime state through multiple
    actions correctly (every entry produces either an `OK` or a
    `notAdmissible` result).
  * Determinism: `processPure` is a pure function of its inputs.

**Verify-opaque caveat.**  See `Test/Runtime/Replay.lean` for the
full discussion.  Key implication: every `processSignedAction`
test that doesn't explicitly *expect* failure will fail (because
Verify returns false in the test runtime).  We test the rejection
path as the primary positive evidence that the runtime is wired
correctly.
-/

import LegalKernel.Test.Framework
import LegalKernel.Runtime.Loop

namespace LegalKernel.Test.Runtime
namespace LoopTests

open LegalKernel
open LegalKernel.Authority
open LegalKernel.Runtime
open LegalKernel.Encoding

/-- Test policy: unrestricted. -/
def policy : AuthorityPolicy := AuthorityPolicy.unrestricted

/-- A genesis state: actor 1 holds 100 of resource 1. -/
def genesis : ExtendedState :=
  { base    := setBalance ({ balances := ∅ }) 1 1 100
  , nonces  := { next := ∅ }
  , registry := KeyRegistry.empty }

/-- A signed action.  Will fail admissibility because Verify=false. -/
def transferAction : SignedAction :=
  { action := .transfer 1 1 2 30
  , signer := 1
  , nonce  := 0
  , sig    := ⟨#[]⟩ }

/-- `bootstrap` of an empty log returns the fresh runtime state. -/
def bootstrapEmpty : TestCase := {
  name := "bootstrap of missing log returns fresh runtime"
  body := do
    let path := System.FilePath.mk "/tmp/canon-test-loop-empty.bin"
    if (← path.pathExists) then
      IO.FS.removeFile path
    match (← bootstrap policy genesis path) with
    | .ok (rs, frameErr?) =>
      assertEq (0 : Nat) rs.logIndex "logIndex"
      assertEq (zeroHash.toList) (rs.prevHash.toList) "prevHash"
      if frameErr?.isSome then
        throw <| IO.userError "unexpected truncation diagnostic"
    | .error e => throw <| IO.userError s!"bootstrap failed: {repr e}"
}

/-- `processSignedAction` rejects an inadmissible action.  Verify
    returns false in tests, so the signature-clause of `Admissible`
    fails. -/
def processInadmissible : TestCase := {
  name := "processSignedAction rejects inadmissible action"
  body := do
    let path := System.FilePath.mk "/tmp/canon-test-loop-rej.bin"
    if (← path.pathExists) then
      IO.FS.removeFile path
    let rs : RuntimeState :=
      { policy := policy, state := genesis, prevHash := zeroHash
      , logIndex := 0, logPath := path }
    match (← processSignedAction rs transferAction) with
    | .ok _ =>
      throw <| IO.userError "BUG: accepted inadmissible action"
    | .error .notAdmissible =>
      -- Verify the file was NOT touched.
      let present ← path.pathExists
      if present then
        throw <| IO.userError "BUG: file written despite admissibility failure"
}

/-- `processBatch` threads state through multiple inadmissible
    actions, returning a list of `notAdmissible` results in the
    same order. -/
def processBatchAllReject : TestCase := {
  name := "processBatch returns one rejection per inadmissible action"
  body := do
    let path := System.FilePath.mk "/tmp/canon-test-loop-batch.bin"
    if (← path.pathExists) then
      IO.FS.removeFile path
    let rs : RuntimeState :=
      { policy := policy, state := genesis, prevHash := zeroHash
      , logIndex := 0, logPath := path }
    let actions := [transferAction, transferAction, transferAction]
    let (rs', results) ← processBatch rs actions
    assertEq (3 : Nat) results.length "result count"
    assertEq (0 : Nat) rs'.logIndex "logIndex unchanged"
    -- Verify all rejections.
    let mut rejections := 0
    for r in results do
      match r with
      | .error _ => rejections := rejections + 1
      | .ok _ => pure ()
    assertEq (3 : Nat) rejections "all three rejected"
}

/-- `processPure` is deterministic: equal inputs yield equal
    outputs. -/
def processPureDeterministic : TestCase := {
  name := "processPure is deterministic"
  body := do
    let path := System.FilePath.mk "/tmp/canon-test-loop-pure.bin"
    let rs : RuntimeState :=
      { policy := policy, state := genesis, prevHash := zeroHash
      , logIndex := 0, logPath := path }
    let r1 := processPure rs transferAction
    let r2 := processPure rs transferAction
    -- Compare results.
    match r1, r2 with
    | .error _, .error _ => pure ()
    | .ok _, .ok _ => pure ()
    | _, _ => throw <| IO.userError "non-deterministic processPure"
}

/-- `processPure` rejects the inadmissible action (Verify=false). -/
def processPureRejection : TestCase := {
  name := "processPure rejects inadmissible action"
  body := do
    let path := System.FilePath.mk "/tmp/canon-test-loop-pure-rej.bin"
    let rs : RuntimeState :=
      { policy := policy, state := genesis, prevHash := zeroHash
      , logIndex := 0, logPath := path }
    match processPure rs transferAction with
    | .ok _ => throw <| IO.userError "BUG: accepted inadmissible action"
    | .error .notAdmissible => pure ()
}

/-- Term-level API: `processPure_deterministic`. -/
def deterministicAPI : TestCase := {
  name := "processPure_deterministic API stability"
  body := do
    let _proof : ∀ (rs₁ rs₂ : RuntimeState) (st₁ st₂ : SignedAction),
                   rs₁ = rs₂ → st₁ = st₂ →
                   processPure rs₁ st₁ = processPure rs₂ st₂ :=
      processPure_deterministic
    pure ()
}

/-- All tests. -/
def tests : List TestCase :=
  [bootstrapEmpty, processInadmissible, processBatchAllReject,
   processPureDeterministic, processPureRejection, deterministicAPI]

end LoopTests
end LegalKernel.Test.Runtime
