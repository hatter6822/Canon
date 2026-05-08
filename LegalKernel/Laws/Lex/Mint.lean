/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Laws.Lex.Mint — Lex (LX.23) re-expression of the
non-conservative `mint` law.

M2-milestone Lex declaration for `mint` (frozen action index 1).
Produces a `def legalkernel_mint_transition` definitionally equal
to the hand-written `LegalKernel.Laws.mint`; the byte-equivalence
is verified by the regression `example` at the end of this file.

The Lex declaration's `lex_satisfies` list is empty in M2 (the
synthesizer skeleton produces placeholder bodies; M3 will land
the canonical-shape emission).  `mint` would correctly fail the
`synth_conservative` path (mint is non-conservative by design)
and succeed `synth_monotonic`; the M2 milestone only covers the
byte-equivalence regression, not the synthesizer integration.

See `LegalKernel/Laws/Lex/Transfer.lean`'s docstring for the
"Why a separate file?" explanation.
-/

import LegalKernel.Laws.Mint
import LegalKernel.DSL.LexLaw

namespace LegalKernel.Laws.Lex

open LegalKernel

set_option linter.missingDocs false in
lexlaw legalkernel_mint where
  lex_id              legalkernel.mint
  lex_version         "1.0.0"
  lex_action_index    1
  lex_intent          "Mint `amount` units of resource `r` into actor `to`'s balance.  Non-conservative by design (Genesis Plan §5.6); classified as `IsMonotonic`."
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

/-- LX.23 byte-equivalence regression: the M2 Lex re-expression of
    `mint` is definitionally equal to the hand-written `Laws.mint`.
    Closes by `rfl`. -/
example (r : ResourceId) (to : ActorId) (amount : Amount) :
    legalkernel_mint_transition r to amount =
    LegalKernel.Laws.mint r to amount := rfl

end LegalKernel.Laws.Lex
