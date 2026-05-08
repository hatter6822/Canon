/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Laws.Lex.Deposit — Lex (LX.26) re-expression of the
bridge `deposit` law.

M2-milestone Lex declaration for `deposit` (frozen action index
13; Workstream-C).  Produces a `def
legalkernel_deposit_transition` definitionally equal to the
hand-written `LegalKernel.Laws.deposit`.

The kernel precondition is `True` (the bridge-level deposit-id
uniqueness check lives in `BridgeAdmissibleWith`); the kernel
effect is `mint`-style (credit `recipient`'s balance).  The
`depositId` parameter is unused at the kernel level (deliberately:
it carries through to `BridgeAdmissibleWith` for the uniqueness
check); the underscore prefix communicates this.

See `LegalKernel/Laws/Lex/Transfer.lean`'s docstring for the
"Why a separate file?" explanation.
-/

import LegalKernel.Laws.Deposit
import LegalKernel.Bridge.State
import LegalKernel.DSL.LexLaw

namespace LegalKernel.Laws.Lex

open LegalKernel
open LegalKernel.Bridge

set_option linter.missingDocs false in
lexlaw legalkernel_deposit where
  lex_id              legalkernel.deposit
  lex_version         "1.0.0"
  lex_action_index    13
  lex_intent          "Bridge L1 → L2 deposit (Workstream C / Genesis Plan §7.4): credit `amount` units of resource `r` to `recipient` on L2, marking `_depositId` as consumed (the bridge-level effect happens in `applyActionToBridgeState`).  Kernel-level effect is `mint`-shaped balance increment."
  lex_signed_by       bridge
  lex_authorized_by   (fun _ _ => True)
  lex_params          (r : LegalKernel.ResourceId)
                      (recipient : LegalKernel.ActorId)
                      (amount : LegalKernel.Amount)
                      (_depositId : LegalKernel.Bridge.DepositId)
  lex_pre             := fun (_ : LegalKernel.State) => True
  lex_impl            :=
    fun s =>
      LegalKernel.setBalance s r recipient
        (LegalKernel.getBalance s r recipient + amount)
  lex_satisfies       := []
  lex_events          := []

/-- LX.26 byte-equivalence regression: the M2 Lex re-expression of
    `deposit` is definitionally equal to the hand-written
    `Laws.deposit`.  Closes by `rfl`. -/
example (r : ResourceId) (recipient : ActorId) (amount : Amount)
    (depositId : Bridge.DepositId) :
    legalkernel_deposit_transition r recipient amount depositId =
    LegalKernel.Laws.deposit r recipient amount depositId := rfl

end LegalKernel.Laws.Lex
