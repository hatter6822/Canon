# Genesis Plan: The Legal Kernel

> A formally grounded, implementation-oriented constitutional kernel built in
> Lean 4. This document is the founding architectural and mathematical
> blueprint for the system.

---

## 0. Document Metadata

| Field        | Value                                                              |
|--------------|--------------------------------------------------------------------|
| Title        | Genesis Plan: The Legal Kernel                                     |
| Status       | Draft (living document)                                            |
| Audience     | Kernel implementers, formal-methods reviewers, protocol designers  |
| Prerequisites| Working knowledge of Lean 4, dependent types, Hoare-style reasoning|
| Scope        | Architecture, formal semantics, invariants, roadmap, threat model  |
| Out of scope | Concrete economic policy, specific jurisdictions, business logic   |

The Genesis Plan is the canonical source of truth for the kernel's design
philosophy, formal model, and implementation strategy. Subsidiary documents
(law specifications, runtime guides, deployment manuals) are downstream of
this one. Where downstream documents disagree with the Genesis Plan, the
Genesis Plan wins until amended.

---

## 1. Executive Summary

The Legal Kernel is a **proof-carrying state transition system** in which
legality is a type, every state change is accompanied by a machine-checkable
proof of admissibility, and global system properties are guaranteed by
inductive invariants rather than by trust in operators.

The kernel is intentionally **small, parametric, and law-free**. It does not
say what is legal; it says what it means for something to be legal, and it
mechanically enforces that nothing else can happen. Specific laws (transfer
rules, permission policies, dispute procedures, economic constraints) are
expressed as values of a `Transition` type and are external to the kernel.

The kernel guarantees four things at the type level:

1. **Determinism.** For any state and any legal transition, the resulting
   state is uniquely determined.
2. **No silent illegality.** A transition whose precondition fails leaves
   the state unchanged; it cannot produce a partial or corrupted state.
3. **Refinement.** Every executable transition step satisfies the
   relational specification of that transition.
4. **Global invariant preservation.** Any property that is true initially
   and is preserved by every legal step is true in every reachable state.

These four properties are proved once, in Lean 4, against the abstract
transition interface. They then hold for every law that conforms to the
interface, by construction.

The remainder of this document develops the mathematical foundations, the
concrete kernel, the architectural layers above it, the components still to
be built, the verification methodology, the threat model, performance
considerations, and a phased roadmap from the current state to a complete
formally verified legal execution layer.

---

## 2. Foundational Concepts

### 2.1 Motivation

Most software systems that govern shared resources (financial ledgers,
identity registries, voting systems, smart contracts, regulatory
compliance engines) rely on **trusted implementations**: humans review
code, auditors stamp it, and the rest of the world hopes the reviewers
were thorough and the implementers honest. When such a system goes wrong,
the failure modes are familiar: silent corruption, ambiguous semantics,
disputes that have no formal procedure of resolution, and emergency
patches that themselves break the rules they were meant to fix.

The Legal Kernel is an attempt to remove the "hope" from this picture. It
asks: what would a system look like if every state change had to come with
a mathematically checkable proof that it was permitted? What would change
if the rules of the system were themselves objects in a programming
language, manipulable, composable, and subject to the same proof
discipline as the kernel itself?

The thesis is that such a system is possible, that Lean 4 is a sufficient
substrate to build it, and that the result is qualitatively different from
both traditional financial software and contemporary smart contract
platforms.

### 2.2 Core Thesis (Formal)

Let $\mathcal{S}$ be a set of states and let $\mathcal{T}$ be a set of
transitions. A transition $t \in \mathcal{T}$ is a pair
$t = (\pi_t, \varphi_t)$ where:

- $\pi_t : \mathcal{S} \to \mathbb{B}$ is a **precondition** (a decidable
  proposition over states), and
- $\varphi_t : \mathcal{S} \to \mathcal{S}$ is a total **state
  transformer**.

A **transition step** is the partial function
$\sigma_t : \mathcal{S} \rightharpoonup \mathcal{S}$ defined by

$$
\sigma_t(s) = \begin{cases} \varphi_t(s) & \text{if } \pi_t(s) \\
                            s            & \text{otherwise}
\end{cases}
$$

The kernel asserts that the *only* way to advance state is via $\sigma_t$
for some $t$, and that proofs of $\pi_t(s)$ are first-class values whose
existence is necessary to exercise the trusted execution path.

The Genesis thesis is then:

> **Legality is a type.** A transition is legal in a state precisely when
> there exists an inhabitant of `Legal s t`, where `Legal s t` is the
> propositional reflection of $\pi_t(s)$. Programs that hold such an
> inhabitant can execute without any further runtime check.

### 2.3 Three Separations

The kernel design is structured around three deliberate separations.
Conflating any of them is a recurring source of error in trust-bearing
systems.

1. **Specification vs. Execution.** A *specification* is a relation
   `step_spec s s' t` that says "`s'` is an admissible result of applying
   `t` to `s`". An *execution* is a function `step_impl s t : State` that
   actually computes a result. The two are linked by a proven refinement
   theorem; neither dominates the other.

2. **Law vs. Mechanism.** A *law* is a value of type `Transition` together
   with the proof obligations its precondition imposes. A *mechanism* is
   the kernel machinery that consumes those values, checks proofs, and
   applies state transformations. The kernel never inspects the *content*
   of a law; it only verifies that legal preconditions hold.

3. **Semantics vs. Verification.** *Semantics* is the meaning of a
   transition: what the function does to the state. *Verification* is the
   accompanying proof that the meaning satisfies declared invariants. The
   kernel can ingest semantics without verification (in which case the
   transition cannot be applied through the certified path) but it never
   accepts verification without semantics.

### 2.4 Design Philosophy

A handful of philosophical commitments drive every later decision.

- **Smallness over features.** The trusted core must fit in a reviewer's
  head. Every kilobyte of kernel code is a kilobyte of attack surface.
- **Totality over partiality.** Every kernel function is total. Failures
  are reified as values (`Option`, `Except`, no-op fallbacks), never as
  uncaught exceptions.
- **Proof obligations over runtime checks.** Where it is cheap to demand a
  proof at compile time, do so. Runtime checks are a code smell in the
  certified execution path.
- **Parametricity over hard-coding.** The kernel takes laws, invariants,
  and authority policies as parameters. Hard-coding any of them would
  collapse the abstraction the kernel is built to provide.
- **Reversibility of opinion.** Anything that depends on contested values
  (what is fair, what is moral, what is good policy) lives outside the
  kernel and can be replaced without touching the trusted core.

---

## 3. Mathematical Preliminaries

This section fixes the mathematical vocabulary used throughout the rest of
the document. Readers familiar with operational semantics and refinement
calculus may skim it; later sections reference these definitions
verbatim.

### 3.1 State Spaces and Transition Systems

A **state space** is a (possibly infinite) set $\mathcal{S}$. A **labelled
transition system** is a triple $(\mathcal{S}, \mathcal{T}, \to)$ where
$\to \subseteq \mathcal{S} \times \mathcal{T} \times \mathcal{S}$ is the
transition relation. We write $s \xrightarrow{t} s'$ for
$(s, t, s') \in \to$.

The Legal Kernel uses a **deterministic** labelled transition system: for
every $s$ and $t$ there is at most one $s'$ with $s \xrightarrow{t} s'$,
and exactly one when $\pi_t(s)$ holds.

The **reachable set** from $s_0$ is the smallest set $R(s_0) \subseteq
\mathcal{S}$ such that:

- $s_0 \in R(s_0)$, and
- if $s \in R(s_0)$ and $s \xrightarrow{t} s'$ for some $t$ with
  $\pi_t(s)$, then $s' \in R(s_0)$.

### 3.2 Inductive Invariants

An **invariant** is a predicate $I : \mathcal{S} \to \mathbb{B}$. An
invariant is **inductive** with respect to a transition system if:

1. **Initiality.** $I(s_0)$ holds.
2. **Preservation.** For every $s$ and $t$, if $I(s)$ and $\pi_t(s)$ then
   $I(\sigma_t(s))$.

The standard induction principle then gives:

$$
\forall s \in R(s_0).\; I(s).
$$

This is the **constitutional guarantee** of the Legal Kernel: any property
proved inductive against the kernel transition relation holds in every
reachable state, irrespective of which laws are loaded.

### 3.3 Refinement

Given a relation $R \subseteq \mathcal{S} \times \mathcal{S}$ and a function
$f : \mathcal{S} \to \mathcal{S}$, we say $f$ **refines** $R$ on
precondition $\pi$ if for every $s$:

$$
\pi(s) \implies (s, f(s)) \in R.
$$

For the kernel, $R$ is the relational specification `step_spec` and $f$ is
the executable `step_impl`. Refinement is the bridge that lets us use the
fast executable path while reasoning about the abstract relational path.

### 3.4 Proof Relevance

Lean 4's type theory distinguishes two universes: `Prop` (proof-irrelevant
propositions) and `Type` (data). The kernel uses both deliberately:

- Preconditions live in `Prop`. The *fact* of legality matters; the
  particular proof object does not.
- Witnesses live in structures (`Legal`, `CertifiedTransition`). The
  presence of such a witness in a function signature is what gives us
  type-level legality; the runtime erases the proof, leaving only the
  state transformation.

This separation is what allows the certified execution path to be free of
runtime checks while still being formally tied to the legality predicate.

