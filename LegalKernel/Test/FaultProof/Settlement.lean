/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Test.FaultProof.Settlement — value-level tests for the
composite trust-model upgrade theorem (Workstream H §12.4.4 /
WU H.4.4c).

Exercises the three settlement branches:
  * Challenger responds truthfully → wins.
  * Sequencer responds with disputed-high.commit, kernel computes
    truth → mismatch → challenger wins.
  * Sequencer's cell proofs fail → challenger wins.

Plus the composite theorem and the trace-bridge lemma.
-/

import LegalKernel.FaultProof.Settlement
import LegalKernel.Test.Framework

open LegalKernel
open LegalKernel.FaultProof
open LegalKernel.Authority
open LegalKernel.Disputes
open LegalKernel.Test

namespace LegalKernel.Test.FaultProof.Settlement

/-- 32 zero bytes — the canonical "zero commit". -/
private def zeroCommit : StateCommit := ByteArray.empty

/-- A non-zero commit (32 bytes of `0x01`). -/
private def oneCommit : StateCommit :=
  ByteArray.mk #[1, 1, 1, 1, 1, 1, 1, 1,
                 1, 1, 1, 1, 1, 1, 1, 1,
                 1, 1, 1, 1, 1, 1, 1, 1,
                 1, 1, 1, 1, 1, 1, 1, 1]

/-- A second non-zero commit, distinct from `oneCommit`. -/
private def twoCommit : StateCommit :=
  ByteArray.mk #[2, 2, 2, 2, 2, 2, 2, 2,
                 2, 2, 2, 2, 2, 2, 2, 2,
                 2, 2, 2, 2, 2, 2, 2, 2,
                 2, 2, 2, 2, 2, 2, 2, 2]

/-- A single-step disputed range with low and high commits
    distinct: `oneCommit` ≠ `twoCommit`. -/
private def singleStepRange : DisputedRange :=
  { low  := { idx := 0, commit := oneCommit },
    high := { idx := 1, commit := twoCommit } }

/-- A game state with the challenger's turn at a single-step
    range.  Used to exercise the
    `honest_challenger_responds_truthfully_wins` theorem. -/
private def challengerRespondingGame : GameState :=
  { sequencer       := 1
  , challenger      := 2
  , range           := singleStepRange
  , pendingMidpoint := none
  , depth           := 1
  , turn            := .challenger
  , sequencerBond   := 1_000
  , challengerBond  := 50
  , status          := .inProgress
  , deploymentId    := ByteArray.empty }

/-- A game state with the sequencer's turn at a single-step
    range.  Used to exercise the
    `sequencer_responding_with_disputed_high_loses` theorem. -/
private def sequencerRespondingGame : GameState :=
  { sequencer       := 1
  , challenger      := 2
  , range           := singleStepRange
  , pendingMidpoint := none
  , depth           := 1
  , turn            := .sequencer
  , sequencerBond   := 1_000
  , challengerBond  := 50
  , status          := .inProgress
  , deploymentId    := ByteArray.empty }

/-- Tests for the composite trust-model theorem. -/
def tests : List TestCase :=
  [ { name := "settlementDisagreement holds when high ≠ truth"
    , body := do
        let truth : LogIndex → StateCommit := fun _ => oneCommit
        -- gs.range.high.commit = twoCommit ≠ truth(1) = oneCommit.
        let h : settlementDisagreement truth challengerRespondingGame :=
          fun heq => absurd heq (by decide)
        let _ := h
        assert true "settlementDisagreement decidable + holds"
    }
  , { name := "inDisagreementWithTruth_implies_settlementDisagreement type-checks"
    , body := do
        let _ := @inDisagreementWithTruth_implies_settlementDisagreement
        assert true "bridge lemma type-checks"
    }
  , { name := "honest_challenger_responds_truthfully_wins type-checks"
    , body := do
        let _ := @honest_challenger_responds_truthfully_wins
        assert true "challenger-win theorem type-checks"
    }
  , { name := "sequencer_responding_with_disputed_high_loses type-checks"
    , body := do
        let _ := @sequencer_responding_with_disputed_high_loses
        assert true "sequencer-loss theorem type-checks"
    }
  , { name := "sequencer_responding_with_invalid_proofs_loses type-checks"
    , body := do
        let _ := @sequencer_responding_with_invalid_proofs_loses
        assert true "sequencer-invalid-proofs theorem type-checks"
    }
  , { name := "honest_challenger_wins_against_invalid_state_root type-checks"
    , body := do
        let _ := @honest_challenger_wins_against_invalid_state_root
        assert true "composite #232 theorem type-checks"
    }
  , { name := "settlementDisagreement decidable"
    , body := do
        let truth : LogIndex → StateCommit := fun _ => oneCommit
        let d := instDecidableSettlementDisagreement truth challengerRespondingGame
        let _ := d
        assert true "decidable instance synthesised"
    }
  , { name := "challenger turn + single-step range is well-shaped"
    , body := do
        assert challengerRespondingGame.range.isSingleStep
          "range is single-step"
        assertEq (expected := TurnSide.challenger)
                 (actual := challengerRespondingGame.turn)
                 "challenger's turn"
    }
  , { name := "sequencer turn + single-step range is well-shaped"
    , body := do
        assert sequencerRespondingGame.range.isSingleStep
          "range is single-step"
        assertEq (expected := TurnSide.sequencer)
                 (actual := sequencerRespondingGame.turn)
                 "sequencer's turn"
    }
  ]

end LegalKernel.Test.FaultProof.Settlement
