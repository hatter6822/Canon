/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Laws.Lex.Burn — Lex (LX.23) re-expression of the
non-conservative `burn` law.

M2-milestone Lex declaration for `burn` (frozen action index 2).
Produces a `def legalkernel_burn_transition` definitionally equal
to the hand-written `LegalKernel.Laws.burn`; the byte-equivalence
is verified by the regression `example`.

`burn` exercises the negative-witness path: it would fail the
`synth_conservative` synthesizer (`burn` is non-conservative)
AND the `synth_monotonic` synthesizer (`burn_not_monotonic` is
the explicit negative witness in `LegalKernel.Laws.Burn`).  The
M2 declaration omits both `conservative` and `monotonic` from
`lex_satisfies` to reflect the negative classification; the
`local`, `freeze_preserving`, `nonce_advances`, and
`registry_preserving` properties continue to hold but are
omitted from `lex_satisfies` in M2 (synthesizer integration is
M3 work; see plan §19.4 LX.23 acceptance note).

See `LegalKernel/Laws/Lex/Transfer.lean`'s docstring for the
"Why a separate file?" explanation.
-/

import LegalKernel.Laws.Burn
import LegalKernel.DSL.LexLaw

namespace LegalKernel.Laws.Lex

open LegalKernel

set_option linter.missingDocs false in
lexlaw legalkernel_burn where
  lex_id              legalkernel.burn
  lex_version         "1.0.0"
  lex_action_index    2
  lex_intent          "Burn `amount` units of resource `r` from actor `fromActor`'s balance.  Non-conservative AND non-monotonic by design (Genesis Plan §5.6 + Phase-4 prelude `burn_not_monotonic`)."
  lex_signed_by       fromActor
  lex_authorized_by   (fun _ _ => True)
  lex_params          (r : LegalKernel.ResourceId)
                      (fromActor : LegalKernel.ActorId)
                      (amount : LegalKernel.Amount)
  lex_pre             :=
    fun s => LegalKernel.getBalance s r fromActor ≥ amount ∧ amount > 0
  lex_impl            :=
    fun s =>
      LegalKernel.setBalance s r fromActor
        (LegalKernel.getBalance s r fromActor - amount)
  lex_satisfies       := []
  lex_events          := []

/-- LX.23 byte-equivalence regression: the M2 Lex re-expression of
    `burn` is definitionally equal to the hand-written `Laws.burn`.
    Closes by `rfl`. -/
example (r : ResourceId) (fromActor : ActorId) (amount : Amount) :
    legalkernel_burn_transition r fromActor amount =
    LegalKernel.Laws.burn r fromActor amount := rfl

end LegalKernel.Laws.Lex