### 3.5 Equality, Functional Extensionality, and Decidability

Two practical points to flag for Lean implementers:

- The kernel relies on propositional equality of states (`s = s'`). Because
  `State` is a structure of decidable types over `RBMap`, equality reduces
  to equality of the underlying tree representation. Two states with
  *equal balances but differently shaped trees* are not propositionally
  equal in Lean. The kernel does not rely on representational equality
  except in `step_impl`, where `s' = t.apply_impl s` is by definition.
  When proving conservation and other invariants, we work modulo balance
  equality, lifted via `getBalance`-extensionality lemmas.
- Preconditions used in the certified path must be **decidable**, so that
  `if t.pre s then ... else ...` typechecks without `Classical.dec`.
  Concretely, every law contributed to the system must come with a
  `Decidable (t.pre s)` instance. The kernel's safety properties do not
  require decidability; the executable path does.

---

## 4. The Formal Kernel

This section presents the kernel in full. It is organised top-down: first
the type universe, then state, then balance operations, then the
transition system, then specification/implementation separation, then
proof-carrying legality, then certified execution, then reachability and
the global invariant theorem, then a worked example. Every code block is
intended to compile with Lean 4 and `mathlib`-style `Std`. Where a proof
is currently `sorry`, this is called out explicitly and tracked in the
roadmap.

### 4.1 Type Universe

The kernel is parametric over actor and resource identifiers but commits
to specific representations for them. This is a deliberate trade: by
fixing the representation we obtain decidable equality, total ordering,
and free serialisation; by exposing them only through `abbrev` aliases we
keep the option to swap representations later if cryptographic identity
demands it.

```lean
abbrev ActorId    := UInt64
abbrev ResourceId := UInt64
abbrev Amount     := Nat
```

`ActorId` and `ResourceId` are 64-bit unsigned integers. They are opaque
to the kernel; their meaning (a public key hash, a UUID, a registry
index) is decided by the application layer.

`Amount` is `Nat` (a non-negative integer of unbounded size). The choice
of `Nat` over a fixed-width type is critical: it makes the absence of
overflow a theorem rather than a hope, and it lets the precondition
language express balance constraints natively. The cost is that runtime
representations may exceed 64 bits and must be serialised carefully (see
Section 8.5 and Section 12, Phase 4).

### 4.2 State Representation

State is organised as a two-level finite map: from resource to actor to
amount. Empty entries denote zero balance.

```lean
abbrev BalanceMap := RBMap ActorId Amount compare

structure State where
  balances : RBMap ResourceId BalanceMap compare
  deriving Repr
```

Two design choices warrant comment.

- **Two-level rather than flat.** A flat `RBMap (ResourceId × ActorId)
  Amount` would merge the indices. The two-level form makes per-resource
  reasoning (conservation, total supply, freeze policies) cheaper to
  state and prove because we can quantify over a single `BalanceMap`.
- **`RBMap` rather than `HashMap`.** `RBMap` provides total ordering and
  a deterministic fold order, both of which we need for serialisable,
  reproducible state hashing.

### 4.3 Balance Operations

Two primitives suffice: read and write a single balance.

```lean
def getBalance (s : State) (r : ResourceId) (a : ActorId) : Amount :=
  match s.balances.find? r with
  | none    => 0
  | some bm => (bm.find? a).getD 0

def setBalance (s : State) (r : ResourceId) (a : ActorId) (v : Amount) : State :=
  let bm  := (s.balances.find? r).getD RBMap.empty
  let bm' := bm.insert a v
  { balances := s.balances.insert r bm' }
```

The two functions are mutual inverses up to the natural quotient:
`getBalance (setBalance s r a v) r a = v`, and for `(r', a') ≠ (r, a)`,
`getBalance (setBalance s r a v) r' a' = getBalance s r' a'`.

These two equations are the **balance lemmas**; they are the only
primitive RBMap facts the kernel relies on, and proving them is the
gateway to all higher-level invariants.

```lean
theorem getBalance_setBalance_same
  (s : State) (r : ResourceId) (a : ActorId) (v : Amount) :
  getBalance (setBalance s r a v) r a = v := by
  -- Follows from RBMap.find?_insert (same key) at both levels.
  sorry

theorem getBalance_setBalance_other
  (s : State) (r r' : ResourceId) (a a' : ActorId) (v : Amount)
  (h : r ≠ r' ∨ a ≠ a') :
  getBalance (setBalance s r a v) r' a' = getBalance s r' a' := by
  -- Follows from RBMap.find?_insert (different key) at the appropriate level.
  sorry
```

These are listed as `sorry` for now because they depend on a small library
of `RBMap` lemmas that is itself a work item (see Section 8.3). The
roadmap discharges them in Phase 1.

### 4.4 Transitions

A transition is a precondition together with a state transformer.

```lean
structure Transition where
  apply_impl : State → State
  pre        : State → Prop
```

Three observations.

- `apply_impl` is total. Pre-image filtering is the precondition's job.
- `pre` lives in `Prop`. The *executable* path additionally requires
  `Decidable (pre s)` so that `if pre s then ... else ...` reduces; the
  *certified* path does not.
- The structure intentionally has no name field, no version field, and no
  metadata. Identity and provenance are layered above (Section 8.2).

### 4.5 Specification vs. Implementation

```lean
/-- Relational specification of a transition step. -/
def step_spec (s s' : State) (t : Transition) : Prop :=
  t.pre s ∧ s' = t.apply_impl s

/-- Executable implementation of a transition step. -/
def step_impl (s : State) (t : Transition) : State :=
  if h : t.pre s then t.apply_impl s else s
```

`step_spec` is a relation: it says "`s'` is an admissible successor of
`s` under `t`". `step_impl` is a function: it computes one. They are
linked by the refinement theorem of Section 4.6.

The use of `if h : t.pre s then ... else ...` (with the dependent `h`
in scope on the `then` branch) means that `Decidable (t.pre s)` is
needed for `step_impl` to be definable. In Phase 1 we add a
typeclass instance discipline to enforce decidability at the law
boundary.

### 4.6 Refinement Theorem

```lean
/-- Implementation refines specification when the precondition holds. -/
theorem impl_refines_spec
  (s : State) (t : Transition) (h : t.pre s) :
  step_spec s (step_impl s t) t := by
  unfold step_impl step_spec
  simp [h]

/-- Implementation is the identity when the precondition fails. -/
theorem impl_noop_if_not_pre
  (s : State) (t : Transition) (h : ¬ t.pre s) :
  step_impl s t = s := by
  unfold step_impl
  simp [h]
```

These two theorems together form the **soundness** statement of the
implementation. The first says: every step we actually take is a step the
specification permits. The second says: when the precondition is not
satisfied, the kernel makes no observable change to the world.

### 4.7 Proof-Carrying Legality

Legality is reified as a structure whose only field is the proof of the
precondition.

```lean
/-- A proof that `t` is legal in `s`. -/
structure Legal (s : State) (t : Transition) where
  proof : t.pre s

/-- A transition together with a proof of its legality in a fixed state. -/
structure CertifiedTransition (s : State) where
  t    : Transition
  cert : Legal s t
```

The `Legal` structure has a single field of propositional type. By Lean's
proof irrelevance, two `Legal s t` values are definitionally equal when
their underlying propositions hold; the structure exists purely to give
us a name to bind in function signatures.

`CertifiedTransition` packages the witness with the transition, indexed
by the state in which the legality holds. The dependent index prevents
the obvious mistake of carrying a certification across an unrelated
state change.

### 4.8 Certified Execution

The trusted execution path takes a `CertifiedTransition` and applies its
inner transformer directly, with no runtime check.

```lean
/-- Certified execution: no runtime check, by construction. -/
def apply_certified (s : State) (ct : CertifiedTransition s) : State :=
  ct.t.apply_impl s

theorem apply_certified_eq_step_impl
  (s : State) (ct : CertifiedTransition s) :
  apply_certified s ct = step_impl s ct.t := by
  unfold apply_certified step_impl
  simp [ct.cert.proof]
```

The second theorem closes the loop: the certified path agrees with the
executable path in every state where the latter would have actually
applied the transition. This means the certified path is not a *separate*
semantics; it is an *optimisation* of the executable semantics that the
type system makes safe.

### 4.9 Reachability

The set of states reachable from a given initial state $s_0$ is captured
inductively.

```lean
inductive Reachable (s0 : State) : State → Prop
  | base : Reachable s0 s0
  | step (s : State) (t : Transition)
      (hreach : Reachable s0 s)
      (hpre   : t.pre s) :
      Reachable s0 (step_impl s t)
```

