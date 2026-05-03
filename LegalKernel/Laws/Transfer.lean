/-
LegalKernel.Laws.Transfer — the canonical balance-moving law.

This is the §4.11 worked example.  In Phase 0 the deliverable is the
*law itself* (the `Transition` value) plus the precondition's
decidability witness.  The conservation theorem
`transfer_conserves` and the cross-resource independence theorem
`transfer_does_not_touch_other_resources` of §4.11.1–4.11.2 are
deferred:

* §4.11.1 `transfer_conserves` is unblocked once §8.3
  `RBMap.foldl_insert_present` lands (Phase 1 WU 1.3) and is then
  discharged in WU 2.2 / WU 2.3.
* §4.11.2 `transfer_does_not_touch_other_resources` is unblocked once
  `getBalance_setBalance_other` lands (Phase 1 WU 1.5).

Stating those theorems with a `sorry` placeholder here would weaken
Phase 0's "no sorry in kernel-adjacent code" hygiene, so we omit them
and let Phase 1 introduce them in their natural home.

The self-transfer bug fix (§4.11) is preserved verbatim: the
receiver's pre-credit balance is read from `s1` (the post-debit
intermediate state), not from `s` (the original).
-/

import LegalKernel.Kernel

namespace LegalKernel
namespace Laws

/-- Transfer `amount` units of resource `r` from `sender` to
    `receiver`.

    * Precondition: the sender holds at least `amount`, and `amount`
      is strictly positive.  The positivity clause excludes vacuous
      transfers; it is policy, not correctness, and can be relaxed
      without breaking any kernel proof.
    * Effect: a debit at `sender` followed by a credit at `receiver`,
      reading the receiver's pre-credit balance from the post-debit
      intermediate state.  This sequencing is what makes
      self-transfers conserve total supply (see §4.11 for the proof
      sketch).

    `decPre` is inferred: the precondition is a conjunction of two
    decidable arithmetic comparisons over `Nat`. -/
def transfer (r : ResourceId)
    (sender receiver : ActorId) (amount : Amount) : Transition where
  pre        := fun s => getBalance s r sender ≥ amount ∧ amount > 0
  decPre     := fun _ => inferInstance
  apply_impl := fun s =>
    let fromBal := getBalance s r sender
    let s1      := setBalance s r sender (fromBal - amount)
    -- Crucial: read receiver's balance from s1, not s.
    -- When sender = receiver, this preserves the actor's total
    -- balance; reading from `s` would over-credit by `amount`.
    let toBal   := getBalance s1 r receiver
    setBalance s1 r receiver (toBal + amount)

/-- Sanity restatement of the precondition: `transfer.pre s` is exactly
    "sender holds at least `amount`, and `amount > 0`".  Also serves
    as a smoke test that the precondition is decidable (the typeclass
    resolution below would fail otherwise). -/
example (r : ResourceId) (sender receiver : ActorId) (amount : Amount)
    (s : State) :
    Decidable ((transfer r sender receiver amount).pre s) :=
  inferInstance

end Laws
end LegalKernel
