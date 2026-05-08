/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Test.Laws.LexM2 — M2 milestone byte-equivalence
regression suite.

LX.30 acceptance: every kernel-built-in law's M2 Lex re-expression
produces a `Transition` definitionally equal to the hand-written
form.  After the LX-M2 in-place migration, the per-law `example`
proofs live INSIDE each `Laws/<Law>.lean` file (alongside the
hand-written form), enforced at *elaboration time* (an `rfl`
failure breaks the build); this suite re-asserts the invariants
at *test time* with explicit value-level checks against fixture
inputs.

Each test case picks a representative concrete fixture for the
law's parameters and asserts:

  1. The Lex-derived `legalkernel_<law>_transition (params)`
     equals the hand-written form (already `rfl`; tested here
     for documentation + suite-level visibility).
  2. The transition's `pre` and `apply_impl` projections
     match between the two forms (explicit equality at the
     field level).

Re-running the M2 milestone gate is a one-liner:

```bash
lake test 2>&1 | grep "^== laws-lex-m2"
```

Any divergence here is a build-blocking signal that the M2
strict-equivalence invariant has been broken.
-/

import LegalKernel
import LegalKernel.Test.Framework

open LegalKernel
open LegalKernel.Test
open LegalKernel.Laws
open LegalKernel.Authority
open LegalKernel.Bridge
open LegalKernel.Disputes

namespace LegalKernel.Test.Laws.LexM2

/-- Fixture state for the value-level field-projection checks. -/
private def fixState : LegalKernel.State := emptyState

/-! ## LX.22 — `transfer` (action index 0) -/

/-- The Lex re-expression of `transfer` is byte-equivalent to the
    hand-written form on a representative fixture.  This is the
    suite-level mirror of the `rfl` `example` in
    `LegalKernel/Laws/Lex/Transfer.lean`. -/
private def transferTests : List TestCase :=
  [ { name := "LX.22: legalkernel_transfer ≡ Laws.transfer (rfl)"
    , body := do
        let _ : legalkernel_transfer_transition 1 10 20 5 =
                Laws.transfer 1 10 20 5 := rfl
        pure ()
    }
  , { name := "LX.22: transfer pre projects identically"
    , body := do
        let lex := legalkernel_transfer_transition 1 10 20 5
        let hand := Laws.transfer 1 10 20 5
        let _ : lex.pre = hand.pre := rfl
        pure ()
    }
  , { name := "LX.22: transfer apply_impl projects identically"
    , body := do
        let lex := legalkernel_transfer_transition 1 10 20 5
        let hand := Laws.transfer 1 10 20 5
        let _ : lex.apply_impl = hand.apply_impl := rfl
        pure ()
    }
  ]

/-! ## LX.23 — `mint` and `burn` (indices 1, 2) -/

private def mintBurnTests : List TestCase :=
  [ { name := "LX.23: legalkernel_mint ≡ Laws.mint (rfl)"
    , body := do
        let _ : legalkernel_mint_transition 1 10 5 = Laws.mint 1 10 5 := rfl
        pure ()
    }
  , { name := "LX.23: legalkernel_burn ≡ Laws.burn (rfl)"
    , body := do
        let _ : legalkernel_burn_transition 1 10 5 = Laws.burn 1 10 5 := rfl
        pure ()
    }
  , { name := "LX.23: mint pre projects identically"
    , body := do
        let _ : (legalkernel_mint_transition 1 10 5).pre =
                (Laws.mint 1 10 5).pre := rfl
        pure ()
    }
  , { name := "LX.23: burn pre projects identically"
    , body := do
        let _ : (legalkernel_burn_transition 1 10 5).pre =
                (Laws.burn 1 10 5).pre := rfl
        pure ()
    }
  ]

/-! ## LX.24 — `freezeResource` and `reward` (indices 3, 5) -/

private def freezeRewardTests : List TestCase :=
  [ { name := "LX.24: legalkernel_freezeResource ≡ Laws.freezeResource (rfl)"
    , body := do
        let _ : legalkernel_freezeResource_transition 7 =
                Laws.freezeResource 7 := rfl
        pure ()
    }
  , { name := "LX.24: legalkernel_reward ≡ Laws.reward (rfl)"
    , body := do
        let _ : legalkernel_reward_transition 1 10 5 = Laws.reward 1 10 5 := rfl
        pure ()
    }
  , { name := "LX.24: freezeResource is the identity transition"
    , body := do
        let lex := legalkernel_freezeResource_transition 7
        -- step_impl on the identity transition is the identity at
        -- the balances level.
        let s' := step_impl fixState lex
        let _ : s'.balances = fixState.balances := by rfl
        pure ()
    }
  ]

