/-
LegalKernel.Test.Laws.Transfer — unit tests for §4.11.

Phase-0 acceptance for WU 0.3 is "builds; transfer.pre is decidable".
The first is checked by Lake; the second is checked at compile time
by the `example : Decidable ...` line in `Laws/Transfer.lean`.  This
file adds run-time tests that pin down the *intended semantics*:

* the precondition is decided correctly on positive and negative
  cases;
* a legal transfer moves the right amount in the distinct-actor case;
* a self-transfer leaves the actor's balance unchanged (the §4.11
  bug-fix invariant);
* a transfer of more than the sender holds is a no-op;
* a transfer of zero (vacuous) is rejected by precondition;
* unrelated resources are untouched.

These tests deliberately avoid using `transfer_conserves` because that
theorem is deferred to Phase 2 (see `Laws/Transfer.lean` header for
the dependency chain).
-/

import LegalKernel.Laws.Transfer
import LegalKernel.Test.Framework

open LegalKernel
open LegalKernel.Laws
open LegalKernel.Test

namespace LegalKernel.Test.Laws.TransferTests

/-- Convenience: a fresh state with `(r=1, sender=10) ↦ initialBalance`. -/
def fund (initialBalance : Amount) : State :=
  setBalance emptyState 1 10 initialBalance

/-- Tests for the `transfer` law. -/
def tests : List TestCase :=
  [ { name := "precondition: enough balance ∧ amount > 0 ⇒ true"
    , body := do
        let s := fund 100
        let t := transfer 1 10 20 30
        assert (decide (t.pre s)) "should accept"
    }
  , { name := "precondition: insufficient balance ⇒ false"
    , body := do
        let s := fund 5
        let t := transfer 1 10 20 30
        assert (! decide (t.pre s)) "should reject (insufficient)"
    }
  , { name := "precondition: zero amount ⇒ false"
    , body := do
        let s := fund 100
        let t := transfer 1 10 20 0
        assert (! decide (t.pre s)) "should reject (zero amount)"
    }
  , { name := "legal transfer moves balance to receiver"
    , body := do
        let s  := fund 100
        let t  := transfer 1 10 20 30
        let s' := step_impl s t
        assertEq (expected := 70) (actual := getBalance s' 1 10) "sender after"
        assertEq (expected := 30) (actual := getBalance s' 1 20) "receiver after"
    }
  , { name := "self-transfer preserves the actor's balance (the §4.11 fix)"
    , body := do
        -- Read receiver's balance from the post-debit state, not pre.
        -- Without the fix, a self-transfer of 30 from balance 100 would
        -- leave 130 (over-credit) or 70 (under-credit) instead of 100.
        let s  := fund 100
        let t  := transfer 1 10 10 30
        let s' := step_impl s t
        assertEq (expected := 100) (actual := getBalance s' 1 10)
          "self-transfer should be balance-preserving"
    }
  , { name := "self-transfer of 1 from balance 1 stays at 1"
    , body := do
        -- Boundary: amount equals balance, sender = receiver.  Without
        -- the §4.11 sequencing, this would compute 1-1+1 = 1 only if
        -- both reads come from the *original* state (over-credit when
        -- different actors, under-credit when same).  The fix makes the
        -- second read see the post-debit value (0), giving 0+1 = 1.
        let s  := fund 1
        let t  := transfer 1 10 10 1
        let s' := step_impl s t
        assertEq (expected := 1) (actual := getBalance s' 1 10)
          "self-transfer with full balance"
    }
  , { name := "rejected transfer is a no-op"
    , body := do
        let s  := fund 5
        let t  := transfer 1 10 20 30
        let s' := step_impl s t
        assertEq (expected := 5) (actual := getBalance s' 1 10) "sender unchanged"
        assertEq (expected := 0) (actual := getBalance s' 1 20) "no credit"
    }
  , { name := "transfer leaves unrelated resources untouched"
    , body := do
        let s0 := setBalance (fund 100) 2 99 7
        let t  := transfer 1 10 20 30
        let s' := step_impl s0 t
        assertEq (expected := 7) (actual := getBalance s' 2 99) "other resource"
    }
  , { name := "transfer leaves unrelated actors untouched"
    , body := do
        let s0 := setBalance (fund 100) 1 99 42
        let t  := transfer 1 10 20 30
        let s' := step_impl s0 t
        assertEq (expected := 42) (actual := getBalance s' 1 99) "other actor"
    }
  , { name := "decidable precondition typeclass resolves"
    , body := do
        -- This is mainly a smoke test that the `decPre` field still
        -- reaches the `Decidable` instance.  At runtime, `decide`
        -- exercises that path.
        let s := fund 100
        let t := transfer 1 10 20 30
        let _ : Decidable (t.pre s) := inferInstance
        pure ()
    }
  , { name := "two sequential legal transfers compose correctly"
    , body := do
        -- Drives the kernel through two `step_impl` applications, then
        -- checks balance invariants pointwise.  Phase 2 will lift this
        -- to a TotalSupply-conservation property.
        let s0 := fund 100
        let t1 := transfer 1 10 20 30
        let t2 := transfer 1 20 30 10
        let s1 := step_impl s0 t1
        let s2 := step_impl s1 t2
        assertEq (expected := 70) (actual := getBalance s2 1 10) "sender"
        assertEq (expected := 20) (actual := getBalance s2 1 20) "middle"
        assertEq (expected := 10) (actual := getBalance s2 1 30) "final"
    }
  ]

end LegalKernel.Test.Laws.TransferTests