The inductive definition has two constructors. `base` says the initial
state is reachable. `step` says that if `s` is reachable and `t` is legal
in `s`, then `step_impl s t` is reachable. The latter uses the
*executable* step rather than `apply_impl` directly, which means that
even hypothetical illegal applications cannot extend the reachable set
(though by `step`'s `hpre` premise this is a moot point in practice).

Two extensions are deferred to Phase 1:

- A multi-step closure `Reachable*` that quantifies over arbitrary
  transition sequences.
- A version of `Reachable` parametrised by a *law set* `L : Set
  Transition`, restricting reachability to transitions in `L`.

### 4.10 Invariant Preservation Theorem

This is the central theorem of the kernel.

```lean
theorem invariant_preservation
  (I : State → Prop)
  (s0 : State)
  (h_init : I s0)
  (h_step : ∀ s t, I s → t.pre s → I (step_impl s t)) :
  ∀ s, Reachable s0 s → I s := by
  intro s h
  induction h with
  | base => exact h_init
  | step s t hreach hpre ih => exact h_step s t ih hpre
```

This says: any predicate that holds initially and is preserved by every
legal step holds in every reachable state. It is the formal mechanism by
which a single line of work at the law boundary (proving local
preservation) yields a global guarantee.

### 4.11 Worked Example: Transfer

A canonical law: move `amount` units of resource `r` from `sender` to
`receiver`. The naive implementation of this transition has a subtle bug
when `sender = receiver`. The corrected version below sequences the
balance reads through the intermediate state.

```lean
def transfer (r : ResourceId) (sender receiver : ActorId) (amount : Amount)
    : Transition :=
  { apply_impl := fun s =>
      let fromBal := getBalance s r sender
      let s1      := setBalance s r sender (fromBal - amount)
      -- Crucial: read receiver's balance from s1, not s.
      -- When sender = receiver, this preserves the actor's total balance.
      let toBal   := getBalance s1 r receiver
      setBalance s1 r receiver (toBal + amount)
  , pre := fun s =>
      getBalance s r sender ≥ amount ∧ amount > 0
  }
```

Why the sequencing matters. If we instead read `toBal` from `s` (the
original state), then for `sender = receiver` we have `fromBal = toBal`,
and after the debit-then-credit sequence the second `setBalance`
overwrites the first, leaving the actor with `fromBal + amount` rather
than `fromBal`. That violates conservation. Reading `toBal` from `s1`
gives `toBal = fromBal - amount` in the self-transfer case, and the
final balance is `(fromBal - amount) + amount = fromBal`, which is
correct.

The `amount > 0` clause excludes vacuous transfers; this is a policy
choice, not a correctness requirement. It can be relaxed by deleting the
conjunct without breaking any kernel proof.

#### 4.11.1 Local Safety for Transfer

The non-negativity of balances is a free theorem because `Amount = Nat`:
`Nat` cannot be negative, so the property holds by typing alone. The
substantive local property is **conservation per resource**: total
supply is unchanged by any transfer.

```lean
def TotalSupply (s : State) (r : ResourceId) : Nat :=
  match s.balances.find? r with
  | none    => 0
  | some bm => bm.foldl (fun acc _ v => acc + v) 0

theorem transfer_conserves
  (r : ResourceId) (sender receiver : ActorId) (amount : Amount) (s : State)
  (hpre : (transfer r sender receiver amount).pre s) :
  TotalSupply (step_impl s (transfer r sender receiver amount)) r =
  TotalSupply s r := by
  -- Two cases on (sender = receiver):
  --   * Self-transfer: by the sequencing argument above, the actor's
  --     balance is unchanged, hence the fold is unchanged.
  --   * Distinct actors: the sum decreases by `amount` at sender and
  --     increases by `amount` at receiver; the net change is zero.
  -- Both cases are mechanised by `RBMap.foldl_insert` (Section 8.3).
  sorry
```

The proof is currently `sorry`. It is unblocked once the RBMap fold
lemmas of Section 8.3 are in place. The proof obligation is local to the
law and need not touch the kernel.

#### 4.11.2 Cross-Resource Independence

Transfers in resource `r` do not affect balances in any other resource
`r' ≠ r`. This is direct from `getBalance_setBalance_other`.

```lean
theorem transfer_does_not_touch_other_resources
  (r r' : ResourceId) (sender receiver : ActorId) (amount : Amount)
  (a : ActorId) (s : State) (h : r ≠ r') :
  getBalance (step_impl s (transfer r sender receiver amount)) r' a =
  getBalance s r' a := by
  -- Two `setBalance` writes, both at resource `r`; both are absorbed
  -- by `getBalance_setBalance_other`.
  sorry
```

### 4.12 Complete Kernel Listing

Pulling it all together, the kernel module reads:

```lean
import Std.Data.RBMap

open Std

namespace LegalKernel

abbrev ActorId    := UInt64
abbrev ResourceId := UInt64
abbrev Amount     := Nat

abbrev BalanceMap := RBMap ActorId Amount compare

structure State where
  balances : RBMap ResourceId BalanceMap compare
  deriving Repr

def getBalance (s : State) (r : ResourceId) (a : ActorId) : Amount :=
  match s.balances.find? r with
  | none    => 0
  | some bm => (bm.find? a).getD 0

def setBalance (s : State) (r : ResourceId) (a : ActorId) (v : Amount) : State :=
  let bm  := (s.balances.find? r).getD RBMap.empty
  let bm' := bm.insert a v
  { balances := s.balances.insert r bm' }

structure Transition where
  apply_impl : State → State
  pre        : State → Prop

def step_spec (s s' : State) (t : Transition) : Prop :=
  t.pre s ∧ s' = t.apply_impl s

def step_impl (s : State) (t : Transition) : State :=
  if h : t.pre s then t.apply_impl s else s

theorem impl_refines_spec
  (s : State) (t : Transition) (h : t.pre s) :
  step_spec s (step_impl s t) t := by
  unfold step_impl step_spec; simp [h]

theorem impl_noop_if_not_pre
  (s : State) (t : Transition) (h : ¬ t.pre s) :
  step_impl s t = s := by
  unfold step_impl; simp [h]

structure Legal (s : State) (t : Transition) where
  proof : t.pre s

structure CertifiedTransition (s : State) where
  t    : Transition
  cert : Legal s t

def apply_certified (s : State) (ct : CertifiedTransition s) : State :=
  ct.t.apply_impl s

theorem apply_certified_eq_step_impl
  (s : State) (ct : CertifiedTransition s) :
  apply_certified s ct = step_impl s ct.t := by
  unfold apply_certified step_impl; simp [ct.cert.proof]

inductive Reachable (s0 : State) : State → Prop
  | base : Reachable s0 s0
  | step (s : State) (t : Transition)
      (hreach : Reachable s0 s)
      (hpre   : t.pre s) :
      Reachable s0 (step_impl s t)

theorem invariant_preservation
  (I : State → Prop)
  (s0 : State)
  (h_init : I s0)
  (h_step : ∀ s t, I s → t.pre s → I (step_impl s t)) :
  ∀ s, Reachable s0 s → I s := by
  intro s h
  induction h with
  | base => exact h_init
  | step s t hreach hpre ih => exact h_step s t ih hpre

end LegalKernel
```

This is the **trusted core**. Everything else in the system is built on
top of it.

---

## 5. Mathematical Guarantees

This section restates the guarantees the kernel provides, in increasing
order of strength, with explicit proof obligations and references to the
Lean theorems above.

### 5.1 Determinism

**Claim.** For every state $s$ and transition $t$, $\text{step\_impl}(s,
t)$ is uniquely determined.

**Proof.** Lean functions are total and deterministic; the result of
`step_impl s t` is a single inhabitant of `State`, so the claim follows
from typing. There is no need for an additional theorem.

**Consequence.** Two replicas of the kernel that receive the same
initial state and the same transition stream will produce bit-identical
state sequences. This is the foundation of replay verification and
state-hashing protocols (Section 8.6).

### 5.2 Local Safety

**Claim (parametric).** For an invariant $I$ that has been shown to be
preserved by every legal step, $I$ holds after each individual legal
step.

**Lean encoding.**

$$
\forall s\, t.\; I(s) \land \pi_t(s) \implies I(\text{step\_impl}(s, t)).
$$

This is the *hypothesis* `h_step` of `invariant_preservation`. It must
be discharged on a per-invariant basis. The kernel's only role is to
ensure that no other path to state change exists; the truth of the
hypothesis is the law-author's responsibility.

### 5.3 Global Safety

**Claim.** If $I(s_0)$ and local safety hold, then $I(s)$ for every
$s \in R(s_0)$.

**Lean encoding.** This is `invariant_preservation` applied to the law
set in question. A complete deployment will produce one corollary of
`invariant_preservation` per invariant, of the form:

```lean
theorem balance_nonneg_global
  (s0 : State) (h_init : NonNegBalances s0) :
  ∀ s, Reachable s0 s → NonNegBalances s := by
  apply invariant_preservation NonNegBalances s0 h_init
  intro s t hI hpre
  -- One subgoal per law in the deployed law set.
  sorry
```

The "one subgoal per law" structure is what makes the cost of adding a
new law explicit and bounded: a new law adds exactly one preservation
obligation per global invariant.

### 5.4 Refinement Soundness

**Claim.** Every result produced by `step_impl` is a result the
specification permits.

**Lean encoding.** `impl_refines_spec`, restated:

$$
\forall s\, t.\; \pi_t(s) \implies (\pi_t(s) \land \text{step\_impl}(s, t)
= \varphi_t(s)).
$$

The conjunction is trivially true on its first conjunct (the hypothesis)
and on its second by definition of `step_impl` under the assumption.

**Consequence.** Reasoning at the relational level (`step_spec`) and
reasoning at the executable level (`step_impl`) are interchangeable
under the precondition, with no loss of fidelity. This means
specification-level theorems automatically transfer to the executable
path.

### 5.5 No-Op Safety

**Claim.** A transition whose precondition fails leaves the state
unchanged.

**Lean encoding.** `impl_noop_if_not_pre`, restated:

$$
\forall s\, t.\; \neg \pi_t(s) \implies \text{step\_impl}(s, t) = s.
$$

**Consequence.** This is what allows the kernel to "see and refuse"
illegal transitions without raising exceptions or mutating partial
state. Combined with the parametricity of the law set, it means the
kernel can be used as a filter: any transition stream is laundered into
a stream of state-preserving and state-advancing steps with no other
options.

### 5.6 Conservation (per Resource)

**Claim.** For the `transfer` law (and any other law that preserves
total supply), the per-resource total supply is invariant under legal
application.

**Lean encoding.** Given in Section 4.11.1. The proof is `sorry` until
the RBMap fold lemmas of Section 8.3 are in place.

**Generalisation.** Conservation generalises to any *quantity functional*
$Q : \mathcal{S} \to \mathbb{N}$ that decomposes into a fold over
balances. The kernel does not privilege one such functional; downstream
laws that introduce minting, burning, or fees define their own and
discharge the corresponding preservation theorem.

### 5.7 Composability of Invariants

**Claim.** If $I_1$ and $I_2$ are both inductive, then $I_1 \land I_2$
is inductive.

**Lean sketch.**

```lean
theorem invariants_compose
  (I₁ I₂ : State → Prop) (s0 : State)
  (hi₁ : I₁ s0) (hi₂ : I₂ s0)
  (hs₁ : ∀ s t, I₁ s → t.pre s → I₁ (step_impl s t))
  (hs₂ : ∀ s t, I₂ s → t.pre s → I₂ (step_impl s t)) :
  ∀ s, Reachable s0 s → (I₁ s ∧ I₂ s) := by
  apply invariant_preservation (fun s => I₁ s ∧ I₂ s)
  · exact ⟨hi₁, hi₂⟩
  · intro s t ⟨h₁, h₂⟩ hpre
    exact ⟨hs₁ s t h₁ hpre, hs₂ s t h₂ hpre⟩
```

Composability is what lets us *layer* invariants: a deployment can
specify a list of invariants, and the conjunction is itself an
inductive property. This avoids the combinatorial explosion of having
to reprove "everything together" for each new property.

---

## 6. Architectural Layers

The system as a whole is structured as five concentric layers. The
kernel sits at the centre; each subsequent layer depends only on the
layers below it. The trusted computing base is exactly Layer 0.

### 6.0 Overview

```
+-----------------------------------------------------------+
| Layer 4:  Application       (UIs, wallets, dashboards)    |
+-----------------------------------------------------------+
| Layer 3:  Context           (oracles, time, external data)|
+-----------------------------------------------------------+
| Layer 2:  Intent            (goals, constraints, planning)|
+-----------------------------------------------------------+
| Layer 1:  Law               (transitions + proofs)        |
+-----------------------------------------------------------+
| Layer 0:  Kernel            (state, semantics, invariants)|
+-----------------------------------------------------------+
```

Each higher layer is permitted to be wrong, untrusted, or even
adversarial; the kernel guarantees that no behaviour at any higher
layer can violate the invariants discharged at Layer 0/1.

### 6.1 Layer 0: Kernel

**Responsibilities.**

- Define `State`, `Transition`, `Legal`, `CertifiedTransition`,
  `Reachable`.
- Provide `step_impl`, `apply_certified`.
- Prove `impl_refines_spec`, `impl_noop_if_not_pre`,
  `apply_certified_eq_step_impl`, `invariant_preservation`,
  `invariants_compose`.
- Provide the `RBMap` proof library required by laws (Section 8.3).

**Non-responsibilities.**

- Defining any specific law.
- Defining any specific invariant beyond the structural ones.
- Networking, persistence, serialisation, cryptography.

Layer 0 is the only layer that is part of the trusted computing base.
Compromising it requires either a Lean kernel bug or a meta-theoretic
flaw in the invariant proofs.

### 6.2 Layer 1: Law

**Responsibilities.**

- Provide concrete `Transition` values.
- Provide `Decidable (t.pre s)` instances for executable laws.
- Discharge local safety obligations against any deployed invariant.
- Compose laws into law sets, with sub-typed views (e.g. "all transfer
  laws", "all governance laws", "all minting laws").

**Examples.** `transfer`, `mint`, `burn`, `freeze`, `unfreeze`, `vote`,
`enact`.

Layer 1 is *not* trusted in the sense that bugs in a specific law cannot
violate invariants the law was proved to preserve. They can, however,
introduce *new* legal behaviours that are surprising to users; the
mitigation is published, audited, version-controlled law sets.

### 6.3 Layer 2: Intent

**Responsibilities.**

- Express user-level goals as constraints over the trajectory of the
  system.
- Plan sequences of legal transitions that satisfy the constraints.
- Provide search, optimisation, and counter-factual evaluation.

**Examples.** "Move 100 units of resource $r$ from $a_1$ to $a_2$ at
minimum cost", "achieve a target distribution of resource $r$ across a
set of actors", "schedule a payroll satisfying these constraints".

Intents are *plans*, not transitions. They are compiled down to
sequences of certified transitions. Intent compilers are untrusted;
their output is type-checked by the kernel before execution.

### 6.4 Layer 3: Context

**Responsibilities.**

- Provide external data: prices, timestamps, randomness, off-chain
  facts.
- Sign and date oracle reports.
- Bridge the gap between deterministic kernel state and a
  non-deterministic outside world.

Context is the interface to non-determinism. Every oracle reading
becomes part of state via a transition (e.g. `record_price`), so even
external data enters the system through the proof discipline.

### 6.5 Layer 4: Application

**Responsibilities.**

- Render state to humans.
- Solicit intents from users.
- Interpret kernel outputs in domain-specific terms.

Applications are entirely untrusted. They cannot do harm because they
cannot bypass the kernel; they can mislead, however, and so should be
audited as if they were untrusted.

### 6.6 Layer Boundaries and the Trusted Computing Base

The trusted computing base (TCB) is precisely:

- The Lean 4 type checker.
- The `Std.Data.RBMap` definitions (and any other `Std` modules used).
- The kernel module of Section 4.12.

Concretely, the TCB is *bounded by what is checked when you compile the
kernel module*. Anything outside that compilation unit is, by
construction, outside the TCB.

A pragmatic implication: any time we add to the kernel, we must
explicitly justify the addition in TCB terms. The phased roadmap of
Section 12 follows this discipline.

---

## 7. Design Properties

The properties below are not *theorems* about the kernel; they are
*design constraints* that the kernel must satisfy and that future
extensions must respect. Each is followed by a falsifiable test: a
description of what evidence would refute the property.

### 7.1 Parametric Law

**Property.** The kernel does not refer to any specific law.

**Falsifying evidence.** A grep of the kernel source shows references
to a named law (e.g. `transfer`, `mint`).

**Status.** Holds as of this writing. The example `transfer` is
defined in a downstream module, not in the kernel module.

### 7.2 Proof-Carrying Execution

**Property.** Every value produced by the certified execution path is
accompanied by a proof of legality at the type level.

**Falsifying evidence.** A function in the kernel that returns a
post-state without consuming a `Legal` or `CertifiedTransition`
witness.

**Status.** Holds. `apply_certified` requires a `CertifiedTransition`
argument; `step_impl` is the alternative path and explicitly performs
the runtime check.

### 7.3 Deterministic Semantics

**Property.** For every $s$ and $t$, `step_impl s t` is a unique value.

**Falsifying evidence.** A non-deterministic primitive (e.g. random
number generation) inside the kernel.

**Status.** Holds. The kernel has no non-deterministic primitives.

### 7.4 Minimal Trusted Computing Base

**Property.** The TCB is exactly the kernel module of Section 4.12,
plus the Lean type checker and the `Std` types it imports.

**Falsifying evidence.** A second module that must be trusted in order
for kernel theorems to be sound.

**Status.** Holds, with the noted dependency on `Std.Data.RBMap`.
Phase 1 includes a review of the exact `Std` lemmas the kernel relies
on, and a plan to either pin them or replace them with locally-stated
equivalents.

### 7.5 Compositionality

**Property.** Invariants and laws compose without re-proof.

**Falsifying evidence.** A pair of invariants $I_1$, $I_2$ each proved
inductive, whose conjunction $I_1 \land I_2$ requires non-trivial
additional argument to be inductive.

**Status.** Holds, by `invariants_compose` (Section 5.7).

### 7.6 Total Functions

**Property.** Every kernel function is total.

**Falsifying evidence.** A `partial def` or a use of `Classical.choice`
in the kernel module.

**Status.** Holds. The kernel uses no partial definitions and no
classical axioms.

### 7.7 Erasability of Proofs

**Property.** Proof objects do not appear in the runtime
representation of certified transitions; they are erased by the Lean
compiler.

**Falsifying evidence.** Disassembled bytecode of `apply_certified`
contains references to `Legal` proof structures rather than only to
`apply_impl`.

**Status.** To be verified in Phase 5 (extraction). Lean's compilation
strategy erases `Prop`-valued fields, so the property is expected to
hold; the verification is mechanical.

### 7.8 Explicitness of Failure

**Property.** Whenever the kernel cannot make progress, the failure is
visible as a value (no-op state, returned `Except`, etc.) and never as
an exception.

**Falsifying evidence.** A kernel function that throws.

**Status.** Holds; no kernel function throws.

---

## 8. Critical Components

The kernel as defined in Section 4 is necessary but not sufficient.
Several components must be added before the kernel can support a
real-world deployment. This section names each gap, gives a formal
treatment of what fills it, and points to the roadmap phase that
addresses it.

### 8.1 Conservation Law

**Gap.** The kernel does not yet have a proof that any specific quantity
is conserved across transitions.

**Formal definition.** For a resource $r$, the **total supply** at state
$s$ is

$$
T_r(s) = \sum_{a \in \text{Actors}} \text{getBalance}(s, r, a).
$$

Because `getBalance` returns `0` for actors not in the underlying
`BalanceMap`, the sum is finite and equal to a fold over the map's
explicit entries. The Lean encoding is:

```lean
def TotalSupply (s : State) (r : ResourceId) : Nat :=
  match s.balances.find? r with
  | none    => 0
  | some bm => bm.foldl (fun acc _ v => acc + v) 0
```

**Conservation theorem (statement).** For every transition $t$ in a
*conservative* law set $L_C$:

$$
\forall s\, r.\; \pi_t(s) \implies T_r(\sigma_t(s)) = T_r(s).
$$

Lean:

```lean
theorem law_set_conserves
  (L : Set Transition) (hL : ∀ t ∈ L, IsConservative t)
  (s : State) (t : Transition) (htL : t ∈ L) (hpre : t.pre s)
  (r : ResourceId) :
  TotalSupply (step_impl s t) r = TotalSupply s r := by
  exact hL t htL r s hpre
```

**Required lemmas.**

1. `RBMap.foldl_insert_present`: folding after `insert` of a key already
   present updates the accumulator by the new value minus the old.
2. `RBMap.foldl_insert_absent`: folding after `insert` of a fresh key
   adds the new value to the accumulator.
3. `RBMap.foldl_eq_sum_of_values`: the fold equals the multiset sum of
   the values, independent of insertion order.

These are tracked in Section 8.3.

**Roadmap.** Phase 2.

### 8.2 Authority Model

**Gap.** Anyone holding a transition value can construct a `Legal`
witness if the precondition holds. There is no notion of *who* is
permitted to apply a given transition.

**Formal model.** Introduce **identities** and **policies**.

```lean
abbrev PublicKey := ByteArray
abbrev Signature := ByteArray

structure Identity where
  id  : ActorId
  key : PublicKey

structure SignedTransition where
  inner   : Transition
  signer  : ActorId
  payload : ByteArray   -- canonical encoding of `inner`
  sig     : Signature

structure AuthorityPolicy where
  authorized : ActorId → Transition → Prop
  registry   : RBMap ActorId PublicKey compare
```

A signed transition is **authorised** in policy $P$ at state $s$ when:

1. $P$.authorized(signer, inner) holds, and
2. $P$.registry maps `signer` to a public key `pk`, and
3. `Verify(pk, payload, sig) = true`, and
4. `payload = canonical_encode(inner)`.

```lean
def Authorised
  (P : AuthorityPolicy) (st : SignedTransition) : Prop :=
  P.authorized st.signer st.inner ∧
  ∃ pk, P.registry.find? st.signer = some pk ∧
        Verify pk st.payload st.sig = true ∧
        st.payload = canonicalEncode st.inner
```

The kernel exposes a guarded variant of `apply_certified` that consumes
both a `Legal` witness *and* an `Authorised` witness:

```lean
def apply_authorised
  (P : AuthorityPolicy) (s : State)
  (st : SignedTransition)
  (auth : Authorised P st)
  (cert : Legal s st.inner) : State :=
  st.inner.apply_impl s
```

**Cryptographic primitives.** `Verify` is treated as an *uninterpreted*
function in the kernel; its security properties (existential
unforgeability under chosen-message attack) are assumed. The choice of
signature scheme (Ed25519, ECDSA over secp256k1, post-quantum
alternatives) is a deployment decision.

**Replay protection.** Authorised transitions must include a nonce or
sequence number to prevent re-application; this is the subject of
Section 8.5.

**Roadmap.** Phase 3.

### 8.3 RBMap Proof Library

**Gap.** Several kernel and law-level theorems depend on `RBMap`
properties not yet formalised.

**Required lemmas.**

```lean
-- Pointwise behaviour
theorem RBMap.find?_insert_self
  (m : RBMap κ α cmp) (k : κ) (v : α) :
  (m.insert k v).find? k = some v

theorem RBMap.find?_insert_other
  (m : RBMap κ α cmp) (k k' : κ) (v : α) (h : k ≠ k') :
  (m.insert k v).find? k' = m.find? k'

-- Fold behaviour
theorem RBMap.foldl_insert_absent
  (m : RBMap κ α cmp) (k : κ) (v : α)
  (f : β → κ → α → β) (init : β)
  (h : m.find? k = none) :
  (m.insert k v).foldl f init = f (m.foldl f init) k v

theorem RBMap.foldl_insert_present
  (m : RBMap κ α cmp) (k : κ) (v_old v_new : α)
  (f : β → κ → α → β) (init : β)
  (h : m.find? k = some v_old) :
  (m.insert k v_new).foldl f init =
  -- requires `f` to be commutative on disjoint keys; see below
  ...
```

The fold lemmas require either:

- A *commutative monoid* assumption on the fold operation (sufficient
  for sums, products, and bag-style aggregates), or
- An explicit *re-fold* expression that "undoes" the old value and
  applies the new (more general but harder to use).

The conservation proofs use the commutative monoid path.

**Library shape.** The library lives in `LegalKernel.RBMapLemmas` and is
imported by both the kernel (where it is part of the TCB by extension)
and by laws.

**Roadmap.** Phase 1.

### 8.4 Dispute System

**Gap.** When two parties disagree about the legality of a transition
or the value of an oracle, the kernel has no formal mechanism for
resolution.

**Formal model.** A **dispute** is a structured assertion that a
specific transition is illegal, paired with evidence. An
**adjudication** is a transition that resolves a dispute by either
upholding or rejecting the challenge.

```lean
inductive DisputeClaim
  | preconditionFalse (t : Transition) (s : State)
  | oracleMisreported (oracleId : ActorId) (claimed actual : ByteArray)
  | doubleSpend       (t1 t2 : Transition) (s : State)

structure Dispute where
  challenger : ActorId
  claim      : DisputeClaim
  evidence   : ByteArray

inductive Adjudication
  | uphold  (d : Dispute)
  | reject  (d : Dispute) (counter_evidence : ByteArray)
```

Adjudications themselves are transitions, governed by an authority
policy: only the designated adjudicator(s) may sign them, and only the
disputed actor (or a quorum) may file a `Dispute`.

**Adjudication semantics.** An upheld dispute against a state-transition
$t$ on state $s$ produces a *rollback* transition that restores
$s$ as the new current state. Because the kernel is deterministic,
the rollback is unambiguous: $s$ is reproducible from the genesis
state and the recorded transition log.

**Liveness.** Disputes must be resolved within a bounded time window;
otherwise the system can stall. Liveness is *not* guaranteed by the
kernel; it is a property of the deployed adjudication policy, and the
kernel exposes a primitive that lets the policy enforce timeouts.

**Roadmap.** Phase 6.

### 8.5 Time, Nonces, and Replay Protection

**Gap.** The kernel as defined has no notion of time. Two identical
authorised transitions submitted at different "real-world" times are
indistinguishable to the kernel, which means a replay of an old
signed transfer would succeed.

**Formal mitigation.** Embed a monotonic counter (a "nonce") in
authorised transitions, and maintain per-actor next-expected-nonce in
state.

```lean
abbrev Nonce := UInt64

structure NonceState where
  next : RBMap ActorId Nonce compare

structure ExtendedState where
  base   : State
  nonces : NonceState

def expectsNonce (es : ExtendedState) (a : ActorId) : Nonce :=
  (es.nonces.next.find? a).getD 0

def advanceNonce (es : ExtendedState) (a : ActorId) : ExtendedState :=
  { es with nonces :=
    { next := es.nonces.next.insert a (expectsNonce es a + 1) } }
```

A signed transition's precondition is augmented to require
`signer_nonce = expectsNonce es signer`, and its `apply_impl` is
augmented to call `advanceNonce`.

**Time as a context variable.** When wall-clock time matters (for
expiry, vesting, scheduled execution), it enters via a `Context` oracle
transition that records the current time as part of state. The kernel
makes no assumption about the relationship between consecutive recorded
times beyond monotonicity, which the oracle policy must enforce.

**Roadmap.** Phase 3 (alongside the authority model).

### 8.6 Bootstrap and Genesis State

**Gap.** Where does $s_0$ come from?

**Formal answer.** The genesis state is a *fixed value* embedded in the
deployed kernel binary. Its hash is published; the deployment is only
considered legitimate if its embedded genesis hashes to that value.

```lean
def genesis : State :=
  { balances := RBMap.empty }
  -- Or, for a non-trivial deployment, an explicit construction.
```

For deployments with non-trivial genesis (initial balances, registered
identities, default policies), the value is generated by a *genesis
script* whose output is reviewed and then frozen into the binary.

**Migrations.** The kernel does not support upgrading a live deployment
to a new genesis. Migrations across kernel versions are explicit:
either a state-export-and-reimport sequence, or a *bridge transition*
that maps Old Kernel state to New Kernel state via a one-time
authorised step.

**Roadmap.** Phase 0 (bootstrap script) and Phase 5 (migration
protocol).

### 8.7 Persistence and Logging

**Gap.** The kernel is purely in-memory.

**Formal model.** A **transition log** is a sequence of authorised
transitions:

$$
L = [(s_0, t_0, s_1), (s_1, t_1, s_2), \ldots, (s_{n-1}, t_{n-1}, s_n)].
$$

The deployment guarantees:

1. The log is append-only.
2. Each entry is signed by the kernel runtime (in addition to the
   transition's own signer) so that log entries are non-repudiable.
3. The current state $s_n$ is reproducible from $s_0$ and the log,
   bit-for-bit, by replay.

Persistence is implemented at the *runtime* level (Section 12, Phase 5),
not in the kernel. The kernel exposes the determinism property that
makes replay possible.

---

## 9. Verification Methodology

This section defines how we *do* verification, not what we verify.
Discipline at this level is the difference between a kernel that is
"probably correct" and one that is provably correct.

### 9.1 Proof Style

- **Forward proofs** for short, computational obligations; **backward
  proofs** (`apply`-style) for theorems with structural induction.
- **`simp`-only at trusted lemma boundaries.** Every use of `simp`
  inside the kernel module names its rewrite set explicitly. No
  appeals to `simp` with the default set inside trusted code.
- **No `sorry` in the kernel.** Outside the kernel, `sorry` is allowed
  but tracked: every `sorry` carries a `-- TODO(genesis-#NN)` tag
  pointing to a roadmap item.
- **`by decide` is discouraged for security-sensitive propositions.**
  It hides assumptions that should be visible.

### 9.2 Tactic Discipline

- Prefer `exact` over `apply` where it costs nothing in length.
- Use `refine` with metavariables for medium-size goals; do not nest
  more than two levels deep.
- Avoid `omega` and `linarith` inside the kernel module; both are large
  and would expand the TCB. They are fine in law modules.
- Name every hypothesis. Anonymous hypotheses (`intro`, `intros` with
  no names) are allowed only in one-line proofs.

### 9.3 Test Strategy

The kernel has formal proofs; tests are still useful for:

- Detecting regressions in `Std.Data.RBMap` between Lean versions.
- Validating extraction (Phase 5) against a reference implementation.
- Sanity-checking law preconditions on hand-crafted examples.

Tests live in `LegalKernel/Test/` and are executed by `lake test`.

### 9.4 Property-Based Testing

Use `Plausible` (or `SlimCheck`) to generate random states and
transitions and check that:

- `step_impl` is total (no panics, no exceptions).
- `step_impl s t = step_impl s t` (determinism).
- For laws with proven invariants, the invariant holds on the
  post-state.

Property-based testing complements formal proof; it is *not* a
substitute. Its value is in catching specification bugs that the proofs
do not address (e.g. a precondition that is too weak in practice but
correctly proved).

### 9.5 Fuzzing

For the runtime layer (Phase 5), fuzz the parser, the signature
verifier, and the canonical encoder. The kernel itself has no
parser-shaped attack surface; the runtime that feeds it does.

### 9.6 Continuous Verification

CI on every commit:

1. `lake build` (compile everything, including all proofs).
2. `lake test` (run tests).
3. `lake exe count_sorries` (must be zero in the kernel module; must be
   non-increasing in the rest of the codebase).
4. `lake exe tcb_audit` (lists all imports of the kernel module; must
   match a hand-maintained allowlist).

A failing CI blocks merge.

---

## 10. Threat Model

We enumerate the threats the kernel is and is not designed to defend
against, and the trust assumptions on which the defences depend.

### 10.1 In-Scope Threats

- **Malicious laws** that attempt to violate a deployed invariant.
  Defence: invariants are inductive, so a law that violated them would
  fail to compile. Status: defended by `invariant_preservation`.
- **Forged certifications.** A `Legal s t` value can only be
  constructed by exhibiting a proof of `t.pre s`; forging one requires
  forging a Lean proof, which requires a soundness bug in Lean.
  Defence: type system. Status: as strong as Lean.
- **State corruption via partial transitions.** A transition whose
  precondition fails leaves state untouched. Status: defended by
  `impl_noop_if_not_pre`.
- **Non-deterministic divergence between replicas.** Defence: the
  kernel is purely functional. Status: defended by typing.
- **Replay of old authorised transitions.** Defence: per-actor nonces
  (Section 8.5). Status: planned for Phase 3.

### 10.2 Out-of-Scope Threats

- **Compromise of the operating system or hardware** running the
  kernel. The kernel cannot defend against an attacker who can
  arbitrarily modify memory. Mitigation: deploy on hardened hosts;
  use attestation.
- **Compromise of the Lean type checker.** A flaw in Lean's type
  theory would invalidate kernel proofs. Mitigation: track Lean
  releases; pin to audited versions.
- **Compromise of cryptographic primitives.** A break of the
  signature scheme would invalidate the authority layer. Mitigation:
  use widely-reviewed schemes; design to allow algorithmic agility.
- **Liveness attacks.** The kernel guarantees safety, not liveness.
  An adversary that prevents transitions from being submitted (DoS)
  cannot violate invariants but can prevent progress. Mitigation:
  deployment-level concerns (rate limiting, redundancy).

### 10.3 Trust Assumptions

To rely on the kernel's guarantees, you must trust:

1. The Lean 4 type checker (a few thousand lines of well-reviewed C++).
2. The `Std` library's `RBMap` (bounded by Phase 1 audit; see Section
   7.4).
3. The kernel module of Section 4.12.
4. The operating system kernel and hardware on which Lean runs.
5. (For authorised transitions only) The cryptographic primitives.

Note that *you do not trust* the law authors, the application
developers, the oracle providers, or the network operators. Their
malice is bounded by what the kernel will accept.

### 10.4 Side Channels

The kernel's pure-functional structure has no observable side channels
*within the Lean runtime*. After extraction (Phase 5), timing channels
become possible:

- Signature verification time may leak signing key material; use
  constant-time implementations.
- `RBMap.find?` is logarithmic but not constant-time; this can in
  principle leak which keys are present. For most deployments this is
  acceptable; for high-assurance ones, swap `RBMap` for a
  constant-time data structure (perforce a non-trivial change).

These mitigations are deployment-time, not kernel-time, decisions.

---

## 11. Performance Considerations

Performance is a property of the *deployed runtime*, not the formal
kernel; nonetheless, decisions in the kernel determine the achievable
performance envelope.

### 11.1 Asymptotic Costs

Let $n_r$ denote the number of distinct actors holding resource $r$ in
state $s$, and let $R$ denote the number of distinct resources.

| Operation                       | Cost                      |
|---------------------------------|---------------------------|
| `getBalance s r a`              | $O(\log R + \log n_r)$    |
| `setBalance s r a v`            | $O(\log R + \log n_r)$    |
| `transfer.apply_impl`           | $O(\log R + \log n_r)$    |
| `transfer.pre`                  | $O(\log R + \log n_r)$    |
| `step_impl`                     | cost of `pre` + `apply_impl` |
| `apply_certified`               | cost of `apply_impl`      |
| `TotalSupply s r`               | $O(n_r)$                  |
| `Reachable` membership          | not decidable in general  |

The constants are dominated by `RBMap` rebalancing. For most realistic
workloads this is acceptable; for ledgers with very large actor sets
($n_r > 10^7$) the constants begin to matter and a custom radix-trie
representation may be warranted.

### 11.2 Proof Verification Cost

Compiling the kernel is a one-time cost paid by the implementer. The
runtime cost of *checking* a `Legal` witness is zero, because the
witness is a proof object that has been erased: the type system has
already verified it.

The cost of *constructing* a `Legal` witness is the cost of running the
`Decidable` instance for `t.pre s`, which is the same as evaluating
`t.pre s`. For the laws contemplated here this is $O(\log R + \log n_r)$.

### 11.3 Extraction Targets

Three target backends are contemplated for Phase 5.

- **Lean's native compiler** (LLVM via C). Highest fidelity to the
  proven semantics; reasonable performance; available today.
- **Hand-written Rust runtime** with an interpreter for serialized
  transitions. Better integration with existing infrastructure;
  introduces a translation layer that must itself be verified or
  fuzzed.
- **WASM** for in-browser deployment. Lowest performance; widest
  reach. Not contemplated in the initial roadmap.

A mixed deployment is likely: Lean-native for the trusted runtime, Rust
for the network and storage layers, with a strict serialization
boundary between them.

### 11.4 Memory Profile

State is held in memory as a tree of `RBMap`s. A naive estimate per
`(resource, actor, amount)` triple is roughly:

- 16 bytes for the actor ID and amount.
- 24-32 bytes of `RBMap` node overhead (colour bit, two child pointers,
  possibly key/value boxes).

Call this $\sim 50$ bytes per entry. A million-actor, ten-resource
deployment is then $\sim 500$ MB of working set, before any history
retention. This is within reach of modern hardware but argues for
careful capacity planning.

### 11.5 Concurrency

The kernel is single-threaded by design. Concurrent submission of
transitions is the runtime's problem; the runtime serialises them and
feeds them to the kernel one at a time. This is acceptable for
moderate throughput (thousands of transitions per second) and avoids
the proof-explosion that concurrent semantics would require.

For higher throughput, one path is **sharding by resource**: state for
disjoint resource sets lives in different kernel instances, with a
lightweight cross-shard transition protocol. This is contemplated as a
post-Phase-7 extension and is mentioned here only to note that the
Phase 0-7 plan does not require it.

---

## 12. Implementation Roadmap

The roadmap is organised into eight phases (0 through 7). Each phase
has explicit entry criteria, deliverables, exit criteria, and
dependencies. Phase 0 is partially complete; subsequent phases assume
their predecessors.

### Phase 0: Foundations

**Entry criteria.** Lean 4 toolchain installed; repository initialised.

**Deliverables.**

- `lakefile.lean` and `lean-toolchain` pinned to a known-good Lean
  version.
- The kernel module of Section 4.12, compiling cleanly.
- The example `transfer` law (Section 4.11), with the self-transfer
  bug fix incorporated.
- Initial CI pipeline (`lake build` + `lake test`).
- This document.

**Exit criteria.** All deliverables present; CI green.

**Status.** In progress; this document is part of the deliverables.

### Phase 1: Kernel Completion

**Entry criteria.** Phase 0 complete.

**Deliverables.**

- `LegalKernel.RBMapLemmas` module with the lemmas of Section 8.3.
- All `sorry` markers in the kernel module discharged.
- `getBalance_setBalance_same` and `getBalance_setBalance_other`
  proven.
- `Decidable` instances for example law preconditions.
- Documentation of every `Std` lemma the kernel relies on.

**Exit criteria.** `lake exe count_sorries` returns 0 for the kernel
module; the TCB audit list is published.

### Phase 2: Economic Invariants

**Entry criteria.** Phase 1 complete.

**Deliverables.**

- `TotalSupply` definition.
- `transfer_conserves` proven (no `sorry`).
- A `Conservative` typeclass capturing per-resource conservation.
- `law_set_conserves` (Section 8.1) proven against the typeclass.
- An optional `mint`/`burn` law set in a separate module, with its own
  (non-conservative) law set.

**Exit criteria.** Conservation theorems compile; the conservative law
set excludes mint/burn at the type level.

### Phase 3: Authority Layer

**Entry criteria.** Phase 1 complete (Phase 2 not strictly required
but recommended).

**Deliverables.**

- `Identity`, `SignedTransition`, `AuthorityPolicy` (Section 8.2).
- `Authorised` predicate and `apply_authorised` function.
- Per-actor nonce state (Section 8.5).
- `canonicalEncode` for `Transition` values.
- A reference signature scheme adaptor (Ed25519).

**Exit criteria.** A signed-and-authorised transfer can be replayed
exactly once and is rejected on second submission.

### Phase 4: DSL and Serialization

**Entry criteria.** Phase 3 complete.

**Deliverables.**

- A surface DSL for laws (`law transfer (r) (sender receiver) (amount)
  ...`) that elaborates to `Transition` values.
- A canonical binary encoding for `Transition` values, with round-trip
  proofs.
- A canonical binary encoding for `State`.
- A reference deserialiser with bounds checks proved.

**Exit criteria.** A law written in the DSL produces an identical
elaborated `Transition` to its hand-written equivalent; round-trip
serialisation is provably the identity on well-formed inputs.

### Phase 5: Runtime and Extraction

**Entry criteria.** Phase 4 complete.

**Deliverables.**

- Lean-native runtime: a binary that loads genesis, accepts a
  transition stream over a documented protocol, applies certified
  transitions, persists the log.
- Extraction notes documenting which Lean constructs survive
  compilation and which are erased.
- A Rust adaptor for network and storage, with a strict ABI to the
  Lean runtime.
- Replay tool: takes a genesis hash and a log, reconstructs final
  state, and verifies the hash matches.

**Exit criteria.** The replay tool reproduces final state from any
recorded log; persistence is crash-consistent (verified by fault
injection tests).

### Phase 6: Disputes and Adjudication

**Entry criteria.** Phase 5 complete.

**Deliverables.**

- `DisputeClaim`, `Dispute`, `Adjudication` (Section 8.4).
- A reference adjudication policy with timeouts.
- Rollback transitions for upheld disputes.
- A challenger UI (untrusted; lives in Layer 4).

**Exit criteria.** A planted illegal transition can be challenged,
adjudicated, and rolled back, with the rollback itself a recorded
authorised transition.

### Phase 7: Advanced Capabilities

**Entry criteria.** Phase 6 complete.

**Deliverables.**

- Zero-knowledge proof integration: produce a ZK-SNARK that a
  transition was applied correctly without revealing the transition
  payload. Useful for privacy-preserving deployments.
- Intent solver integration: a constraint-solving frontend that
  produces sequences of certified transitions satisfying user goals.
- Cross-shard protocol (sketch only; full work is post-roadmap).

**Exit criteria.** Per-feature acceptance criteria, defined when each
feature begins.

### Phase Dependency Graph

```
Phase 0  ──►  Phase 1  ──►  Phase 2
                  │
                  ├──►  Phase 3  ──►  Phase 4  ──►  Phase 5  ──►  Phase 6  ──►  Phase 7
```

### Estimated Effort

These are calibration ranges, not commitments. They assume one
full-time formal-methods engineer and contemplate no parallelism.

| Phase | Estimate (engineer-weeks) |
|-------|--------------------------|
| 0     | 2 (mostly complete)      |
| 1     | 4-6                      |
| 2     | 3-5                      |
| 3     | 6-8                      |
| 4     | 4-6                      |
| 5     | 8-12                     |
| 6     | 6-10                     |
| 7     | 12+ (open-ended)         |

---

## 13. Tooling and Build

### 13.1 Toolchain

- **Lean 4** (pinned in `lean-toolchain`).
- **Lake** (Lean's build system).
- **Mathlib** is *not* a kernel dependency; the kernel uses `Std` only.
  Law modules may use Mathlib for convenience.
- **`elan`** for toolchain version management.

### 13.2 Repository Layout

```
LegalKernel/
├── Kernel.lean              -- Section 4.12 (TCB).
├── RBMapLemmas.lean         -- Section 8.3 (TCB by extension).
├── Laws/
│   ├── Transfer.lean        -- Section 4.11.
│   ├── Mint.lean
│   └── ...
├── Authority/
│   ├── Signed.lean          -- Section 8.2.
│   └── Nonce.lean           -- Section 8.5.
├── Disputes/
│   └── Adjudication.lean    -- Section 8.4.
├── Runtime/                 -- Phase 5; not part of TCB.
└── Test/
    ├── KernelTests.lean
    └── PropertyTests.lean
docs/
├── GENESIS_PLAN.md          -- This document.
└── ...
```

### 13.3 CI

GitHub Actions (or equivalent), with one workflow per push:

```yaml
jobs:
  build:
    steps:
      - uses: actions/checkout@v4
      - uses: leanprover/lean-action@v1
      - run: lake build
      - run: lake test
      - run: lake exe count_sorries
      - run: lake exe tcb_audit
```

### 13.4 Reproducibility

- Build artifacts are reproducible byte-for-byte across machines that
  share the same `lean-toolchain`.
- The genesis hash is published in `docs/GENESIS.txt` and verified by
  CI.
- Each release tag is signed.

### 13.5 Local Developer Workflow

```bash
elan toolchain install $(cat lean-toolchain)
lake build               # full build
lake build LegalKernel.Kernel   # kernel only (fastest feedback)
lake test
```

A fast inner loop targets the kernel module; full builds are run
before commit.

---

## 14. Best Practices Enforced

Many of the following are restatements or refinements of points
appearing earlier in the document; collecting them here gives reviewers
a single checklist.

### 14.1 Source Discipline

- One `namespace` per file; namespaces match file paths.
- No top-level definitions outside a namespace.
- All public definitions documented with a doc-comment that names the
  property they encode.
- All `theorem`s named with a verb-first convention
  (`step_impl_refines_step_spec`, `transfer_conserves_supply`).

### 14.2 Proof Discipline

- No `sorry` in the kernel module. Ever.
- Every `sorry` in non-kernel modules carries a `TODO(genesis-#NN)`
  tag.
- No unnamed hypotheses except in one-line proofs.
- No use of `Classical.choice` in trusted modules.
- No use of `omega`/`linarith` in trusted modules.

### 14.3 Naming Discipline

- `getX` / `setX` for state accessors.
- `X_pre`, `X_post`, `X_inv` for precondition, postcondition, invariant
  predicates of law `X`.
- `X_refines_Y` for refinement theorems.
- `X_preserves_Y` for invariant preservation lemmas.

### 14.4 Review Discipline

- All changes to the kernel module require two reviewers, one of whom
  must be a formal-methods specialist.
- All changes to `RBMapLemmas` likewise require two reviewers.
- Other modules require one reviewer.
- A change that increases the TCB requires explicit Genesis-Plan
  amendment.

### 14.5 Operational Discipline

- Every release is accompanied by a public Lean compilation log proving
  zero `sorry` in the kernel.
- Every release publishes the genesis hash and the kernel module hash
  side-by-side.
- Bug reports against the kernel are triaged within 48 hours; security
  bugs within 4.

---

## 15. Open Research Questions

The kernel as planned is *complete enough to ship*, but several
questions remain genuinely open. We list them here so that work in
adjacent areas (academic and industrial) can be matched to the
project's needs.

### 15.1 Decidability at the Boundary

The kernel admits any `Prop`-valued precondition, but `step_impl`
requires `Decidable (t.pre s)`. Is there a clean way to *enforce*
decidability at the law-boundary type level, so that a non-decidable
law cannot be elaborated into the executable path? A natural candidate
is a `DecidableTransition` newtype wrapping `Transition` with a
`Decidable` instance bundled in.

### 15.2 Concurrent Semantics

Single-threaded semantics are a deliberate choice, but if the
deployment target eventually demands true concurrency, what is the
right operational model? Linear types? An STM-style serialiser? A
proof-relevant variant of linearisability? Each option implies a
different proof burden.

### 15.3 ZK Integration

For privacy-preserving deployments we want to publish a proof that
"some legal transition occurred" without revealing which one. This
requires either:

- Compiling kernel proof terms into ZK circuits (research-grade), or
- Designing a parallel circuit-friendly kernel and proving an
  observational equivalence to the Lean kernel (probably more
  tractable).

### 15.4 Cross-Shard Atomicity

If state is sharded across multiple kernel instances, how do we get
atomicity for cross-shard transitions? Two-phase commit is the obvious
candidate; verifying it inductively at the kernel level is non-trivial.

### 15.5 Reasoning About Liveness

The kernel guarantees safety. Liveness (every legal transition
eventually applies) is a property of the deployment, not the kernel.
Is there a kernel-level abstraction (a "fairness oracle"?) that lets
us reason about liveness without coupling to a specific scheduler?

### 15.6 Mechanised Proof of Refinement to Extracted Code

Lean's compilation strategy is, today, *not* itself formally verified
end-to-end. The closest thing is the soundness of the type theory plus
careful manual review of the runtime. A proof that the extracted code
preserves the kernel's denotational semantics would close this gap.

### 15.7 Upgrade Paths

Migrations between kernel versions are described as "explicit bridge
transitions" (Section 8.6). Is there a more general theory? In
particular: when can two kernel versions be shown *observationally
equivalent* on a subset of states, so that an upgrade is a no-op for
deployments that stay within the subset?

---

## 16. Final Principles

These are the principles to which all design decisions return when
debate becomes intractable.

### 16.1 The Kernel Enforces Invariants, Not Meaning

The kernel does not know what a "transfer" *means*. It knows that some
function `transfer.apply_impl` exists, that some predicate
`transfer.pre` exists, and that the latter implies the former
preserves any invariant that was proven preserved by it. Meaning is
the law-author's job; meaning lives at Layer 1 and above.

### 16.2 Safety Without Rigidity

Because the kernel is parametric in its laws, the same kernel can run
arbitrarily different deployments without modification. A change of
policy is a change of inputs, not a change of code.

### 16.3 Flexibility Without Chaos

Because every state change requires a proof, no amount of policy
flexibility can produce an illegal state. The space of permitted
behaviours can be as large as the law-author chooses; the *guarantees*
on that space remain.

### 16.4 No Hidden Assumptions

Every assumption the kernel makes is named: `Decidable` for executable
paths, the `Std.Data.RBMap` lemmas for fold reasoning, the cryptographic
soundness assumption for authority. None hides in a comment, in a test,
or in a developer's head.

### 16.5 Versioning as a First-Class Concern

The kernel module is hashed, versioned, and signed. The genesis state
is hashed, versioned, and signed. Migrations are themselves
transitions, hashed, versioned, and signed. There is no part of the
system that lacks an unambiguous identity.

### 16.6 The Future Is a Plan, Not a Promise

The roadmap of Section 12 commits to a *direction*, not to specific
delivery dates. The Genesis Plan is a living document; it will be
amended as we learn. Amendments are tracked, justified, and reviewed
with the same discipline as the kernel itself.

---

## 17. End State Vision

When fully implemented, the Legal Kernel will provide:

- A **universal legal execution layer** in which any rule expressible
  as a decidable precondition over a finite state space can be enforced
  with mathematical certainty.
- A **proof-carrying execution model** in which every state change
  carries a witness of its legality, free of runtime checks.
- A **deterministic, replayable** ledger whose state at any time is
  reproducible from the genesis state and the transition log.
- An **authority and dispute system** that gives every action an
  identifiable signer and every disagreement a formal procedure of
  resolution.
- A **modular architecture** in which laws, policies, intents, and
  applications can be developed independently of the kernel and of
  each other.
- A **minimal trusted computing base** of a few hundred lines of Lean,
  reviewable by a single specialist in a day.

In one sentence:

> Laws are programs, legality is a proof, governance is a state machine,
> and the whole of it is formally verified.

---

## Appendix A. Glossary

- **Actor.** An identity that can submit transitions. Represented in
  state by an `ActorId`.
- **Adjudication.** A transition that resolves a dispute. Section 8.4.
- **Authority Policy.** A predicate over `(ActorId, Transition)` pairs
  describing who is permitted to do what. Section 8.2.
- **Balance.** The amount of a given resource held by a given actor in
  a given state. Returned by `getBalance`.
- **Certified Transition.** A `Transition` paired with a proof of its
  legality in a specific state. Section 4.7.
- **Conservation.** Preservation of total supply across legal
  transitions. Section 8.1.
- **Decidable Precondition.** A precondition for which Lean can compute
  a `Bool` deciding it. Required for the executable path. Section 3.5.
- **Genesis State.** The initial state of a deployment. Section 8.6.
- **Inductive Invariant.** A predicate that holds initially and is
  preserved by every legal step. Section 3.2.
- **Kernel.** The trusted module of Section 4.12.
- **Law.** A `Transition` value, typically defined in Layer 1.
- **Legal.** A proof-bearing structure asserting a transition's
  precondition holds in a state. Section 4.7.
- **No-Op Safety.** The property that `step_impl s t = s` when
  `t.pre s` is false. Section 4.6.
- **Nonce.** A monotonic per-actor counter preventing transition
  replay. Section 8.5.
- **Proof-Carrying Execution.** A discipline in which every state
  change consumes a proof of admissibility. Section 1.
- **Reachable State.** A state derivable from the genesis state by a
  finite sequence of legal transitions. Section 4.9.
- **Refinement.** The property that an executable function satisfies a
  relational specification. Section 3.3, Section 4.6.
- **Resource.** A class of fungible token. Represented by `ResourceId`.
- **Specification.** A relational description of admissible state
  successors. `step_spec` in Lean.
- **State.** The two-level finite map of resource to actor to balance.
  Section 4.2.
- **Step.** Either `step_spec` (relation) or `step_impl` (function).
- **Total Supply.** The sum of balances of a given resource across all
  actors. Section 8.1.
- **Trusted Computing Base (TCB).** The set of components that must be
  correct for the system's guarantees to hold. Section 6.6.

---

## Appendix B. Notation

The mathematical notation in this document follows standard
conventions. A short reference:

| Symbol           | Meaning                                                |
|------------------|--------------------------------------------------------|
| $\mathcal{S}$    | The set of all states                                  |
| $\mathcal{T}$    | The set of all transitions                             |
| $s, s'$          | Specific states                                        |
| $t$              | A specific transition                                  |
| $\pi_t$          | The precondition of transition $t$                     |
| $\varphi_t$      | The state-transformer of transition $t$                |
| $\sigma_t$       | The combined `step_impl` for $t$                       |
| $R(s_0)$         | The reachable set from initial state $s_0$             |
| $I$              | An invariant (a predicate over states)                 |
| $\to$            | The transition relation                                |
| $T_r(s)$         | The total supply of resource $r$ in state $s$          |
| $\mathbb{N}$     | The non-negative integers                              |
| $\mathbb{B}$     | The booleans                                           |

Lean-specific notation:

| Lean              | Mathematical reading                              |
|-------------------|---------------------------------------------------|
| `t.pre s`         | $\pi_t(s)$                                        |
| `t.apply_impl s`  | $\varphi_t(s)$                                    |
| `step_impl s t`   | $\sigma_t(s)$                                     |
| `step_spec s s' t`| $(s, s') \in \mathord{\to_t}$ (graph of $\sigma_t$) |
| `Reachable s0 s`  | $s \in R(s_0)$                                    |
| `Legal s t`       | proof-relevant carrier of $\pi_t(s)$              |

---

## Appendix C. References

The Genesis Plan does not depend on external citations to be
mechanically checked, but the design draws on a tradition of work that
deserves naming.

- **Refinement calculus.** Back & von Wright, *Refinement Calculus*
  (1998). The spec/impl separation in Section 4.5 is in this lineage.
- **Hoare logic.** Hoare, *An Axiomatic Basis for Computer
  Programming* (1969). The pre/post discipline in `Transition` is
  Hoare-shaped.
- **Lean 4 type theory.** de Moura & Ullrich, *The Lean 4 Theorem
  Prover and Programming Language* (2021). The substrate for the
  whole kernel.
- **Operational semantics of state machines.** Plotkin, *A Structural
  Approach to Operational Semantics* (1981).
- **Inductive invariant proofs.** Manna & Pnueli, *Temporal
  Verification of Reactive Systems* (1995).
- **Proof-carrying code.** Necula, *Proof-Carrying Code* (1997). The
  spirit of `CertifiedTransition` is here.
- **Smart-contract verification.** Various; the negative space (what
  goes wrong without these disciplines) motivates the kernel.

These are signposts, not formal dependencies. The Genesis Plan stands
on its own definitions and proofs.

---

## Appendix D. Change Log

This is the founding revision. Subsequent amendments will be appended
below with a date, an author, a one-line summary, and a link to the
amending discussion.

| Revision | Date       | Summary                                       |
|----------|------------|-----------------------------------------------|
| 1.0      | 2026-05-03 | Initial Genesis Plan (this document).         |

---

*End of document.*
