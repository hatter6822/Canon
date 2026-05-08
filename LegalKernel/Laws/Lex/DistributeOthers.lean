/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Laws.Lex.DistributeOthers — Lex (LX.29) re-expression
of the uniform-positive-incentive `distributeOthers` law.

M2-milestone Lex declaration for `distributeOthers` (frozen action
index 6; Phase-4 prelude).  Produces a `def
legalkernel_distributeOthers_transition` definitionally equal to
the hand-written `LegalKernel.Laws.distributeOthers`.

`distributeOthers` exercises the `for`-loop impl shape (`foldl
over `bm.toList`).  The plan §19.4 LX.29 acceptance note says:
> The `proof` override mechanism (LX.16) is exercised end-to-end:
> the synthesizer fails on `for`-shaped impl, the override fires,
> and the resulting instance is byte-equivalent to the pre-LX.29
> hand-written form.

In M2 the `lex_satisfies` is empty (the synthesizer skeleton
returns placeholder strings that the M3 codegen pass would
substitute with the canonical hand-written shapes).  The proof
overrides are documented in the existing
`distributeOthers_isMonotonic` / etc. instances in
`LegalKernel/Laws/DistributeOthers.lean`.

See `LegalKernel/Laws/Lex/Transfer.lean`'s docstring for the
"Why a separate file?" explanation.
-/

import LegalKernel.Laws.DistributeOthers
import LegalKernel.DSL.LexLaw

namespace LegalKernel.Laws.Lex

open LegalKernel
open Std
open scoped Std.TreeMap

set_option linter.missingDocs false in
lexlaw legalkernel_distributeOthers where
  lex_id              legalkernel.distributeOthers
  lex_version         "1.0.0"
  lex_action_index    6
  lex_intent          "Distribute `amount` to every actor in `r`'s `BalanceMap` except `excluded`.  Empty/excluded-only resources are no-ops.  Substitute for 'fining `excluded` by the equivalent of `amount * k`' without removing tokens from `excluded`.  Classified `IsMonotonic` (positive-incentive tier)."
  lex_signed_by       deployer
  lex_authorized_by   (fun _ _ => True)
  lex_params          (r : LegalKernel.ResourceId)
                      (excluded : LegalKernel.ActorId)
                      (amount : LegalKernel.Amount)
  lex_pre             := fun _ => amount > 0
  lex_impl            :=
    fun s =>
      let bm := s.balances[r]?.getD ∅
      let toReward := bm.toList.filter (fun kv => kv.1 != excluded)
      toReward.foldl
        (fun s' kv =>
          LegalKernel.setBalance s' r kv.1
            (LegalKernel.getBalance s' r kv.1 + amount))
        s
  lex_satisfies       := []
  lex_events          := []

/-- LX.29 byte-equivalence regression: the M2 Lex re-expression of
    `distributeOthers` is definitionally equal to the hand-written
    `Laws.distributeOthers`.  Closes by `rfl` because both forms
    produce the same `foldl`-over-filtered-balances body inside
    the same `Transition` record. -/
example (r : ResourceId) (excluded : ActorId) (amount : Amount) :
    legalkernel_distributeOthers_transition r excluded amount =
    LegalKernel.Laws.distributeOthers r excluded amount := rfl

end LegalKernel.Laws.Lex
