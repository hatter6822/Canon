/-
LegalKernel.Kernel — the trusted core.

This module is the literal Section 4.12 listing of the Genesis Plan
(`docs/GENESIS_PLAN.md`).  Every line in this file is part of the
trusted computing base (TCB) of every deployment that uses Canon, so
changes here MUST come with a Genesis-Plan amendment and the
two-reviewer gate described in §13.6 / §14.4.

Imports: `Std.Data.TreeMap` is the canonical ordered finite-map in
Lean 4 ≥ 4.10 core.  The Genesis Plan was written when std4 still
exposed `Std.Data.RBMap`; the modern equivalent in Lean core is the
`TreeMap` family in the same `Std` namespace, with a red-black tree
backing and the same API surface used by §4.3 and §4.11 (insert,
find?, foldl, getD).  The plan's "kernel uses `Std` only" rule is
preserved verbatim; only the dependency name has changed.

No `sorry` may appear in this file.  The two balance lemmas of §4.3
(`getBalance_setBalance_same`, `getBalance_setBalance_other`) live in
`LegalKernel.RBMapLemmas` (Phase 1 WU 1.5); they intentionally do not
appear here, so that the Phase-0 kernel builds with zero `sorry`.
-/

import Std.Data.TreeMap

open Std

namespace LegalKernel

/-! ## Type universe (§4.1) -/

/-- Opaque identifier for an actor (key, account, principal). -/
abbrev ActorId    : Type := UInt64

/-- Opaque identifier for a resource (asset, currency, registry). -/
abbrev ResourceId : Type := UInt64

/-- Non-negative balance.  Using `Nat` makes overflow absence a
    theorem (rather than an audit), at the cost of unbounded
    serialised width — see §8.8 for the canonical encoding. -/
abbrev Amount     : Type := Nat

/-! ## State (§4.2) -/

/-- Per-resource map from actor → balance.  Empty entries denote zero
    balance. -/
abbrev BalanceMap : Type := TreeMap ActorId Amount compare

/-- Global state: a two-level finite map from resource → actor →
    amount.  See §4.2 for the rationale (per-resource reasoning,
    deterministic fold for hashing). -/
structure State where
  balances : TreeMap ResourceId BalanceMap compare
  deriving Repr

/-! ## Balance operations (§4.3) -/

/-- Read a balance.  Missing entries at either level return `0`. -/
def getBalance (s : State) (r : ResourceId) (a : ActorId) : Amount :=
  match s.balances[r]? with
  | none    => 0
  | some bm => bm[a]?.getD 0

/-- Write a balance, allocating an empty per-resource map if needed.
    `setBalance` is deliberately total: partiality lives in the
    transition's precondition, never in the state-transformer. -/
