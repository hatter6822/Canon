/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Laws.Lex.ProportionalDilute — Lex (LX.29) re-expression
of the proportional-positive-incentive `proportionalDilute` law.

M2-milestone Lex declaration for `proportionalDilute` (frozen
action index 7; Phase-4 prelude).  Produces a `def
legalkernel_proportionalDilute_transition` definitionally equal
to the hand-written `LegalKernel.Laws.proportionalDilute`.

Like `distributeOthers`, this law uses a `foldl`-over-filtered-
balances impl with a data-dependent per-step value (the share
each non-excluded actor receives is proportional to their
snapshotted balance, divided by the captured `sumOthers`).
The dust-bound theorem `proportionalDilute_distributed_le_totalReward`
in `LegalKernel/Laws/ProportionalDilute.lean` is what makes
proportional dilution a proper "no value destruction" law.

See `LegalKernel/Laws/Lex/Transfer.lean`'s docstring for the
"Why a separate file?" explanation.
-/

import LegalKernel.Laws.ProportionalDilute
import LegalKernel.DSL.LexLaw

namespace LegalKernel.Laws.Lex

open LegalKernel
open Std
open scoped Std.TreeMap

set_option linter.missingDocs false in
lexlaw legalkernel_proportionalDilute where
  lex_id              legalkernel.proportionalDilute
  lex_version         "1.0.0"
  lex_action_index    7
  lex_intent          "Proportionally dilute `excluded` by minting `totalReward * v_k / sumOthers` (Nat floor; dust discarded) to each non-excluded actor `k`.  The strongest analogue of 'burning excluded's balance share' available without removing tokens.  Classified `IsMonotonic`."
  lex_signed_by       deployer
  lex_authorized_by   (fun _ _ => True)
  lex_params          (r : LegalKernel.ResourceId)
                      (excluded : LegalKernel.ActorId)
                      (totalReward : LegalKernel.Amount)
  lex_pre             :=
    fun s => totalReward > 0 ∧ LegalKernel.sumOthers s r excluded > 0
  lex_impl            :=
    fun s =>
      let bm := s.balances[r]?.getD ∅
      let S  := LegalKernel.sumOthers s r excluded
      let toReward := bm.toList.filter (fun kv => kv.1 != excluded)
      toReward.foldl
        (fun s' kv =>
          LegalKernel.setBalance s' r kv.1
            (LegalKernel.getBalance s' r kv.1 + totalReward * kv.2 / S))
        s
  lex_satisfies       := []
  lex_events          := []

/-- LX.29 byte-equivalence regression: the M2 Lex re-expression of
    `proportionalDilute` is definitionally equal to the
    hand-written `Laws.proportionalDilute`.  Closes by `rfl`. -/
example (r : ResourceId) (excluded : ActorId) (totalReward : Amount) :
    legalkernel_proportionalDilute_transition r excluded totalReward =
    LegalKernel.Laws.proportionalDilute r excluded totalReward := rfl

end LegalKernel.Laws.Lex
