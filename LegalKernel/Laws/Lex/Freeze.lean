/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Laws.Lex.Freeze — Lex (LX.24) re-expression of the
`freezeResource` deployment-commitment marker.

M2-milestone Lex declaration for `freezeResource` (frozen action
index 3).  Produces a `def legalkernel_freezeResource_transition`
definitionally equal to the hand-written
`LegalKernel.Laws.freezeResource`; the byte-equivalence is
verified by the regression `example`.

`freezeResource` exercises the universal-`LocalTo []` shape (it
touches no balance cell) and the universal-`FreezePreserving [*]`
shape (no balance change preserves any frozen invariant).  M2's
`lex_satisfies` is empty because synthesizer-driven instance
emission is M3 work; the existing hand-written
`Laws.freezeResource_*` instances in `LegalKernel/Laws/Freeze.lean`
discharge the typeclass obligations.

See `LegalKernel/Laws/Lex/Transfer.lean`'s docstring for the
"Why a separate file?" explanation.
-/

import LegalKernel.Laws.Freeze
import LegalKernel.DSL.LexLaw

namespace LegalKernel.Laws.Lex

open LegalKernel

set_option linter.missingDocs false in
lexlaw legalkernel_freezeResource where
  lex_id              legalkernel.freezeResource
  lex_version         "1.0.0"
  lex_action_index    3
  lex_intent          "Mark resource `_r` as frozen.  No-op at the kernel level (Genesis Plan §4.10); deployment commitment to never mutate `_r` after this transition.  Underscore prefix communicates the param's deliberate irrelevance to the kernel-level Transition."
  lex_signed_by       deployer
  lex_authorized_by   (fun _ _ => True)
  lex_params          (_r : LegalKernel.ResourceId)
  lex_pre             := fun (_ : LegalKernel.State) => True
  lex_impl            := fun (s : LegalKernel.State) => s
  lex_satisfies       := []
  lex_events          := []

/-- LX.24 byte-equivalence regression: the M2 Lex re-expression of
    `freezeResource` is definitionally equal to the hand-written
    `Laws.freezeResource`.  Closes by `rfl`. -/
example (r : ResourceId) :
    legalkernel_freezeResource_transition r =
    LegalKernel.Laws.freezeResource r := rfl

end LegalKernel.Laws.Lex
