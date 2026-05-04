/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Test.Events.Types — Phase-5 WU 5.6 tests for the
`Event` inductive.
-/

import LegalKernel.Test.Framework
import LegalKernel.Events.Types

namespace LegalKernel.Test.Events
namespace TypesTests

open LegalKernel.Events
open LegalKernel.Authority

/-- `balanceChanged` is classified as a balance change. -/
def isBalanceChangeT : TestCase := {
  name := "balanceChanged.isBalanceChange = true"
  body := do
    let e : Event := .balanceChanged 1 2 30 40
    assertEq true e.isBalanceChange "isBalanceChange"
}

/-- `nonceAdvanced` is not a balance change. -/
def isBalanceChangeF : TestCase := {
  name := "nonceAdvanced.isBalanceChange = false"
  body := do
    let e : Event := .nonceAdvanced 5 0 1
    assertEq false e.isBalanceChange "isBalanceChange"
}

/-- `identityRegistered` is a registry change. -/
def isRegistryChangeT : TestCase := {
  name := "identityRegistered.isRegistryChange = true"
  body := do
    let e : Event := .identityRegistered 7 ⟨#[0x01]⟩
    assertEq true e.isRegistryChange "isRegistryChange"
}

/-- `identityRevoked` is a registry change. -/
def isRegistryChangeRevoked : TestCase := {
  name := "identityRevoked.isRegistryChange = true"
  body := do
    let e : Event := .identityRevoked 9
    assertEq true e.isRegistryChange "isRegistryChange"
}

/-- The `actor` projection returns `some` for actor-bearing events. -/
def actorProj : TestCase := {
  name := "Event.actor returns expected projection"
  body := do
    assertEq (some (5 : ActorId))
      ((Event.balanceChanged 1 5 30 40).actor) "balanceChanged actor"
    assertEq (some (7 : ActorId))
      ((Event.nonceAdvanced 7 0 1).actor) "nonceAdvanced actor"
    assertEq (none : Option ActorId)
      ((Event.timeRecorded 100).actor) "timeRecorded actor"
}

/-- The `resource` projection returns `some` only for `balanceChanged`. -/
def resourceProj : TestCase := {
  name := "Event.resource projection matches expectation"
  body := do
    assertEq (some (1 : ResourceId))
      ((Event.balanceChanged 1 5 30 40).resource) "balanceChanged resource"
    assertEq (none : Option ResourceId)
      ((Event.nonceAdvanced 7 0 1).resource) "nonceAdvanced resource"
}

/-- Equal events compare equal under DecidableEq. -/
def decEq : TestCase := {
  name := "Event DecidableEq matches structural equality"
  body := do
    let e₁ : Event := .balanceChanged 1 2 30 40
    let e₂ : Event := .balanceChanged 1 2 30 40
    let e₃ : Event := .balanceChanged 1 2 30 41
    if e₁ == e₂ then pure ()
    else throw <| IO.userError "BUG: equal events compared unequal"
    if e₁ == e₃ then
      throw <| IO.userError "BUG: distinct events compared equal"
    else pure ()
}

/-- All tests. -/
def tests : List TestCase :=
  [isBalanceChangeT, isBalanceChangeF, isRegistryChangeT, isRegistryChangeRevoked,
   actorProj, resourceProj, decEq]

end TypesTests
end LegalKernel.Test.Events