/-! ## LX.25 — `replaceKey` and `registerIdentity` (indices 4, 12) -/

private def authorityKeyTests : List TestCase :=
  [ { name := "LX.25: legalkernel_replaceKey ≡ freezeResource 0 (rfl)"
    , body := do
        let pk : LegalKernel.Authority.PublicKey := ByteArray.empty
        let _ : legalkernel_replaceKey_transition 7 pk =
                Laws.freezeResource 0 := rfl
        pure ()
    }
  , { name := "LX.25: legalkernel_registerIdentity ≡ freezeResource 0 (rfl)"
    , body := do
        let pk : LegalKernel.Authority.PublicKey := ByteArray.empty
        let _ : legalkernel_registerIdentity_transition 7 pk =
                Laws.freezeResource 0 := rfl
        pure ()
    }
  ]

/-! ## LX.26 — `deposit` and `withdraw` (indices 13, 14) -/

private def bridgeTests : List TestCase :=
  [ { name := "LX.26: legalkernel_deposit ≡ Laws.deposit (rfl)"
    , body := do
        let _ : legalkernel_deposit_transition 1 10 5 0 =
                Laws.deposit 1 10 5 0 := rfl
        pure ()
    }
  , { name := "LX.26: legalkernel_withdraw ≡ Laws.withdraw (rfl)"
    , body := do
        let rcp : LegalKernel.Bridge.EthAddress := ⟨0, by decide⟩
        let _ : legalkernel_withdraw_transition 1 10 5 rcp =
                Laws.withdraw 1 10 5 rcp := rfl
        pure ()
    }
  ]

/-! ## LX.27 — dispute pipeline (indices 8 – 11) -/

private def disputeTests : List TestCase :=
  [ { name := "LX.27: legalkernel_dispute ≡ freezeResource 0 (rfl)"
    , body := do
        -- Synthesise a minimal Dispute fixture to exercise the
        -- transition.  The dispute's content is irrelevant — the
        -- kernel-level transition is identity regardless.
        let d : Disputes.Dispute := {
          challenger := 1,
          claim := .preconditionFalse 0,
          evidence := ByteArray.empty,
          nonce := 0,
          sig := ByteArray.empty
        }
        let _ : legalkernel_dispute_transition d =
                Laws.freezeResource 0 := rfl
        pure ()
    }
  , { name := "LX.27: legalkernel_disputeWithdraw ≡ freezeResource 0 (rfl)"
    , body := do
        let _ : legalkernel_disputeWithdraw_transition (5 : Disputes.LogIndex) =
                Laws.freezeResource 0 := rfl
        pure ()
    }
  , { name := "LX.27: legalkernel_verdict ≡ freezeResource 0 (rfl)"
    , body := do
        let v : Disputes.Verdict := {
          disputeId := 0,
          outcome := .rejected,
          rationale := ByteArray.empty,
          signatures := []
        }
        let _ : legalkernel_verdict_transition v =
                Laws.freezeResource 0 := rfl
        pure ()
    }
  , { name := "LX.27: legalkernel_rollback ≡ freezeResource 0 (rfl)"
    , body := do
        let _ : legalkernel_rollback_transition (3 : Disputes.LogIndex) =
                Laws.freezeResource 0 := rfl
        pure ()
    }
  ]

/-! ## LX.28 — local-policy actions (indices 15, 16) -/

private def localPolicyTests : List TestCase :=
  [ { name := "LX.28: legalkernel_declareLocalPolicy ≡ freezeResource 0 (rfl)"
    , body := do
        let p : LegalKernel.Authority.LocalPolicy := { clauses := [] }
        let _ : legalkernel_declareLocalPolicy_transition p =
                Laws.freezeResource 0 := rfl
        pure ()
    }
  , { name := "LX.28: legalkernel_revokeLocalPolicy ≡ freezeResource 0 (rfl)"
    , body := do
        let _ : legalkernel_revokeLocalPolicy_transition =
                Laws.freezeResource 0 := rfl
        pure ()
    }
  ]

/-! ## LX.29 — aggregate laws (indices 6, 7) -/

