/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Laws.Lex.Reward — Lex (LX.24) re-expression of the
positive-incentive `reward` law.

M2-milestone Lex declaration for `reward` (frozen action index 5).
Produces a `def legalkernel_reward_transition` definitionally
equal to the hand-written `LegalKernel.Laws.reward`.

`reward` is definitionally identical to `mint` at the kernel
level (both produce the same `setBalance` increment); the
semantic distinction lives at the `Action` layer (so deployment
authorisation policies can grant "may reward" independently from
"may mint").  See plan §19.4 LX.24.

See `LegalKernel/Laws/Lex/Transfer.lean`'s docstring for the
"Why a separate file?" explanation.
-/

import LegalKernel.Laws.Reward
import LegalKernel.DSL.LexLaw

namespace LegalKernel.Laws.Lex

open LegalKernel

set_option linter.missingDocs false in
lexlaw legalkernel_reward where
  lex_id              legalkernel.reward
  lex_version         "1.0.0"
  lex_action_index    5
  lex_intent          "Reward `to` with `amount` units of resource `r`.  Definitionally identical to `mint` at the kernel level; the semantic distinction lives in the `Action.reward` constructor and downstream authorisation policies."
  lex_signed_by       to
  lex_authorized_by   (fun _ _ => True)
  lex_params          (r : LegalKernel.ResourceId)
                      (to : LegalKernel.ActorId)
                      (amount : LegalKernel.Amount)
  lex_pre             := fun _ => amount > 0
  lex_impl            :=
    fun s => LegalKernel.setBalance s r to (LegalKernel.getBalance s r to + amount)
  lex_satisfies       := []
  lex_events          := []

/-- LX.24 byte-equivalence regression: the M2 Lex re-expression of
    `reward` is definitionally equal to the hand-written
    `Laws.reward`.  Closes by `rfl`. -/
example (r : ResourceId) (to : ActorId) (amount : Amount) :
    legalkernel_reward_transition r to amount =
    LegalKernel.Laws.reward r to amount := rfl

end LegalKernel.Laws.Lex
