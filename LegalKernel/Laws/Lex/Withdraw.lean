/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Laws.Lex.Withdraw — Lex (LX.26) re-expression of the
bridge `withdraw` law.

M2-milestone Lex declaration for `withdraw` (frozen action index
14; Workstream-C).  Produces a `def
legalkernel_withdraw_transition` definitionally equal to the
hand-written `LegalKernel.Laws.withdraw`.

The kernel precondition is `getBalance s r sender ≥ amount`
(sufficient-balance for the debit); the kernel effect is
`burn`-style (debit `sender`'s balance).  The `recipientL1`
parameter is unused at the kernel level (it carries through to
`BridgeState.pending` for L1-redemption tracking via
`applyActionToBridgeState`); the underscore prefix communicates
this.

See `LegalKernel/Laws/Lex/Transfer.lean`'s docstring for the
"Why a separate file?" explanation.
-/

import LegalKernel.Laws.Withdraw
import LegalKernel.Bridge.AddressBook
import LegalKernel.DSL.LexLaw

namespace LegalKernel.Laws.Lex

open LegalKernel
open LegalKernel.Bridge

set_option linter.missingDocs false in
lexlaw legalkernel_withdraw where
  lex_id              legalkernel.withdraw
  lex_version         "1.0.0"
  lex_action_index    14
  lex_intent          "Bridge L2 → L1 withdrawal (Workstream C / Genesis Plan §7.4): debit `amount` units of resource `r` from `sender`'s balance and schedule an L1 redemption to `_recipientL1`.  Kernel-level effect is `burn`-shaped balance decrement (gated by sufficient-balance precondition).  The 20-byte `EthAddress` parameter is encoded losslessly per the Workstream-C audit-2 fix."
  lex_signed_by       sender
  lex_authorized_by   (fun _ _ => True)
  lex_params          (r : LegalKernel.ResourceId)
                      (sender : LegalKernel.ActorId)
                      (amount : LegalKernel.Amount)
                      (_recipientL1 : LegalKernel.Bridge.EthAddress)
  lex_pre             :=
    fun s => LegalKernel.getBalance s r sender ≥ amount
  lex_impl            :=
    fun s =>
      LegalKernel.setBalance s r sender
        (LegalKernel.getBalance s r sender - amount)
  lex_satisfies       := []
  lex_events          := []

/-- LX.26 byte-equivalence regression: the M2 Lex re-expression of
    `withdraw` is definitionally equal to the hand-written
    `Laws.withdraw`.  Closes by `rfl`. -/
example (r : ResourceId) (sender : ActorId) (amount : Amount)
    (recipientL1 : Bridge.EthAddress) :
    legalkernel_withdraw_transition r sender amount recipientL1 =
    LegalKernel.Laws.withdraw r sender amount recipientL1 := rfl

end LegalKernel.Laws.Lex