private def aggregateTests : List TestCase :=
  [ { name := "LX.29: legalkernel_distributeOthers ≡ Laws.distributeOthers (rfl)"
    , body := do
        let _ : legalkernel_distributeOthers_transition 1 10 5 =
                Laws.distributeOthers 1 10 5 := rfl
        pure ()
    }
  , { name := "LX.29: legalkernel_proportionalDilute ≡ Laws.proportionalDilute (rfl)"
    , body := do
        let _ : legalkernel_proportionalDilute_transition 1 10 100 =
                Laws.proportionalDilute 1 10 100 := rfl
        pure ()
    }
  ]

/-! ## LX.30 — M2 milestone gate -/

private def milestoneGateTests : List TestCase :=
  [ { name := "LX.30: kernelBuildTag is `canon-lex-m2-canonical`"
    , body := do
        assertEq (expected := "canon-lex-m2-canonical")
                 (actual   := LegalKernel.kernelBuildTag)
                 "M2 milestone gate"
    }
  , { name := "LX.30: 17 kernel-built-in laws have Lex re-expressions"
    , body := do
        -- Term-level API stability: every `legalkernel_<law>_transition`
        -- exists and has the expected type.  An identifier rename or
        -- removal would fail elaboration here.
        let _ : LegalKernel.ResourceId → LegalKernel.ActorId →
                LegalKernel.ActorId → LegalKernel.Amount →
                LegalKernel.Transition := legalkernel_transfer_transition
        let _ : LegalKernel.ResourceId → LegalKernel.ActorId →
                LegalKernel.Amount → LegalKernel.Transition :=
          legalkernel_mint_transition
        let _ : LegalKernel.ResourceId → LegalKernel.ActorId →
                LegalKernel.Amount → LegalKernel.Transition :=
          legalkernel_burn_transition
        let _ : LegalKernel.ResourceId → LegalKernel.Transition :=
          legalkernel_freezeResource_transition
        let _ : LegalKernel.ResourceId → LegalKernel.ActorId →
                LegalKernel.Amount → LegalKernel.Transition :=
          legalkernel_reward_transition
        let _ : LegalKernel.ActorId → LegalKernel.Authority.PublicKey →
                LegalKernel.Transition := legalkernel_replaceKey_transition
        let _ : LegalKernel.ActorId → LegalKernel.Authority.PublicKey →
                LegalKernel.Transition := legalkernel_registerIdentity_transition
        let _ : LegalKernel.ResourceId → LegalKernel.ActorId →
                LegalKernel.Amount → LegalKernel.Bridge.DepositId →
                LegalKernel.Transition := legalkernel_deposit_transition
        let _ : LegalKernel.ResourceId → LegalKernel.ActorId →
                LegalKernel.Amount → LegalKernel.Bridge.EthAddress →
                LegalKernel.Transition := legalkernel_withdraw_transition
        let _ : LegalKernel.Disputes.Dispute → LegalKernel.Transition :=
          legalkernel_dispute_transition
        let _ : LegalKernel.Disputes.LogIndex → LegalKernel.Transition :=
          legalkernel_disputeWithdraw_transition
        let _ : LegalKernel.Disputes.Verdict → LegalKernel.Transition :=
          legalkernel_verdict_transition
        let _ : LegalKernel.Disputes.LogIndex → LegalKernel.Transition :=
          legalkernel_rollback_transition
        let _ : LegalKernel.Authority.LocalPolicy → LegalKernel.Transition :=
          legalkernel_declareLocalPolicy_transition
        let _ : LegalKernel.Transition := legalkernel_revokeLocalPolicy_transition
        let _ : LegalKernel.ResourceId → LegalKernel.ActorId →
                LegalKernel.Amount → LegalKernel.Transition :=
          legalkernel_distributeOthers_transition
        let _ : LegalKernel.ResourceId → LegalKernel.ActorId →
                LegalKernel.Amount → LegalKernel.Transition :=
          legalkernel_proportionalDilute_transition
        pure ()
    }
  ]

/-- The full M2 byte-equivalence regression suite. -/
def tests : List TestCase :=
  transferTests ++ mintBurnTests ++ freezeRewardTests ++
  authorityKeyTests ++ bridgeTests ++ disputeTests ++
  localPolicyTests ++ aggregateTests ++ milestoneGateTests

end LegalKernel.Test.Laws.LexM2
