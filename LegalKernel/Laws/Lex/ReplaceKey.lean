/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Laws.Lex.ReplaceKey — Lex (LX.25) re-expression of the
authority-layer key-rotation `replaceKey` action.

M2-milestone Lex declaration for `replaceKey` (frozen action
index 4).  Produces a `def legalkernel_replaceKey_transition`
whose kernel-level body is the identity `Transition`
(`Laws.freezeResource 0` per the Phase-3 design where authority-
level effects live in `applyActionToRegistry`, not in the
compiled `Transition`).

The byte-equivalence regression test compares against
`LegalKernel.Laws.freezeResource 0` — the value that
`Action.compileTransition (.replaceKey ...)` returns.

The plan §19.4 LX.25 acceptance note says:
> Both laws use the `register_key` impl primitive (which routes
> to the authority-layer `applyActionToRegistry`, not to
> `apply_impl`).
> `RegistryPreserving` is **not** claimed in `satisfies` for
> either law (correctly so; both mutate the registry).

The M2 declaration accordingly does NOT claim `registry_preserving`
in `lex_satisfies` (which is empty in M2 anyway, pending M3
synthesizer integration).

See `LegalKernel/Laws/Lex/Transfer.lean`'s docstring for the
"Why a separate file?" explanation.
-/

import LegalKernel.Laws.Freeze
import LegalKernel.Authority.Crypto
import LegalKernel.DSL.LexLaw

namespace LegalKernel.Laws.Lex

open LegalKernel
open LegalKernel.Authority

set_option linter.missingDocs false in
lexlaw legalkernel_replaceKey where
  lex_id              legalkernel.replaceKey
  lex_version         "1.0.0"
  lex_action_index    4
  lex_intent          "Re-point `actor`'s identity to `newKey` in the `KeyRegistry`, signed by the *old* key.  Kernel-level effect is identity on `State`; the authority-level effect (registry update) happens in `apply_admissible` via `applyActionToRegistry` (Phase 3 / WU 3.10)."
  lex_signed_by       actor
  lex_authorized_by   (fun _ _ => True)
  -- Underscore prefix on `_actor` and `_newKey`: the kernel-level
  -- `Transition` is the identity (per the Phase-3 design where
  -- registry mutation lives in `applyActionToRegistry`, not in
  -- the compiled `Transition`).  The params are part of the
  -- action-layer API but deliberately unused at the kernel level.
  lex_params          (_actor : LegalKernel.ActorId)
                      (_newKey : LegalKernel.Authority.PublicKey)
  lex_pre             := fun (_ : LegalKernel.State) => True
  lex_impl            := fun (s : LegalKernel.State) => s
  lex_satisfies       := []
  lex_events          := []

/-- LX.25 byte-equivalence regression: the M2 Lex re-expression of
    `replaceKey` produces a `Transition` definitionally equal to
    `Laws.freezeResource 0` — the kernel-level body that
    `Action.compileTransition (.replaceKey ...)` returns. -/
example (actor : ActorId) (newKey : PublicKey) :
    legalkernel_replaceKey_transition actor newKey =
    LegalKernel.Laws.freezeResource 0 := rfl

end LegalKernel.Laws.Lex
