/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Laws.Lex.RegisterIdentity — Lex (LX.25) re-expression
of the `registerIdentity` action.

M2-milestone Lex declaration for `registerIdentity` (frozen action
index 12; Workstream-B).  First-time-registration analogue of
`replaceKey`: signed by the bridge actor (rather than the old
key, which doesn't exist for first-time registrations).  The
kernel-level body is the identity `Transition`; the authority-
level effect (KeyRegistry insertion) lives in
`applyActionToRegistry`.

The bridge-actor signing constraint is enforced by the deployment's
`bridgePolicy` (see `LegalKernel/Bridge/BridgeActor.lean`); the M2
Lex declaration captures the *kernel-level* shape, not the bridge
authorisation policy.

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
lexlaw legalkernel_registerIdentity where
  lex_id              legalkernel.registerIdentity
  lex_version         "1.0.0"
  lex_action_index    12
  lex_intent          "Insert a fresh `(actor, pk)` pair into the `KeyRegistry`, signed by the bridge actor.  Used for first-time identity registrations where `replaceKey` cannot apply (the old key doesn't exist yet).  Kernel-level effect is identity on `State`; the authority-level effect (registry insertion) happens in `apply_admissible` via `applyActionToRegistry`."
  lex_signed_by       bridge
  lex_authorized_by   (fun _ _ => True)
  lex_registry_effect registerIdentity
  -- Underscore prefix: kernel-level identity transition; registry
  -- mutation lives in `applyActionToRegistry`, not in the
  -- compiled `Transition`.
  lex_params          (_actor : LegalKernel.ActorId)
                      (_pk : LegalKernel.Authority.PublicKey)
  lex_pre             := fun (_ : LegalKernel.State) => True
  lex_impl            := fun (s : LegalKernel.State) => s
  lex_satisfies       := []
  lex_events          := []

/-- LX.25 byte-equivalence regression: the M2 Lex re-expression of
    `registerIdentity` produces a `Transition` definitionally
    equal to `Laws.freezeResource 0` — the kernel-level body that
    `Action.compileTransition (.registerIdentity ...)` returns. -/
example (actor : ActorId) (pk : PublicKey) :
    legalkernel_registerIdentity_transition actor pk =
    LegalKernel.Laws.freezeResource 0 := rfl

end LegalKernel.Laws.Lex