def setBalance (s : State) (r : ResourceId) (a : ActorId) (v : Amount) :
    State :=
  let bm  := s.balances[r]?.getD ∅
  let bm' := bm.insert a v
  { balances := s.balances.insert r bm' }

/-! ## Transitions (§4.4) -/

/-- A transition is a precondition, a per-state decision procedure for
    that precondition, and a total state transformer.

    * `pre` is in `Prop` so that quantifiers, implications, and
      existence statements compose without `Bool`-coding artefacts.
    * `decPre` is the *constructive* witness that `pre` is effectively
      decidable on every state — without it, `step_impl` could not
      reduce.  For all laws built from arithmetic comparisons and
      finite conjunctions, `decPre := fun _ => inferInstance` is a
      one-liner; see §13.6 for the discipline.
    * `apply_impl` is total.  Pre-image filtering is the
      precondition's job, not the transformer's. -/
structure Transition where
  pre        : State → Prop
  decPre     : (s : State) → Decidable (pre s)
  apply_impl : State → State

/-- Re-export `decPre` as a typeclass instance so that ordinary
    `if t.pre s then ... else ...` notation elaborates.  This is a
    *definition*, not a trusted axiom; deleting it would only make
    `if`-elaboration fail at the call site. -/
instance instDecidableTransitionPre (t : Transition) (s : State) :
    Decidable (t.pre s) := t.decPre s

/-! ## Specification and implementation (§4.5) -/

/-- Relational specification: `s'` is an admissible successor of `s`
    under `t` exactly when `t.pre` holds in `s` and `s'` matches the
    transformer's output. -/
def step_spec (s s' : State) (t : Transition) : Prop :=
  t.pre s ∧ s' = t.apply_impl s

/-- Executable implementation.  Decidability of `t.pre s` flows from
    the `instDecidableTransitionPre` instance above, so the `if`
    reduces with no recourse to ambient classical logic. -/
def step_impl (s : State) (t : Transition) : State :=
  if t.pre s then t.apply_impl s else s

/-! ## Refinement theorems (§4.6) -/

/-- Implementation refines specification when the precondition holds:
    every step we actually take is one the spec permits. -/
theorem impl_refines_spec
    (s : State) (t : Transition) (h : t.pre s) :
    step_spec s (step_impl s t) t := by
  unfold step_impl step_spec
  simp [h]

/-- Implementation is the identity when the precondition fails: no
    silent partial-state corruption is possible. -/
theorem impl_noop_if_not_pre
    (s : State) (t : Transition) (h : ¬ t.pre s) :
    step_impl s t = s := by
  unfold step_impl
  simp [h]

/-! ## Proof-carrying legality (§4.7) -/

/-- A proof that `t` is legal in `s`.  Single-field by design: by
    proof-irrelevance, any two `Legal s t` values are definitionally
    equal once `t.pre s` holds. -/
structure Legal (s : State) (t : Transition) where
  proof : t.pre s

/-- A transition together with a proof of legality in a fixed state.
    The dependent index `s` prevents the obvious mistake of carrying
    a certificate across an unrelated state change. -/
structure CertifiedTransition (s : State) where
  t    : Transition
  cert : Legal s t

/-! ## Certified execution (§4.8) -/

/-- Trusted execution: takes the dependent witness and applies the
    transformer directly, with no runtime check. -/
def apply_certified (s : State) (ct : CertifiedTransition s) : State :=
  ct.t.apply_impl s

/-- The certified path agrees with the executable path in every state
    where the latter would have applied the transition.  This means
    `apply_certified` is an *optimisation* of `step_impl`, not a
    separate semantics. -/
theorem apply_certified_eq_step_impl
    (s : State) (ct : CertifiedTransition s) :
    apply_certified s ct = step_impl s ct.t := by
  unfold apply_certified step_impl
  simp [ct.cert.proof]

/-! ## Reachability (§4.9) -/

/-- States reachable from `s0` via a finite sequence of legal steps.
    The `step` constructor builds on `step_impl` (not `apply_impl`),
    so even hypothetical illegal applications cannot extend the
    reachable set. -/
inductive Reachable (s0 : State) : State → Prop
  | base : Reachable s0 s0
  | step (s : State) (t : Transition)
      (hreach : Reachable s0 s)
      (hpre   : t.pre s) :
      Reachable s0 (step_impl s t)

/-! ## Invariant preservation (§4.10) -/

/-- The central theorem of the kernel: any predicate that holds in the
    initial state and is preserved by every legal step holds in every
    reachable state.  Proving a global property reduces to proving
    *local* preservation, which scales linearly with `(laws ×
    invariants)` rather than combinatorially. -/
theorem invariant_preservation
    (I : State → Prop) (s0 : State)
    (h_init : I s0)
    (h_step : ∀ s t, I s → t.pre s → I (step_impl s t)) :
    ∀ s, Reachable s0 s → I s := by
  intro s h
  induction h with
  | base                       => exact h_init
  | step s t _hreach hpre ih   => exact h_step s t ih hpre

/-- Conjunction of invariants is itself an invariant; deployments can
    reason about a *list* of invariants without re-proving each
    pairwise combination. -/
theorem invariants_compose
    (I₁ I₂ : State → Prop) (s0 : State)
    (hi₁ : I₁ s0) (hi₂ : I₂ s0)
    (hs₁ : ∀ s t, I₁ s → t.pre s → I₁ (step_impl s t))
    (hs₂ : ∀ s t, I₂ s → t.pre s → I₂ (step_impl s t)) :
    ∀ s, Reachable s0 s → (I₁ s ∧ I₂ s) := by
  apply invariant_preservation (fun s => I₁ s ∧ I₂ s) s0
  · exact ⟨hi₁, hi₂⟩
  · intro s t hI hpre
    exact ⟨hs₁ s t hI.1 hpre, hs₂ s t hI.2 hpre⟩

/-! ## Build identification.

A trivial constant whose presence lets non-kernel code (Main, tests)
confirm at link time that the kernel module compiled without having to
exercise any actual transition.  Bumped by hand whenever §4.12
changes; mirror in §13.8 release-cutting runbook. -/
def kernelBuildTag : String := "canon-phase-0-foundations"

end LegalKernel
