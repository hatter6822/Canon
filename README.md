# Legal Kernel

This document defines a **formally grounded, implementation-oriented constitutional kernel** built in Lean 4. It integrates both the architectural vision and the concrete formal system developed so far.

---

# 1. Core Thesis

The Legal Kernel is:

> A **proof-carrying state transition system** where legality is enforced as a type, and global system properties are guaranteed via inductive invariants.

This system separates:
- **Specification vs execution**
- **Law vs mechanism**
- **Semantics vs verification**

---

# 2. Formal Kernel (Lean 4)

Below is the current minimal kernel, refined for correctness and extensibility.

```lean
import Std.Data.RBMap

open Std

namespace LegalKernel

abbrev ActorId := UInt64
abbrev ResourceId := UInt64

abbrev BalanceMap := RBMap ActorId Nat compare

structure State where
  balances : RBMap ResourceId BalanceMap compare
  deriving Repr

--------------------------------------------------
-- Balance Operations
--------------------------------------------------

def getBalance (s : State) (r : ResourceId) (a : ActorId) : Nat :=
  match s.balances.find? r with
  | none => 0
  | some bm => match bm.find? a with
    | none => 0
    | some v => v


def setBalance (s : State) (r : ResourceId) (a : ActorId) (v : Nat) : State :=
  let bm := match s.balances.find? r with
    | none => RBMap.empty
    | some m => m
  let bm' := bm.insert a v
  { balances := s.balances.insert r bm' }

--------------------------------------------------
-- Transition System (Parametric)
--------------------------------------------------

structure Transition where
  apply_impl : State → State
  pre        : State → Prop

--------------------------------------------------
-- Spec / Impl Separation
--------------------------------------------------

/-- Relational specification -/
def step_spec (s s' : State) (t : Transition) : Prop :=
  t.pre s ∧ s' = t.apply_impl s

/-- Executable implementation -/
def step_impl (s : State) (t : Transition) : State :=
  if h : t.pre s then t.apply_impl s else s

/-- Refinement: implementation satisfies spec when pre holds -/
theorem impl_refines_spec
  (s : State) (t : Transition)
  (h : t.pre s) :
  step_spec s (step_impl s t) t := by
  unfold step_impl step_spec
  simp [h]

/-- Safety fallback: no-op when precondition fails -/
theorem impl_noop_if_not_pre
  (s : State) (t : Transition)
  (h : ¬ t.pre s) :
  step_impl s t = s := by
  unfold step_impl
  simp [h]

--------------------------------------------------
-- Proof-Relevant Legality
--------------------------------------------------

structure Legal (s : State) (t : Transition) where
  proof : t.pre s

structure CertifiedTransition (s : State) where
  t    : Transition
  cert : Legal s t

--------------------------------------------------
-- Trusted Execution Path
--------------------------------------------------

/-- Certified execution (no runtime check needed) -/
def apply_certified (s : State) (ct : CertifiedTransition s) : State :=
  ct.t.apply_impl s

--------------------------------------------------
-- Example Transition: Transfer
--------------------------------------------------

def transfer (r : ResourceId) (from to : ActorId) (amount : Nat) : Transition :=
{
  apply_impl := fun s =>
    let fromBal := getBalance s r from
    let toBal   := getBalance s r to
    let s1 := setBalance s r from (fromBal - amount)
    let s2 := setBalance s1 r to (toBal + amount)
    s2,
  pre := fun s =>
    let fromBal := getBalance s r from
    fromBal ≥ amount ∧ amount > 0
}

--------------------------------------------------
-- Invariants
--------------------------------------------------

/-- Non-negativity invariant -/
def NonNeg (s : State) : Prop :=
  ∀ r a, getBalance s r a ≥ 0

--------------------------------------------------
-- Reachability
--------------------------------------------------

inductive Reachable (s0 : State) : State → Prop
| base : Reachable s0 s0
| step (s t)
    (hreach : Reachable s0 s)
    (hpre   : t.pre s) :
    Reachable s0 (step_impl s t)

--------------------------------------------------
-- Global Invariant Theorem
--------------------------------------------------

theorem invariant_preservation
  (I : State → Prop)
  (s0 : State)
  (h_init : I s0)
  (h_step : ∀ s t, I s → t.pre s → I (step_impl s t)) :
  ∀ s, Reachable s0 s → I s := by
  intro s h
  induction h with
  | base => exact h_init
  | step s t hreach hpre ih =>
      exact h_step s t ih hpre

end LegalKernel
```

---

# 3. Mathematical Guarantees

## 3.1 Local Safety

∀ s t, I s → t.pre s → I (step_impl s t)

## 3.2 Global Safety

∀ reachable states s, I s

This is the **constitutional guarantee**.

---

# 4. Architectural Layers

## 4.1 Kernel
- State
- Transition semantics
- Proof checker
- Invariant theorems

## 4.2 Law Layer
- Defines transitions
- Encodes policies

## 4.3 Intent Layer
- Goal specifications
- Constraint solving

## 4.4 Context Layer
- Oracles
- External data

---

# 5. Design Properties

### 5.1 Parametric Law
Kernel does not define law.

### 5.2 Proof-Carrying Execution
Every valid transition includes a proof.

### 5.3 Deterministic Semantics
Pure functions + no hidden state.

### 5.4 Minimal TCB
Only Lean + kernel definitions trusted.

---

# 6. Critical Missing Components (Explicit)

## 6.1 Conservation Law
Requires defining finite sums over RBMap.

## 6.2 Authority Model
Currently absent.

## 6.3 Full Map Proofs
RBMap reasoning not yet formalized.

## 6.4 Dispute System
Not yet implemented.

---

# 7. Implementation Roadmap (Refined)

## Phase 1: Kernel Completion
- Eliminate all weak proofs
- Formal RBMap lemmas

## Phase 2: Economic Invariants
- Conservation proofs
- Multi-resource reasoning

## Phase 3: Authority Layer
- Signed transitions
- Permission system

## Phase 4: DSL
- Typed operations
- Serialization

## Phase 5: Runtime
- Lean → C
- Rust integration

## Phase 6: Advanced
- ZK proofs
- Intent solvers

---

# 8. Best Practices Enforced

- Minimal trusted core
- Explicit invariants
- Proof relevance
- Separation of spec/impl
- No hidden assumptions

---

# 9. Final Principle

> The kernel enforces invariants, not meaning.

Meaning lives outside, where it can be debated.

This ensures:
- safety without rigidity
- flexibility without chaos

---

# 10. End State

A universal legal execution layer where:

- Laws are programs
- Legality is a proof
- Governance is a state machine

And all of it is **formally verified**.
