/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Laws.Lex.Transfer — Lex (LX.22) re-expression of the
canonical `transfer` law.

This is the M2-milestone Lex declaration for `transfer` (frozen
action index 0).  It produces a `def
legalkernel_transfer_transition` whose `Transition` value is
**definitionally equal** to the hand-written
`LegalKernel.Laws.transfer`; the byte-equivalence is verified by
the regression `example` at the end of this file (which closes by
`rfl` because `Law.mk pre impl` unfolds to `{ pre, decPre := fun _
=> inferInstance, apply_impl := impl }` — the same field shape
the hand-written form uses).

The Lex declaration is the *source of truth* for M2-onward Lex-
based deployments; the hand-written `Laws.transfer` is preserved
unchanged so the kernel-level `transfer_conserves`,
`transfer_isConservative`, etc. theorems continue to elaborate
without modification (and so the cyclical import that arose from
threading the Lex DSL through `Laws/Transfer.lean` is avoided —
see the `## Why a separate file?` block below).

# The Lex re-expression separately to avoid an import cycle

The Lex DSL macro lives in `LegalKernel.DSL.LexLaw`, which depends
on `LegalKernel.DSL.Law` (the Phase-4 `Law.mk` form).  `DSL.Law`
registers the Lean tokens `pre` and `impl` for its
`law pre := … ; impl := …` macro.  If `Laws/Transfer.lean` were
to import `DSL.LexLaw`, those tokens would become globally active
during the parse of `Laws/Transfer.lean`, breaking the
hand-written `def transfer ... where pre := ...` block (`pre`
would be tokenised as a keyword rather than a structure-field
name).

The clean fix: keep the Lex re-expression in a *separate file*
that imports both `Laws.Transfer` (for `LegalKernel.Laws.transfer`)
and `DSL.LexLaw` (for the `lexlaw` macro).  The separate file's
parse context has both the law and the DSL in scope; the
hand-written law's parse context does not.

This is the M2 deviation from the implementation plan §19.4 / §1.2,
which specified that `Laws/Transfer.lean` itself would carry the
Lex form.  Documented here and in CLAUDE.md.
-/

import LegalKernel.Laws.Transfer
import LegalKernel.DSL.LexLaw

namespace LegalKernel.Laws.Lex

open LegalKernel

set_option linter.missingDocs false in
lexlaw legalkernel_transfer where
  lex_id              legalkernel.transfer
  lex_version         "1.0.0"
  lex_action_index    0
  lex_intent          "Move `amount` units of resource `r` from `sender` to `receiver`.  The post-debit re-read of the receiver's balance is what makes self-transfers conserve total supply (Genesis Plan §4.11)."
  lex_signed_by       sender
  lex_authorized_by   (fun _ _ => True)
  lex_params          (r : LegalKernel.ResourceId)
                      (sender receiver : LegalKernel.ActorId)
                      (amount : LegalKernel.Amount)
  lex_pre             :=
    fun s => LegalKernel.getBalance s r sender ≥ amount ∧ amount > 0
  lex_impl            :=
    fun s =>
      let fromBal := LegalKernel.getBalance s r sender
      let s1      := LegalKernel.setBalance s r sender (fromBal - amount)
      let toBal   := LegalKernel.getBalance s1 r receiver
      LegalKernel.setBalance s1 r receiver (toBal + amount)
  lex_satisfies       := []
  lex_events          := []

/-- LX.22 byte-equivalence regression: the M2 Lex re-expression of
    `transfer` is definitionally equal to the hand-written
    `Laws.transfer`.  Closes by `rfl` because both forms produce
    the same `Transition` record (`Law.mk pre impl` unfolds to
    `{ pre, decPre := fun _ => inferInstance, apply_impl := impl }`,
    matching the hand-written form exactly).  This is the
    "byte-equivalence regression test" the plan §19.4 calls for. -/
example (r : ResourceId) (sender receiver : ActorId) (amount : Amount) :
    legalkernel_transfer_transition r sender receiver amount =
    LegalKernel.Laws.transfer r sender receiver amount := rfl

end LegalKernel.Laws.Lex
