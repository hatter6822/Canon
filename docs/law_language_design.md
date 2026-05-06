<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

# Canon Law Language: A Design for Code-As-Law

This document specifies the design of a high-level surface language
for writing **laws** in Canon — the deployment-facing complement of
the Phase 0–6 kernel.  It supersedes the minimal Phase-4 `law` macro
(`LegalKernel/DSL/Law.lean`, WU 4.9) by extending it with mandatory
authority binding, structured property claims, frozen wire indices,
literate-program intent blocks, and a deployment-manifest layer.

The language is non-TCB.  Its elaborator is a Lean 4 macro family
that produces ordinary `Transition` and `Action` declarations passing
through the existing kernel typing rules; the trusted core
(`Kernel.lean` + `RBMapLemmas.lean`) does not grow.

> **Working name.**  This document refers to the language as "Lex"
> (Latin: *law*) for brevity.  The name is provisional; the
> repository commits to no marketing brand at this stage.

---

## Table of Contents

  1. [Purpose and scope](#1-purpose-and-scope)
  2. [The two-audience problem](#2-the-two-audience-problem)
  3. [Architectural choice: embedded elaboration to Lean](#3-architectural-choice-embedded-elaboration-to-lean)
  4. [Design principles](#4-design-principles)
  5. [Surface syntax](#5-surface-syntax)
  6. [Elaboration semantics](#6-elaboration-semantics)
     * 6.1. [The decidable precondition grammar (`Pre`)](#61-the-decidable-precondition-grammar-pre)
     * 6.2. [The flow calculus (`impl`)](#62-the-flow-calculus-impl)
     * 6.3. [Authority binding (`signed_by` / `authorized_by`)](#63-authority-binding-signed_by--authorized_by)
     * 6.4. [Property dispatch (`satisfies`)](#64-property-dispatch-satisfies)
     * 6.5. [Action registration (`action_index`)](#65-action-registration-action_index)
     * 6.6. [Event emission (`events`)](#66-event-emission-events)
     * 6.7. [Resource roles (deferred to v3)](#67-resource-roles-deferred-to-v3)
  7. [Deployment manifests](#7-deployment-manifests)
  8. [Governance and amendment](#8-governance-and-amendment)
  9. [Tooling](#9-tooling)
  10. [Diagnostics](#10-diagnostics)
  11. [Deliberate exclusions](#11-deliberate-exclusions)
  12. [Migration plan](#12-migration-plan)
  13. [Roadmap](#13-roadmap)
  14. [Open questions](#14-open-questions)
  15. [Worked examples](#15-worked-examples)

---

## 1. Purpose and scope

Lex is the surface language a deployment uses to **declare a new law**.
A law is a state-transition rule: a precondition, a deterministic
implementation, and a bundle of provable properties (conservation,
monotonicity, locality, freeze-preservation, …).  The language exists
to compress what is currently 7 mechanical edits per law into a
single declaration:

  1. add a constructor to `Action` (Genesis Plan §4.13);
  2. add a `compileTransition` branch (`Authority/Action.lean`);
  3. add CBE encode / decode branches (`Encoding/Action.lean`);
  4. add a `fieldsBounded` branch (`Encoding/Action.lean`);
  5. add an `extractEvents` branch (`Events/Extract.lean`);
  6. add a `non_replaceKey_preserves_registry` branch
     (`Authority/SignedAction.lean`);
  7. supply `IsConservative` / `IsMonotonic` instances (or negative
     witnesses) (`Conservation.lean` consumers).

Each of these is a *consequence* of the law's behaviour, not an
independent design choice.  Lex captures the law once and emits all
seven artefacts.

**In scope:**

  * Single-deployment laws that extend the global `Action` inductive
    (§4.13) at a freshly-allocated frozen index ≥ 12.
  * Re-expression of the existing 12 kernel-built-in laws (`transfer`,
    `mint`, `burn`, `freezeResource`, `replaceKey`, `reward`,
    `distributeOthers`, `proportionalDilute`, `dispute`,
    `disputeWithdraw`, `verdict`, `rollback`) in Lex form, as a
    correctness check that the language can express what the kernel
    already ships.
  * Deployment manifests that bind a law set, an authority
    configuration, a deployment ID, and a list of invariant claims.

**Out of scope (this revision):**

  * Deployment-private laws that do **not** appear in the global
    `Action` inductive.  Per-deployment Action extension is a Phase-7
    runtime-adaptor change; Lex v1 ships kernel-extension laws only.
    The mechanism is sketched in §6.5 and §13 but not specified here.
  * Resource roles (phantom-typed `Currency` / `VotingPower` / …
    markers).  Specified at sketch level in §6.7 and deferred to v3
    once a deployment surfaces a concrete need.
  * Custom dispute-claim variants.  Phase 6 froze the five §8.4.1
    claim variants; new variants are a Genesis-Plan amendment, not a
    Lex feature.

Lex is **not** a vehicle for changing the kernel's threat model, its
TCB, or its on-wire formats.  Every Lex declaration produces output
within the existing surface; the language adds expressiveness, not
trust.

## 2. The two-audience problem

A law is *both* executable code (it runs in the runtime,
deterministically, against `ExtendedState`) and a *governance
artefact* (it is reviewed by people who decide whether it encodes
the policy they want).  These audiences want incompatible things:

| Audience      | Wants                                                                  |
|---------------|------------------------------------------------------------------------|
| Runtime       | precision, type safety, decidability, performance, no ambiguity        |
| Governance    | readability, version-stable identity, amendment trail, semantic diff   |
| Auditors      | a one-screen contract surface that names the proven properties         |
| Operators     | a manifest that says exactly which laws this deployment runs           |
| Counterparties| a way to verify they sign against the same law text the operator runs  |

The current Phase-4 macro (`law pre := … ; impl := …`) addresses only
the runtime audience.  It produces a `Transition` with the
`decPre := fun _ => inferInstance` discipline filled in, and stops
there.  The other audiences are served, today, by 1100 lines of
hand-written `Authority/Action.lean` plus `Encoding/Action.lean` plus
`Events/Extract.lean` plus per-law instance proofs — all of which
must be kept in lock-step by review-time discipline.

Lex resolves the tension by being **a literate-program surface where
the law text is its own documentation**.  Each law carries:

  * a canonical natural-language statement of intent (`intent` block,
    versioned and covered by the manifest signature);
  * the formal precondition (`pre`) and implementation (`impl`) — the
    executable surface;
  * a declarative bridge (`satisfies` block) that names the formal
    properties the natural-language intent informally guarantees.

The reviewer's job is to read the `intent` block and decide whether
the `pre` / `impl` / `satisfies` bundle correctly encodes it.  The
elaborator's job is to mechanically check that the `satisfies`
properties really hold.  Neither audience has to read the other's
material.

## 3. Architectural choice: embedded elaboration to Lean

Lex is a Lean 4 macro family.  It is **not** a standalone language
with its own parser and elaborator.  This choice closes three risks:

  1. **TCB hygiene.**  A standalone elaborator becomes trusted by
     virtue of producing the kernel's input.  The current TCB
     (`Kernel.lean` + `RBMapLemmas.lean`) is ~1100 lines of Std-only
     Lean.  An external parser / elaborator would either need a
     comparable correctness audit or would expand the TCB by an
     unbounded amount.  Embedded macros run *before* type-checking,
     produce ordinary Lean declarations, and the kernel's existing
     `lake exe count_sorries` / `lake exe tcb_audit` gates apply
     unchanged.
  2. **Proof-search reuse.**  The `decPre := fun _ => inferInstance`
     discipline (WU 1.6, `docs/decidability_discipline.md`) only
     works because Lean's instance-resolution sees the precondition
     in its native form.  A standalone language would have to
     re-implement decidability inference and the typeclass database.
  3. **Property dispatch.**  `IsConservative` / `IsMonotonic` /
     `FreezePreserving` (Phase-4-prelude WUs R.1–R.4) are typeclasses
     dispatched by Lean's instance synthesizer.  Generating instance
     declarations from outside Lean is feasible but requires
     reproducing a non-trivial fragment of the Lean elaborator.

The cost of embedding is that Lex inherits Lean 4's macro syntax
constraints and Lean's error messages.  Section 10 specifies the
diagnostic-translation layer that addresses the second.  The first
is mitigated by careful syntax design (§5).

> **Why not a standalone configuration format (e.g. JSON / YAML /
> CBOR) that the runtime parses?**  A configuration format describes
> *which* laws to run; it cannot describe *what a law does* without
> shipping the law's compiled bytes — which makes the format itself
> the surface that needs review.  Once the format is reviewable, it
> needs typed primitives, decidability, and property declarations,
> at which point it has reinvented Lex.  The shorter path is to
> start from a real type system.

## 4. Design principles

Six principles drive every concrete choice in §5 and §6.  Each is
stated tersely; the justification follows.

  1. **Decidability is enforced by grammar.**  Preconditions are
     built only from shapes that `inferInstance` can discharge.  The
     elaborator does not attempt to *prove* decidability for novel
     predicates; it requires that the precondition expression
     parse-fits the grammar of §6.1.  Predicates that do not fit are
     a parse error, not a "failed to synthesize Decidable" error
     buried 60 lines into the macro expansion.

  2. **Flows are first-class; everything else is suspect.**  A
     primitive `flow r: amt from a to b` desugars to the §4.11
     transfer pattern verbatim, including the self-transfer fix
     (post-debit re-read of the receiver), and emits
     `IsConservative` and `IsMonotonic` mechanically.  Operations
     that create or destroy supply use distinct keywords (`mint`,
     `burn`, `reward`).  The asymmetry is the point: a reviewer
     scanning a 200-line law file wants `mint` and `burn` to be
     visually jarring, and wants `flow` to be unremarkable.

  3. **Contracts are mandatory, machine-checked, and one-screen.**
     Every law declares a `satisfies` block listing the formal
     properties it claims.  The elaborator either discharges each
     item or fails with a precise residual obligation.  A law
     without a `satisfies` block is a parse error.  The contract is
     the reviewer's primary surface — the proof is hidden until
     needed.

  4. **Authority binding is structural, not optional.**  Every law
     declares `signed_by <actor>` and (for any non-trivial mutation)
     `authorized_by <policy>`.  The elaborator wires both into the
     §8.2 `Admissible` predicate automatically.  There is no "I
     forgot to advance the nonce" failure mode because the macro
     forbids omitting the binding.

  5. **Frozen indices are immovable.**  Each law commits to an
     `action_index: N` that becomes a wire-format commitment forever
     (CBE constructor tag, Genesis Plan §8.8).  The elaborator
     refuses any change that would break replay of historical logs.
     Version bumps within a fixed index are allowed only if they
     refine the old behaviour (provable refinement obligation).

  6. **Natural-language intent is part of the artefact.**  Every law
     carries an `intent` block — a markdown-typed natural-language
     statement that the deployment manifest's signature covers.  An
     amendment to the `intent` block without a corresponding code
     change requires the same governance signature as a code change.
     This prevents "policy laundering" where the executable
     behaviour stays put while the human-readable description
     silently drifts.

These principles compose: (1) and (2) make the executable layer
tractable; (3) and (4) make the contract layer mandatory; (5) and
(6) make amendment safe.  Drop any one and the others lose force.

## 5. Surface syntax

A Lex law is a single Lean `command` that opens with the `law`
keyword.  The body is a sequence of named *clauses*; clause order
inside the body is fixed (so reviewers always read the manifest
fields, then the formal text, then the contract, in the same
order).

### 5.1. Grammar

```ebnf
law             ::= "law" ident "(" params ")" "where" clause+

params          ::= (binder ("," binder)*)?
binder          ::= ident+ ":" type

clause          ::= header_clause
                  | body_clause

header_clause   ::= "identifier"   ident_path
                  | "version"      string_lit
                  | "action_index" nat_lit
                  | "intent"       md_block

body_clause     ::= "signed_by"    actor_expr
                  | "authorized_by" policy_expr
                  | "pre"          ":=" pre_expr
                  | "impl"         ":=" impl_block
                  | "satisfies"    ":=" property_list
                  | "events"       ":=" event_block
                  | "proof"        ident ":=" tactic_block

ident_path      ::= ident ("." ident)*
md_block        ::= "{" raw_text_until_balanced_close "}"
pre_expr        ::= <restricted, see §6.1>
impl_block      ::= "do" do_stmt+
do_stmt         ::= "flow"   resource_expr ":" amount_expr
                          "from" actor_expr "to" actor_expr
                  | "mint"   resource_expr ":" amount_expr "to"   actor_expr
                  | "burn"   resource_expr ":" amount_expr "from" actor_expr
                  | "reward" resource_expr ":" amount_expr "to"   actor_expr
                  | "for"    ident "in" bounded_iter ":" do_stmt
                  | "if"     pre_expr "then" do_stmt ("else" do_stmt)?
                  | "let"    ident ":=" term
                  | "register_key"   actor_expr "as" key_expr
                  | "revoke_key"     actor_expr
                  | "freeze_resource" resource_expr
                  | <bare term, must have type State → State>

property_list   ::= "[" property ("," property)* "]"
property        ::= "conservative"      "[" resource_set "]"
                  | "monotonic"         "[" resource_set "]"
                  | "local"             "[" resource_set "]"
                  | "freeze_preserving" "[" resource_set "]"
                  | "nonce_advances"    "[" actor_expr   "]"
                  | "registry_preserving"
                  | ident                                   -- user-defined

resource_set    ::= "{" (resource_expr ("," resource_expr)*)? "}"
                  | "*"                                     -- all resources
                  | resource_expr                           -- shorthand for {r}

event_block     ::= "do" emit_stmt+
emit_stmt       ::= "emit" event_ctor (term)*
                  | "for" ident "in" bounded_iter ":" emit_stmt
                  | "if" pre_expr "then" emit_stmt ("else" emit_stmt)?
```

`bounded_iter` is any expression of type `List α` produced by
`BalanceMap.toList`, `KeyRegistry.toList`, `NonceState.toList`, or
the user's own helpers — concretely, anything Lean can recognise as
a finite list.  Streams, infinite sequences, and `IO`-monad iterators
are forbidden.

`tactic_block` is raw Lean tactic syntax.  It is the escape hatch
for `satisfies` items that the property-discharge library cannot
handle on its own (§6.4).

### 5.2. Worked example: `transfer` in Lex

```
law transfer (r : ResourceId) (sender receiver : ActorId) (amount : Nat)
where
  identifier   legalkernel.transfer
  version      "1.0.0"
  action_index 0

  intent {
    Move `amount` units of resource `r` from `sender` to `receiver`.
    Sender must have at least `amount` and `amount` must be positive.
    Self-transfer (sender = receiver) is a no-op on net balance and
    is permitted; the precondition still requires `amount > 0` and
    sufficient balance.
  }

  signed_by      sender
  authorized_by  deployment.transfer_policy sender r

  pre := fun s =>
    amount > 0 ∧ getBalance s r sender ≥ amount

  impl := do
    flow r: amount from sender to receiver

  satisfies := [
    conservative      [r],
    monotonic         [r],
    local             [r],
    freeze_preserving [*],
    nonce_advances    [sender],
    registry_preserving
  ]

  events := do
    let pre_sender   := getBalance s r sender
    let pre_receiver := getBalance s r receiver
    if amount > 0 then emit BalanceChanged r sender   (pre_sender   - amount) pre_sender
    if amount > 0 then emit BalanceChanged r receiver (pre_receiver + amount) pre_receiver
```

This declaration is the *complete* source of truth for the
`transfer` law.  The current 7-edit hand-written form
(`Authority/Action.lean`'s `transfer` constructor + `compileTransition`
case + `Encoding/Action.lean` encode / decode / fieldsBounded cases
+ `Events/Extract.lean` event case + `Conservation.lean` /
`Laws/Transfer.lean`'s `IsConservative` and `IsMonotonic` instances)
is generated mechanically from it.  The `intent` block is the prose
the manifest signs.

### 5.3. Worked example: `mint` in Lex

```
law mint (r : ResourceId) (minter receiver : ActorId) (amount : Nat)
where
  identifier   legalkernel.mint
  version      "1.0.0"
  action_index 1

  intent {
    Create `amount` units of resource `r` in `receiver`'s balance.
    Authorised actors only; signature by `minter`.  Non-conservative
    by design — issues new supply.
  }

  signed_by      minter
  authorized_by  deployment.mint_policy minter r

  pre := fun s => amount > 0

  impl := do
    mint r: amount to receiver

  satisfies := [
    monotonic         [r],
    local             [r],
    freeze_preserving [*],   -- minting a frozen resource is rejected by `pre` of `freezeResource`
    nonce_advances    [minter],
    registry_preserving
  ]
  -- conservative is *not* claimed; mint is not IsConservative.
  -- Adding `conservative [r]` to the list above would fail
  -- elaboration with diagnostic L004.

  events := do
    let pre_balance := getBalance s r receiver
    if amount > 0 then emit BalanceChanged r receiver (pre_balance + amount) pre_balance
```

### 5.4. Worked example: `replaceKey` in Lex

```
law replaceKey (actor : ActorId) (newKey : PublicKey)
where
  identifier   legalkernel.replaceKey
  version      "1.0.0"
  action_index 4

  intent {
    Rotate `actor`'s public key in the deployment's KeyRegistry.
    Signed by the actor's previous key (verified at admissibility
    time); the post-state has `newKey` registered for `actor`.
  }

  signed_by      actor
  authorized_by  deployment.identity_policy actor

  pre := fun _s => True

  impl := do
    register_key actor as newKey

  satisfies := [
    conservative      [*],
    monotonic         [*],
    local             [],         -- touches no resource
    freeze_preserving [*],
    nonce_advances    [actor]
    -- registry_preserving is *not* claimed; this law mutates the registry.
  ]

  events := do
    emit IdentityRegistered actor newKey
```

### 5.5. Lexical conventions

  * **Comments.**  Lean's `--` and `/- -/` work inside Lex as in any
    Lean file.  The `intent` block is *not* a comment; its content
    is captured into the elaborated declaration as a docstring.
  * **Whitespace.**  Significant only inside the `impl` and `events`
    `do` blocks (Lean 4 `do`-block alignment rules apply).  Header
    clauses are insensitive to indentation.
  * **Binders.**  Lex parameters use Lean binder syntax verbatim;
    instance binders (`[…]`), implicit binders (`{…}`), and strict
    implicit binders (`⦃…⦄`) are all valid.  This is what enables
    role-typed laws (§6.7) to be expressed without new syntax.
  * **Naming.**  Lex law names follow the project naming convention
    (CLAUDE.md: `snake_case`, no provenance tokens).  The `identifier`
    field is a fully-qualified path; conventionally
    `<organization>.<lawName>`, e.g. `legalkernel.transfer` for the
    kernel-shipped laws.

## 6. Elaboration semantics

A `law` declaration elaborates to **eight** Lean artefacts:

  1. a `def` of type `Transition` (the §4.4 record);
  2. an `Action` constructor at the declared `action_index`;
  3. a `compileTransition` branch (`Authority/Action.lean`);
  4. an `Action.encode` / `decode` branch pair
     (`Encoding/Action.lean`);
  5. a `fieldsBounded` branch (`Encoding/Action.lean`);
  6. an `extractEvents` branch (`Events/Extract.lean`);
  7. a `non_replaceKey_preserves_registry` branch
     (`Authority/SignedAction.lean`), unless the law is
     `replaceKey`-shaped;
  8. one `instance` per item of the `satisfies` list.

For v1, artefacts (2)–(7) are produced by a code-generation pass
(`lake exe lex_codegen`, §9) that *appends* into the existing
hand-written modules.  This preserves the closed-inductive shape of
`Action` without requiring Lean's macro system to extend an
inductive declaration in another module.  Artefacts (1) and (8) are
produced directly by the macro at the law's declaration site.

The cross-module nature of (2)–(7) is the reason §12's migration
plan is non-trivial.  V2 reorganises the kernel so the generated
file *is* `Authority/Action.lean` and a single source of truth lives
in the law declarations themselves.

### 6.1. The decidable precondition grammar (`Pre`)

The `pre` clause must elaborate to a value of type `State → Prop`
*and* the resulting predicate must satisfy `[DecidablePred pre]` via
`inferInstance`.  The macro emits

```lean
decPre := fun _ => inferInstance
```

verbatim and lets Lean's instance synthesizer fail loudly if the
precondition is not decidable.

To prevent the failure from being a 60-line elaboration trace, Lex
*restricts* the surface grammar to shapes that are guaranteed
instance-discharable.  The grammar is defined inductively:

```text
PreExpr  ::= true | false
           | PreExpr "∧" PreExpr | PreExpr "∨" PreExpr | "¬" PreExpr
           | "if" PreExpr "then" PreExpr "else" PreExpr
           | NatExpr ("≤" | "<" | "=" | "≠" | "≥" | ">") NatExpr
           | ActorExpr  ("=" | "≠") ActorExpr
           | ResourceExpr ("=" | "≠") ResourceExpr
           | "∀" ident "∈" BoundedIter "," PreExpr
           | "∃" ident "∈" BoundedIter "," PreExpr
           | UserPredicate Args                       -- must be tagged @[lex_pre]
NatExpr  ::= literal | ident | NatExpr ("+" | "-" | "*" | "/" | "%") NatExpr
           | "getBalance" Term Term Term
           | "expectsNonce" Term Term
           | UserNatFn Args                            -- must be tagged @[lex_pre]

BoundedIter ::= Term                                  -- Lean term of type List α
                                                      -- (caller's responsibility
                                                      -- that it is finite)
```

Forbidden in `pre`:

  * `∀ x : T, …` and `∃ x : T, …` without an `∈ <list>` bound;
  * `Classical.choose`, `Classical.byContradiction`, or any
    classical-logic primitive;
  * any term whose elaborated type is `Prop` but not
    `Decidable`-friendly (e.g. an opaque user predicate without
    `[Decidable …]`);
  * any expression that touches `IO`, `Task`, `IORef`, etc.;
  * recursive function calls (use bounded iteration over a list
    instead).

The grammar is enforced by a **post-parse pass** in the macro: after
elaborating `pre` to a `Term`, Lex walks the resulting expression
tree and rejects any node not in the grammar.  This produces a
diagnostic at the offending sub-expression's source location, not a
"failed to synthesize Decidable" error inside the generated `def`.

User-defined predicates and Nat-valued functions can be admitted to
the grammar via the `@[lex_pre]` attribute, which the elaborator
consults during the post-parse pass:

```lean
@[lex_pre]
def actor_is_compliant (registry : ComplianceRegistry) (a : ActorId) : Prop :=
  registry.contains a

instance (registry : ComplianceRegistry) (a : ActorId) :
    Decidable (actor_is_compliant registry a) := by
  unfold actor_is_compliant; infer_instance
```

A predicate annotated `@[lex_pre]` may then appear inside a `pre`
clause; absent the annotation, the post-parse pass refuses it with
diagnostic L003.  This makes the trust boundary explicit: every
extension to the precondition grammar is a typed, named addition
that a deployment can audit by `grep '^@\[lex_pre\]'`.

### 6.2. The flow calculus (`impl`)

`impl` is a `do`-block whose every statement is a `State → State`
function.  The macro composes them left-to-right:

```text
impl := do f₁; f₂; …; fₙ        ↦       fun s => fₙ (… (f₂ (f₁ s)))
```

The kernel-allowed mutators (`setBalance`, `KeyRegistry.register`,
`KeyRegistry.revoke`, no-op for `freezeResource`) are exposed as
five primitives:

| Primitive                                       | Desugars to                                                                     |
|-------------------------------------------------|---------------------------------------------------------------------------------|
| `flow r: amt from a to b`                       | post-debit re-read pattern (§4.11 self-transfer fix preserved verbatim)         |
| `mint r: amt to b`                              | `setBalance b r ((getBalance s r b) + amt) s`                                   |
| `burn r: amt from a`                            | `setBalance a r ((getBalance s r a) - amt) s`                                   |
| `reward r: amt to b`                            | identical to `mint` at the kernel level (definitionally equal); separate Action |
| `register_key a as k`                           | updates `es.registry` only; `es.base` and `es.nonces` unchanged                 |
| `revoke_key a`                                  | same module, removal                                                            |
| `freeze_resource r`                             | identity on `es` (semantic marker; freeze invariant is consumed by other laws)  |
| `for x in <list>: <stmt>`                       | `(<list>).foldl (fun s' x => <stmt-as-fn> s') s`                                |
| `if <pre> then <stmt₁> else <stmt₂>`            | `if <pre> then <stmt₁-as-fn> s else <stmt₂-as-fn> s` (decidable branch)         |
| `let x := e`                                    | shadows the local; does **not** advance state                                   |

The `flow` desugaring is fixed to the §4.11 pattern:

```lean
fun s =>
  let bSender   := getBalance s r sender
  let s₁        := setBalance sender r (bSender - amount) s
  let bReceiver := getBalance s₁ r receiver           -- post-debit re-read
  setBalance receiver r (bReceiver + amount) s₁
```

This is the **one** place in the language where a user could choose
to deviate (by writing the raw `setBalance` calls themselves).  Lex
forbids that: a `do` block whose statements are bare `setBalance`
calls is rejected by diagnostic L010.  The reasoning is that the
self-transfer fix is subtle, has bitten the project before, and
should be enforced by macro rather than by review-time alertness.

For laws that need shapes outside the calculus (e.g. a per-resource
fold like `proportionalDilute`'s share computation), the law author
writes a *helper function* outside the `law` block, tags it
`@[lex_impl]`, and calls it from `impl`:

```lean
@[lex_impl]
def proportionalShare (totalReward : Nat) (myStake : Nat) (totalStake : Nat) : Nat :=
  totalReward * myStake / totalStake
```

The `@[lex_impl]` attribute marks the function as part of the
deployment-trusted impl surface.  It carries no theorem obligation
(the obligation lives in the calling law's `satisfies` block); the
attribute exists so tooling can list every term that contributes to
state mutation.

The bare-term escape hatch (`<bare term, must have type State →
State>` in §5.1's grammar) is the v1 escape hatch for laws not
expressible in the calculus.  V2 plans to remove it; see §13.

### 6.3. Authority binding (`signed_by` / `authorized_by`)

`signed_by <actor>` is **mandatory**.  It binds the law's signer
identity for nonce advancement and signature verification.  The
elaborator wires it into the §8.2 `Admissible` predicate as the
`actor = st.signer` constraint and emits a corresponding nonce-
advance call after the `apply_impl` body:

```lean
-- generated, elided from the user's view
def myLaw_apply (st : SignedAction) (es : ExtendedState) (h : Admissible … es st) :
    ExtendedState :=
  { es with
    base     := myLaw_impl …
    nonces   := advanceNonce es.nonces st.signer
    registry := … }
```

`authorized_by <policy-expr>` is **mandatory** for any law that
mutates state observable to a third party (the kernel's `transfer`,
`mint`, `burn`, `reward`, `replaceKey`, `distributeOthers`,
`proportionalDilute`, `dispute`, `disputeWithdraw`, `verdict`,
`rollback` all qualify).  The expression evaluates to a
`Prop`-valued predicate of `(ActorId × Action)` resolved against
the deployment's `AuthorityPolicy` (Phase 3 WU 3.3).

A small number of laws affect only the signer's own state and may
omit `authorized_by` by writing `authorized_by self_only`.  The
elaborator allows this only when the `impl` block's static analysis
shows that every mutated balance / registry slot is keyed by the
signer.  Concretely: every `flow … from sender to …`,
`burn … from sender`, and `register_key sender …` is permitted; a
`flow … from <other>` or `mint … to <other>` while `self_only` is
declared is rejected with diagnostic L011.

A law without **any** `authorized_by` clause (not even `self_only`)
is a parse error.  The repeated forgetfulness around authorisation
in distributed systems is the headline lesson of the last fifteen
years of permissioned-ledger CVEs; Lex makes it impossible to ship a
law without confronting the question.

### 6.4. Property dispatch (`satisfies`)

The `satisfies` block is a list of property claims, each of which
the elaborator must discharge.  Discharge proceeds by matching the
property against a fixed library of *flow-pattern synthesizers*; if
no synthesizer matches, the elaborator emits diagnostic L004 naming
the property and the law.  The user can override by supplying a
`proof <property-name> := by …` clause for that specific property,
in which case the synthesizer is skipped and the user's tactic is
used as the instance body.

The v1 synthesizer library is:

| Property                         | Synthesizer                                              |
|----------------------------------|----------------------------------------------------------|
| `conservative [r]`               | structural induction on the `impl` `do`-block; succeeds  |
|                                  | iff every statement is `flow … r …`, `freeze_resource`,  |
|                                  | `register_key`, `revoke_key`, or `for x in …` whose body |
|                                  | discharges; **fails** on any `mint`, `burn`, `reward`,   |
|                                  | or `flow` on a different resource at the same `r`.       |
| `conservative [{r₁, …, rₙ}]`     | conjunction of `conservative [rᵢ]` for each `rᵢ`         |
| `conservative [*]`               | matches conservatives whose `impl` does not touch any    |
|                                  | balance (e.g. `replaceKey`, `freezeResource`, `dispute`) |
| `monotonic [r]`                  | structural induction; succeeds on `flow … r …`,          |
|                                  | `mint r …`, `reward r …`, `register_key`, `revoke_key`,  |
|                                  | `freeze_resource`; **fails** on `burn r …`.              |
| `monotonic [*]`                  | conjunction over every resource the `impl` touches plus  |
|                                  | a no-op witness for resources untouched.                 |
| `local [{r₁, …, rₙ}]`            | static analysis of `impl` computes the set of touched    |
|                                  | resources; succeeds iff it is a subset of `{r₁, …, rₙ}`. |
| `local []`                       | the `impl` touches no resource (registry-only laws).     |
| `freeze_preserving [r]`          | reduces to: every balance-touching statement is on a     |
|                                  | resource ≠ r OR the law's precondition forbids it.       |
| `freeze_preserving [*]`          | conjunction of all per-resource freeze-preservation.     |
| `nonce_advances [a]`             | derived: holds iff `signed_by a` is the law's binding.   |
| `registry_preserving`            | succeeds iff `impl` contains no `register_key` /         |
|                                  | `revoke_key` statement.                                  |
| user-defined property `P`        | requires `proof P := by …` clause.                       |

Each synthesizer emits a Lean `instance` declaration whose body is
either a direct call to a known kernel theorem (e.g. for
`conservative [r]` on a single-flow `impl`, the body is
`exact transfer_conserves r sender receiver amount`) or a small
tactic block constructing the witness from the kernel-shipped
lemmas (`getBalance_setBalance_other`, `transfer_does_not_touch_other_resources`,
etc.).

The synthesizers are **deliberately conservative**.  A law shaped
as `flow r₁: a₁ from x to y; flow r₁: a₂ from y to x` (a round
trip) is *informally* conservative but the structural-induction
synthesizer will not detect that.  A user who wants to claim
conservation in such a case provides a `proof conservative [r₁] := by …`
override.  The point of the conservative synthesizer is not to be
clever — it is to be *predictable* so reviewers can trust automatic
discharge without reading the proof.

User-defined properties are admissible:

```
satisfies := [
  conservative [r],
  KYC_compliant
]

proof KYC_compliant := by
  unfold KYC_compliant
  -- arbitrary Lean tactic block; the elaborator splices it in
  exact ⟨…⟩
```

The user-defined property must be a `Prop`-valued predicate over the
generated `def` (the `Transition` value).  Concretely:

```lean
def KYC_compliant (t : Transition) : Prop := …
```

User-defined properties are **not** required to be decidable.  They
do not enter the executable path; they are obligations the
deployment chooses to prove for governance reasons.

### 6.5. Action registration (`action_index`)

Every `law` declaration commits to an `action_index : N`.  The
elaborator enforces three rules:

  1. **Reserved range.**  Indices 0..11 are reserved for the
     kernel-built-in laws (the current 12 constructors of `Action`).
     A new law with `action_index < 12` is rejected with diagnostic
     L006.
  2. **Per-deployment uniqueness.**  Within a deployment manifest's
     law set, no two laws may share an `action_index`.  Collision
     produces diagnostic L005.
  3. **Immutability across versions.**  Once a law has been included
     in a tagged release of the deployment, its `action_index` is
     committed forever.  An attempt to renumber it produces
     diagnostic L007 (which is escalated to a build failure if the
     release is signed).

The mechanism for enforcing immutability across versions is a
checked-in registry file `lex_index_registry.txt`, structured as

```text
# format: <identifier>  <action_index>  <first_release>
legalkernel.transfer            0   v0.1.0
legalkernel.mint                1   v0.1.0
…
legalkernel.rollback           11   v0.6.0
my_deployment.staking_lock     12   v1.0.0
```

`lake exe lex_codegen` reads this file before emitting code; if a
`law` declaration's `action_index` disagrees with the registry, the
build fails.  Adding a new law adds a registry entry in the same
PR; removing a law removes the entry but leaves the index reserved
forever (a tombstone) so historical replay is unaffected.

The closed-inductive shape of `Action` is preserved: the elaborator
accumulates all `law` declarations in the build, sorts them by
`action_index`, and emits a single `Authority/Action.lean` file (in
v2 — see §13) or a diff against the existing one (in v1).  The
constructor names are `Action.<lawName>` per the registry, so wire
compatibility hinges on the index, not the surface name.

For laws whose `impl` mutates the registry (currently only
`replaceKey`), the elaborator omits the auto-generated
`non_replaceKey_preserves_registry` branch and instead emits
explicit `replaceKey_*_registry` theorems modelled on the existing
WU 3.10 set.  V1 hand-codes these for `replaceKey` and refuses any
other registry-mutating law (diagnostic L012); v3 plans to admit
arbitrary registry-mutating laws once the dispatch over registry
effects is generalised (§13).

### 6.6. Event emission (`events`)

The `events` block is a `do`-style sequence of `emit <constructor>
<args>…` statements that elaborate to a branch of `actionEvents` in
`LegalKernel/Events/Extract.lean`.  The elaborator threads the pre-
and post-state through implicitly:

```text
events := do
  emit BalanceChanged r sender   newBalSender   oldBalSender
  emit BalanceChanged r receiver newBalReceiver oldBalReceiver
```

elaborates to (roughly)

```lean
fun (preState postState : ExtendedState) =>
  let oldBalSender   := getBalance preState  r sender
  let newBalSender   := getBalance postState r sender
  let oldBalReceiver := getBalance preState  r receiver
  let newBalReceiver := getBalance postState r receiver
  [Event.balanceChanged r sender   newBalSender   oldBalSender,
   Event.balanceChanged r receiver newBalReceiver oldBalReceiver]
```

Lex's event block enforces three invariants:

  1. **Pre / post-state availability.**  The block can refer to both
     `preState` and `postState` via the `getBalance s r a` shape.
     Implicit `s` defaults to `preState` for parsing convenience but
     is rebindable.
  2. **Determinism.**  All event-emission expressions must be free
     of `IO` and `Task`.  This is statically checked.
  3. **Event-impl alignment (warning level).**  The elaborator
     computes the set of `(resource, actor)` cells the `impl`
     touches and warns (diagnostic L013) if the `events` block
     either omits an event for a touched cell or emits one for an
     untouched cell.  The warning is *not* an error in v1 because
     the `extractEvents` machinery already filters zero-deltas
     (§5.6 of `Events/Extract.lean`); a follow-up release may
     promote the warning to an error.

Events implicit from the authority layer are auto-emitted:
`Event.nonceAdvanced signer newNonce` is always emitted at the end
of the generated branch (since `signed_by` is mandatory).
`Event.identityRegistered` / `Event.identityRevoked` are auto-emitted
when the `impl` contains `register_key` / `revoke_key`.  A user
`emit` of these is allowed but produces a warning (L014) recommending
the auto-emission.

### 6.7. Resource roles (deferred to v3)

In a deployment with mixed resource types (e.g. currency vs voting
power vs allowance quota), it is desirable to enforce at parse time
that a payment law cannot be invoked with a voting-power resource.

The mechanism — *resource roles* — is a phantom-typed wrapper around
`ResourceId`:

```lean
structure Roled (ρ : Role) where
  raw : ResourceId

inductive Role where
  | currency
  | votingPower
  | allowance
  | custom (id : ByteArray)
```

A law parameterised on `(r : Roled .currency)` accepts only resources
the deployment tagged as currency.  At the kernel level, `Roled` is
a wrapper that erases to `ResourceId`; the role is purely a
parse-time / typecheck-time concern.

V1 defers this.  The current 12 kernel-built-in laws are all
`(r : ResourceId)`-shaped; introducing roles requires either a
breaking change to those signatures (rejected: too disruptive) or a
new layer of wrapper laws (acceptable, but not a v1 priority).
V3 will revisit once a deployment surfaces the mixed-role need
concretely.

The `intent` block of every v1 law should already document the
expected role of each resource parameter; this preserves the
human-language signal pending machine enforcement.

## 7. Deployment manifests

A **deployment manifest** is the second top-level Lex command.  It
binds a law set, an authority configuration, a deployment ID, a
list of invariant claims, and (in v2) an attestor key.  Manifests
are the auditor's entry point: they fit on one screen and name every
moving part the deployment depends on.

### 7.1. Manifest grammar

```ebnf
deployment ::= "deployment" ident "where" deployment_clause+

deployment_clause
   ::= "identifier"      ident_path
     | "deployment_id"   bytes_lit                      -- 32 bytes; flows into signInput
     | "version"         string_lit
     | "resources"       ":=" resource_list
     | "laws"            ":=" law_binding_list
     | "authority"       ":=" authority_binding_list
     | "invariant_claims" ":=" claim_list
     | "attestor"        ident                          -- v2: attestor key handle

resource_list
   ::= "[" (resource_decl ("," resource_decl)*)? "]"
resource_decl ::= ident "=" nat_lit ("as" Role)?

law_binding_list
   ::= "[" (law_binding ("," law_binding)*)? "]"
law_binding   ::= ident "=" ident_path "@" version_lit

authority_binding_list
   ::= "[" (authority_binding ("," authority_binding)*)? "]"
authority_binding ::= ident "=" policy_expr

claim_list
   ::= "[" (claim ("," claim)*)? "]"
claim ::= "monotonic_law_set"      "[" ident ("," ident)* "]"
        | "conservative_law_set"   "[" ident ("," ident)* "]"
        | "freeze_preserving_law_set"  "[" ident ("," ident)* "]"
        | ident                                          -- user-defined claim
```

### 7.2. Worked example: a USD-clearing manifest

```
deployment usd_clearing where
  identifier      example.usd_clearing
  deployment_id   0xDEADBEEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567
  version         "1.0.0"

  resources := [
    USD = 0  -- as currency  (role wrappers are v3)
  ]

  laws := [
    Transfer    = legalkernel.transfer    @ "1.0.0",
    Mint        = legalkernel.mint        @ "1.0.0",
    Freeze      = legalkernel.freeze      @ "1.0.0",
    ReplaceKey  = legalkernel.replaceKey  @ "1.0.0"
    -- explicitly absent:
    --   * legalkernel.burn (deflation forbidden)
    --   * legalkernel.reward (positive incentives forbidden)
    --   * legalkernel.proportionalDilute (no equity-style dilution)
  ]

  authority := [
    transfer_policy  = federation.transfer_policy_v2,
    mint_policy      = central_bank_only,
    identity_policy  = self_only_with_central_bank_recovery
  ]

  invariant_claims := [
    monotonic_law_set [Transfer, Mint, Freeze, ReplaceKey]
    -- conservative_law_set is *not* claimed: Mint is not IsConservative.
    -- Adding it here would fail elaboration with diagnostic L008.
  ]
```

### 7.3. Elaboration semantics

A `deployment` declaration elaborates to:

  1. a `def deployment_<name> : Deployment` (a record bundling all
     the manifest fields);
  2. one `instance` per `invariant_claims` item, synthesising
     `MonotonicLawSet` / `ConservativeLawSet` / etc. values;
  3. a `theorem deployment_<name>_manifest_hash : ByteArray :=
     <CBE-hash of the manifest source bytes>` that the
     attestor signs in v2.

The most important elaboration step is the invariant-claim
synthesis.  For `monotonic_law_set [L₁, …, Lₙ]`, the elaborator
emits

```lean
def deployment_<name>_monotonic_law_set : MonotonicLawSet :=
  { laws := [L₁, …, Lₙ]
  , monotonicity := by
      intro l hl
      simp [List.mem_cons] at hl
      rcases hl with ⟨…⟩
      all_goals (first | exact L₁_isMonotonic | … | exact Lₙ_isMonotonic) }
```

If any `Lᵢ` lacks the `IsMonotonic` instance, synthesis fails with
diagnostic L008 naming the offending law.  This is the type-level
firewall (§2 of `docs/economic_invariants.md`) made *deployment-time*
rather than per-PR-checklist.

### 7.4. Cross-deployment-replay protection

The `deployment_id` field is a 32-byte unique identifier that flows
into Audit-3.3/3.4's `signingInput` parameterisation:

```lean
def signingInput
    (a : Action) (signer : ActorId) (n : Nonce)
    (deploymentId : ByteArray) : ByteArray := …
```

A signature produced for `deployment_id = 0xDEAD…` will not verify
against any other deployment's `Verify` invocation because the
deployment-ID bytes are part of the message under signature.

The manifest elaborator is responsible for ensuring the
`deployment_id` is propagated wherever `Admissible` is reached:

  * `processSignedAction` reads the deployment's `deployment_id` and
    passes it to `signingInput`;
  * the runtime adaptor (Phase 5) is configured per-deployment with
    a single `deployment_id` value.

V1 ships the manifest's `deployment_id` field as a literal
`ByteArray`; v2 may ship a "deployment-ID derivation" sub-language
(SHA-256 of (organisation || version || nonce)) for deployments
that prefer derived IDs.

### 7.5. Manifest signing

In v1, the manifest is a Lean source file checked into the
deployment's repository.  Its identity is the source bytes; review
is by ordinary code review.

In v2, the manifest's CBE-hash is signed by an **attestor key**
(reusing the Audit-3.2 `AttestedSnapshot` machinery
`LegalKernel/Runtime/AttestedSnapshot.lean`).  The runtime checks
the attestation before bootstrapping; an unsigned or
incorrectly-signed manifest is refused.  This gives counterparties
a cryptographic anchor: they can verify that the operator runs the
manifest the attestor signed.

The `intent` blocks of every law in the manifest's law set are
*included in the bytes the attestor signs*.  Editing the prose
without re-attesting is detectable.

## 8. Governance and amendment

Amendments are the hardest part of any law-as-code system.  Lex
codifies five rules:

### 8.1. The five amendment rules

  1. **Action indices are immutable forever.**  Once a law has
     appeared in any tagged release of the deployment, its
     `action_index` is committed to the wire format.  Renumbering
     is rejected by `lake exe lex_lint` (diagnostic L007).  Removed
     laws leave their indices reserved as tombstones.

  2. **Versions follow semver, mechanically checked.**

     * **Patch** (`1.0.0 → 1.0.1`) — proof refactors only.  No
       change to `pre`, `impl`, `signed_by`, `authorized_by`,
       `satisfies`, `events`, or `intent`.  The `lex_diff` tool
       verifies this.
     * **Minor** (`1.0.1 → 1.1.0`) — refining changes.  The new
       `pre` must imply the old `pre` (the new behaviour is more
       restrictive); the new `impl` must agree with the old on the
       intersection of preconditions.  Refinement is a proof
       obligation discharged in a `proof refinement_v1.0.x := by …`
       clause that elaborates to a theorem of type
       `∀ s, oldPre s → newPre s ∧ (oldPre s → newImpl s = oldImpl s)`.
     * **Major** (`1.1.0 → 2.0.0`) — breaking changes.  Requires
       coordinated migration: deployments must opt in by bumping
       their manifest's law binding to the new version.  Old logs
       can still replay (the old version's `Action` constructor is
       preserved as a tombstone, separately registered at a
       different index).

  3. **`intent` covered by signature.**  The `intent` block is part
     of the manifest's signed bytes.  Editing it without bumping at
     least the patch version produces diagnostic L015 and is
     rejected by `lex_lint`.

  4. **`satisfies` weakening is breaking.**  Removing a property
     from `satisfies` is a major version bump (downstream consumers
     may be relying on it).  Adding a property is a minor version
     bump if synthesis succeeds, or a major bump if the new
     property requires an `impl` change.

  5. **Two-reviewer gate on TCB-touching changes.**  A change to a
     law whose generated artefacts include a TCB module
     (`Kernel.lean`, `RBMapLemmas.lean`) — currently impossible
     under the §6 design but enforced as a forward-protection rule
     — requires two reviewers per CLAUDE.md.

### 8.2. Amendment workflow

A typical amendment to `legalkernel.transfer` proceeds:

  1. Author edits the `law transfer` declaration.
  2. `lake exe lex_lint` runs, producing either a clean diff or
     diagnostics L001–L015.
  3. `lake exe lex_diff <old-sha> <new-sha>` produces a semantic
     diff:
     ```
     legalkernel.transfer:
       version: 1.0.0 → 1.1.0   (minor)
       pre:                     (refinement)
         + amount ≤ 2^32        (new bound)
       impl: unchanged
       satisfies: unchanged
       events: unchanged
       intent: unchanged
     ```
  4. The author supplies the refinement proof as `proof
     refinement_v1.0.x := …` in the new version.
  5. PR review proceeds with the semantic diff as the primary
     artefact, not the textual diff.
  6. On merge, the manifest of every consuming deployment must be
     re-attested (v2).

### 8.3. Sunset of laws

Removing a law from a deployment requires:

  1. The deployment's manifest is amended to omit the law from its
     `laws` block.
  2. The law's `Action` constructor remains in the kernel forever
     (tombstone) so historical logs can replay.
  3. New `SignedAction`s carrying the removed law's constructor are
     rejected at admissibility time (the deployment no longer
     authorises it).

This preserves the "no rewriting history" principle: replay of any
log written under any version of any manifest produces the same
state, even if the laws referenced have since been retired.

## 9. Tooling

Lex ships with a small CLI surface, modelled on the existing
`count_sorries` / `tcb_audit` / `stub_audit` tooling and added to
`lakefile.lean` as audit binaries.

### 9.1. `lake exe lex_lint`

The headline gate.  Walks every `.lean` file under
`LegalKernel/Laws/` and `Deployments/` (v2), parses the `law` and
`deployment` declarations, and checks:

  * mandatory clauses are present (`signed_by`, `authorized_by`,
    `satisfies`, `intent`, `action_index`);
  * `pre` expressions fit the §6.1 grammar;
  * `impl` blocks fit the §6.2 calculus;
  * `action_index` uniqueness and registry consistency
    (`lex_index_registry.txt`);
  * `satisfies` synthesizers terminate;
  * `intent` blocks are non-empty.

Exit non-zero on any failure with a precise location.  Run by CI
on every PR, modelled on the `lake exe count_sorries` pattern.

### 9.2. `lake exe lex_codegen`

The code-generation pass.  Reads every `law` declaration, emits the
seven supporting artefacts (constructors, encoding cases, event
cases, instance declarations) into the appropriate kernel modules,
and writes the result.

V1 mode: **append-only**.  Existing hand-written constructors are
preserved; new laws append.  The kernel-built-in laws are *not* yet
re-expressed in Lex form, so `lex_codegen` is purely additive.

V2 mode: **canonical regeneration**.  The kernel-built-in laws are
re-expressed in Lex; `lex_codegen` regenerates `Authority/Action.lean`
in full.  At this point, manual edits to that module are rejected
by CI.

### 9.3. `lake exe lex_diff <ref-a> <ref-b>`

Semantic diff of two repository revisions.  Outputs per-law and
per-deployment changes in a format intended for PR descriptions:

```
legalkernel.transfer:
  version: 1.0.0 → 1.1.0   (minor — refinement)
  pre:                     diff:
    @@ -1,2 +1,3 @@
       amount > 0
       ∧ getBalance s r sender ≥ amount
    +  ∧ amount ≤ 2^32
  impl: unchanged
  satisfies: unchanged
  events: unchanged
  intent: unchanged
```

The diff is computed on the *parsed* AST, not the source bytes,
so reformatting and comment changes do not appear.

### 9.4. `lake exe lex_format`

Pretty-printer.  Rewrites a `.lean` file containing `law` /
`deployment` declarations into the canonical form (clause order,
indentation, blank-line conventions).  Idempotent.  Run by `pre-
commit` hooks if a deployment elects.

### 9.5. LSP integration (deferred to v3)

A Lean LSP extension that surfaces:

  * surface-error red squiggles (with diagnostic codes);
  * hover tooltips showing the discharged `satisfies` instances;
  * "go-to-impl-of-flow" navigation;
  * `intent`-block markdown rendering.

Deferred because it requires extending Lean's LSP server, a
non-trivial standalone PR that is best landed once the v1 macro
syntax is stable.

### 9.6. Property-test harness (auto-generation)

The Audit-3.9 in-tree property harness
(`LegalKernel/Test/Property.lean`) can auto-generate property tests
from `satisfies` claims:

  * `conservative [r]` ⇒ a property test that draws random
    `(state, sender, receiver, amount)` triples, applies the law,
    and asserts `totalSupply post r = totalSupply pre r`.
  * `monotonic [r]` ⇒ the same shape with `≥` instead of `=`.
  * `local [{r}]` ⇒ a test that asserts every resource ≠ r is
    pointwise-unchanged.

`lake exe lex_codegen` emits an auto-generated test file
(`LegalKernel/Test/Properties/AutoGen.lean`) with one harness call
per `(law, property)` pair.  The CI gate runs them at a default
sample count of 100 (overrideable via `CANON_PROPERTY_ITERATIONS`).

## 10. Diagnostics

Lex emits structured diagnostics with stable, numbered codes so CI
can pin specific failure modes and so deployment authors can search
documentation by code.

### 10.1. Diagnostic catalogue

| Code  | Meaning                                                      | Severity | Remediation                                                                       |
|-------|--------------------------------------------------------------|----------|-----------------------------------------------------------------------------------|
| L001  | Missing `signed_by` clause                                   | error    | Add `signed_by <actor>` naming the actor whose nonce should advance.              |
| L002  | Missing `satisfies` clause                                   | error    | Add `satisfies := […]` listing at least the properties relevant to your law.      |
| L003  | Precondition contains undecidable subexpression `<expr>`     | error    | Replace `<expr>` with a §6.1-grammar shape, or tag the helper `@[lex_pre]`.       |
| L004  | Property `<P>` not synthesizable for law `<L>`               | error    | Either weaken `satisfies` or supply `proof <P> := by …` with a manual witness.    |
| L005  | Action index `<N>` already used by law `<L>`                 | error    | Allocate a fresh index ≥ 12 and update `lex_index_registry.txt`.                  |
| L006  | Action index `<N>` reserved (kernel-built-in range 0..11)    | error    | Allocate `<N> ≥ 12`.                                                              |
| L007  | Action index renumbered from `<old>` to `<new>` for `<L>`    | error    | Restore the original index; renumbering is forbidden.                             |
| L008  | Manifest invariant claim `<C>` not satisfiable               | error    | Either drop the claim or add the missing law's instance.                          |
| L009  | Missing `authorized_by` clause                               | error    | Add `authorized_by <policy>` or, if appropriate, `authorized_by self_only`.       |
| L010  | Bare `setBalance` call in `impl`                             | error    | Use `flow` / `mint` / `burn` / `reward` primitives.                               |
| L011  | `self_only` declared but `impl` mutates non-signer state     | error    | Add an `authorized_by` policy or restrict `impl` to signer-keyed mutations.       |
| L012  | Registry-mutating law other than `replaceKey` (v1)           | error    | Defer to v3, or hand-write the registry-effect theorems and disable lex_codegen.  |
| L013  | `events` block omits or duplicates a balance change          | warning  | Align `events` with the cells `impl` touches, or accept the auto-filter.          |
| L014  | Manual emission of an auto-emitted event                     | warning  | Remove the manual `emit`; the elaborator will add the canonical form.             |
| L015  | `intent` block edited without version bump                   | error    | Bump at least the patch version when editing `intent`.                            |
| L016  | Refinement proof missing for minor version bump              | error    | Supply `proof refinement_v<old> := by …`.                                         |
| L017  | Major version bump without action-index reservation          | error    | Allocate a new tombstone index or use a major-bump mechanism documented in §8.    |
| L018  | Manifest `deployment_id` not 32 bytes                        | error    | Pad to exactly 32 bytes; deployment IDs are fixed-width.                          |
| L019  | `for x in <iter>:` body's iter is not statically a `List α`  | error    | Convert via `.toList` or use a different bounded iterator.                        |
| L020  | Unknown property `<P>` referenced in `satisfies`             | error    | Tag a `def <P>` with `@[lex_property]` and provide a `proof <P> := …` clause.     |

### 10.2. Diagnostic format

Each diagnostic prints in a consistent format:

```text
<file>:<line>:<col>: error: L004: Property `conservative [r]` not synthesizable for law `myLaw`
  --> note: structural induction on `impl` failed; offending statement is
  --> note:   mint r: amount to receiver
  --> note: at <file>:<line>:<col>.
  --> hint: `mint` is non-conservative by design.  Consider:
  --> hint:   - dropping `conservative [r]` from `satisfies`;
  --> hint:   - replacing `mint` with `flow`;
  --> hint:   - supplying `proof conservative [r] := by …` with a manual witness.
```

The file/line/col is anchored at the *surface syntax* (the user's
`law` declaration), not at the macro-expanded Lean term.  This is
the diagnostic-translation layer §3 referenced; it works by walking
the macro-expansion tree, finding the nearest source-mapped node,
and re-emitting the diagnostic at that location.

### 10.3. CI gates

The Lex CI gate set extends the existing kernel gates:

```bash
lake build                # existing
lake test                 # existing
lake exe count_sorries    # WU 1.12 — kernel-TCB sorry count
lake exe tcb_audit        # WU 1.11 — TCB import allowlist
lake exe stub_audit       # Audit-3.8 — stub-detection
lake exe lex_lint         # NEW — Lex parse, grammar, registry, claims
lake exe lex_codegen --check  # NEW — generated artefacts up to date
```

`--check` mode runs `lex_codegen` and fails if its output differs
from what is checked in.  This is the equivalent of
`gofmt -d -check`: regeneration is mechanical, but the generated
files are committed so that reviewers can diff them directly.

## 11. Deliberate exclusions

The following are *deliberately* not in Lex.  Each was considered
and rejected for a specific reason; this section is the project's
record of those rejections so they are not relitigated in
unstructured GitHub comments.

  * **I/O.**  Laws are pure state functions.  Reading from external
    sources is the runtime adaptor's responsibility (Phase 5);
    laws receive `(preState, action)` and produce `postState`.
    Allowing `IO` would break determinism, reproducibility, and the
    replay-for-audit property.

  * **Wall-clock time.**  Time enters the kernel only as data via
    signed `timeRecorded` events.  A law that wants to compare
    against "now" reads from a designated time-bearing actor's
    state.  This makes time auditable and replayable.

  * **Randomness.**  Cryptographic operations are part of the trust-
    assumption stack (the `Verify` opaque, Phase 5's `Runtime.Hash`),
    not the law surface.  Randomness in laws would either be fake
    (PRNG seeded by state — useless) or non-deterministic
    (forbidden).

  * **Exceptions.**  Lex preconditions and `Result`-typed checks
    cover what exceptions would.  Exception flow control is hard to
    reason about under refinement and would obscure the
    Genesis-Plan §4.5 `step_impl` semantics.

  * **Mutation outside the kernel-allowed set.**  `setBalance` is
    the only balance mutator; `KeyRegistry.register` / `revoke` are
    the only registry mutators; `advanceNonce` is auto-emitted.
    Lex's calculus exposes wrappers; the bare primitives are not
    callable from `impl` (§6.2 diagnostic L010).

  * **Reflection / introspection of kernel state.**  Lex laws cannot
    enumerate `BalanceMap.toList` of the entire `State`.  They can
    bound-iterate a deployment-specific actor list provided as a
    parameter.  This preserves the per-action-cost discipline (the
    runtime can bound the work per action).

  * **Turing-completeness in `pre`.**  `pre` is a decidable
    predicate built from a closed grammar.  Recursion is forbidden.
    Bounded iteration over a known-finite list is allowed.  This
    keeps `decide`-driven evaluation tractable and rules out
    decidability-undermining shapes.

  * **Floating-point.**  All amounts are `Nat`.  Floating-point's
    well-known associativity and rounding pathologies make refinement
    proofs unreasonable.

  * **Strings beyond bare necessities.**  CBE encodes strings as
    bounded byte arrays; the kernel does not depend on Unicode
    semantics.  Strings appear only in user-facing fields like
    `intent` (which is text but not interpreted at runtime).

  * **Ambient `Classical.choice`.**  Already forbidden in `pre` by
    §6.1.  Lex laws may use `Classical.choice` in their *proofs*
    (the kernel admits the three Lean built-in axioms), but never
    in executable `apply_impl` paths.

## 12. Migration plan

The Lex v1 implementation lands in three checkpoints.  Each is a
separable PR with its own CI gate.

### 12.1. Checkpoint M1: macro skeleton + v1-additive `lex_codegen`

  * Add `LegalKernel/DSL/LexLaw.lean` exposing the new `law` macro
    (alongside the existing Phase-4 macro, which keeps working).
  * Add `LegalKernel/DSL/LexProperty.lean` with the synthesizer
    library (§6.4).
  * Add `Tools/LexLint.lean` and `Tools/LexCodegen.lean` (audit
    binaries with the same shape as `Tools/CountSorries.lean`).
  * Add `lex_index_registry.txt` initialised with the 12 existing
    constructors.
  * No existing law is touched; the new macro runs in parallel with
    the old.
  * CI adds `lake exe lex_lint` (no-op until a Lex law is added).

Acceptance: a stub `legalkernel.example_lex_only_law` declared in
`LegalKernel/Laws/ExampleLex.lean` elaborates cleanly, generates
the seven artefacts, passes `lex_lint`, and `lake test` passes.

### 12.2. Checkpoint M2: re-express the 12 kernel-built-ins in Lex

  * Migrate `transfer`, `mint`, `burn`, `freezeResource`,
    `replaceKey`, `reward`, `distributeOthers`, `proportionalDilute`,
    `dispute`, `disputeWithdraw`, `verdict`, `rollback` to Lex
    declarations.
  * `lex_codegen` flips to **canonical regeneration** mode for the
    files it now owns:
    * `Authority/Action.lean` (constructors + `compileTransition`);
    * `Encoding/Action.lean` (encode / decode / fieldsBounded);
    * `Events/Extract.lean` (event branches);
    * `Authority/SignedAction.lean`'s
      `non_replaceKey_preserves_registry`.
  * The hand-written instance proofs (`transfer_isConservative`
    etc.) are replaced by synthesizer-generated equivalents; the
    *theorem statements* and their use sites are unchanged so the
    rest of the kernel sees no API drift.
  * The Phase-4 `Law.mk` macro and its `transferDSL` example are
    deprecated (kept compiling for one minor version, then removed).

Acceptance: every existing test passes byte-for-byte; the test
count is unchanged; `#print axioms` on every kernel theorem still
returns `[propext, Classical.choice, Quot.sound]`; the diff is
removal of hand-written cases plus addition of the Lex declarations
plus regenerated artefact files.

### 12.3. Checkpoint M3: deployment manifests + governance tooling

  * Add `LegalKernel/DSL/LexDeployment.lean` with the `deployment`
    macro.
  * Add `Tools/LexDiff.lean` (semantic diff) and `Tools/LexFormat.lean`
    (pretty-printer).
  * Wire `lex_lint` to validate `deployment_id` length, registry
    consistency, claim synthesis.
  * Add a worked-example deployment under `Deployments/Examples/`
    (USD-clearing-style, illustrative only).
  * Document the amendment workflow (§8) with a checked-in
    walkthrough of bumping `legalkernel.transfer` from `1.0.0` to
    `1.1.0` (refinement adding an upper bound on `amount`).

Acceptance: the example deployment elaborates, attestations are
valid, the worked-example minor-bump exercises the refinement-proof
mechanism end-to-end.

### 12.4. Risk and rollback

The high-risk step is M2: it *replaces* the hand-written
`Authority/Action.lean` etc. with generated versions.  If the
synthesizer is buggy, the kernel could silently lose an
`IsConservative` instance, breaking downstream refinement proofs.
Mitigations:

  1. M2 lands behind a `lex_codegen --check` CI gate that rejects
     any divergence between hand-written and generated forms during
     the migration window.
  2. The migration proceeds law-by-law (one Lex declaration per
     PR), so any regression is bisectable.
  3. The post-M2 commit retains the pre-M2 hand-written files in
     `legacy/Authority_Action_pre_lex.lean` for a release window;
     the rollback is `git revert`.

If a serious problem is discovered post-M2, the rollback path is to
revert the M2 PR and continue maintaining hand-written code.  M1
and M3 are independent and remain useful even without M2.

## 13. Roadmap

### 13.1. v1 (this document)

  * `law` macro extended with mandatory `signed_by`,
    `authorized_by`, `satisfies`, `intent`, `action_index`.
  * `flow` / `mint` / `burn` / `reward` / `register_key` /
    `revoke_key` / `freeze_resource` primitives in `impl`.
  * Property synthesizer library covering `conservative`,
    `monotonic`, `local`, `freeze_preserving`, `nonce_advances`,
    `registry_preserving`.
  * `deployment` manifest macro with `invariant_claims`.
  * `lex_lint`, `lex_codegen` (additive mode), `lex_diff`,
    `lex_format` audit binaries.
  * Migration plan M1 + M2 + M3 (§12).
  * Diagnostics L001–L020 with stable codes.

### 13.2. v2

  * Manifest signing via attestor key (Audit-3.2 reuse).
  * `lex_codegen` canonical-regeneration mode.
  * Removal of the bare `<term : State → State>` escape hatch in
    `impl` (§5.1) — every law expressible in the calculus.
  * Cross-deployment-replay protection at the manifest level
    (deployment-ID derivation sub-language).
  * LSP integration (basic — error squiggles, instance hovers).
  * Auto-generated property test harness (§9.6) wired by default.

### 13.3. v3

  * Resource roles (§6.7).  Phantom-typed `Roled ρ` wrappers; per-
    deployment role table.
  * Deployment-private laws (Action-extension via per-deployment
    Action types; runtime-adaptor dispatch).
  * Admission of arbitrary registry-mutating laws beyond `replaceKey`.
  * LSP integration (advanced — `intent`-block markdown rendering,
    "go-to-impl-of-flow" navigation).
  * Custom dispute-claim variants declared in Lex (Genesis-Plan
    §8.4 amendment, requires kernel review).

### 13.4. Beyond v3

Speculative; not committed:

  * Cross-language client-side library that consumes the manifest
    bytes and produces code in a host language (Rust, Python,
    TypeScript).  This is the "external implementer" of
    `docs/abi.md` §1, lifted to the law level.
  * Incremental property re-discharge: when a law's `impl` changes,
    re-run only the affected synthesizers.
  * Property-rich CHIP-style proposals: a deployment proposes an
    amendment; tooling generates the semantic diff, the proof
    obligations, and the migration path automatically.

## 14. Open questions

The design above is concrete and shippable, but several questions
remain genuinely unresolved.  Listing them here keeps the document
honest.

  1. **Refinement of `pre` across versions.**  §8.1 says a minor
     bump's new `pre` must imply the old `pre` (the new behaviour is
     more restrictive).  Is this right?  Some refinements *weaken*
     `pre` (the law accepts more inputs); the implementation
     constraint then is that the *behaviour* on the old domain is
     unchanged.  V1 may need both directions.  Open: which
     direction is the *default*, and how does the macro syntax
     distinguish them?

  2. **In-flight signed actions across amendments.**  A signed
     action admissible at law version 1.0.0 may not be admissible
     at version 1.1.0 if `pre` strengthens.  The deployment must
     either reject in-flight actions on amendment (operational pain)
     or queue them for replay against the new version (correctness
     hazard).  Open: does Lex specify a default policy?

  3. **Cross-law invariant synthesis.**  Many invariants are
     statements about *the law set*, not individual laws (e.g. "no
     two laws can grant the same actor minting authority").  These
     belong in the manifest's `invariant_claims` block, but the
     synthesizer library is empty for them in v1.  Open: what is
     the v2 vocabulary for cross-law claims?

  4. **Compositional property dispatch.**  A law whose `impl` is a
     sequence of `flow`s on different resources should be able to
     claim `conservative [r₁, r₂]` if each flow is on its own `rᵢ`.
     V1's structural-induction synthesizer handles this; but it
     does *not* handle laws whose `impl` is `for x in <list>: flow
     …`.  Open: how does the synthesizer reason about
     fold-of-flow?  (The current `Laws/DistributeOthers.lean` has
     this proof structure; v1 falls back to the user supplying
     `proof conservative [r] := by …`.)

  5. **Property-test seed reproducibility across hosts.**
     Audit-3.9's harness is deterministic given a seed; auto-
     generated tests should record the seed in the test output so
     CI failures are reproducible locally.  Open: where does the
     seed live — env var, embedded literal, or a separate seeds
     file?

  6. **Deployment-ID derivation.**  V2's planned derivation sub-
     language is unspecified.  Should the deployment ID be `SHA-256
     (organisation || version || nonce)`?  `BLAKE3 (manifest source
     bytes)`?  A user-selected scheme?  Open: what is the canonical
     form, and how does it interact with manifest signing?

  7. **Role types vs role values.**  §6.7 sketches phantom-typed
     `Roled ρ`.  An alternative is a runtime predicate `HasRole r ρ`
     decided against a deployment table, with no type-level
     wrapping.  The runtime form integrates more cleanly with the
     existing `(r : ResourceId)` signatures; the phantom form
     catches errors at parse time.  Open: which approach is the v3
     default?

  8. **`pre`-grammar extensibility through `@[lex_pre]`.**  The
     `@[lex_pre]` attribute makes the trust boundary explicit, but
     a malicious deployment could tag a non-decidable predicate
     with `@[lex_pre]` and rely on instance synthesis to fail
     opaquely.  Open: should `@[lex_pre]` require a `Decidable`
     instance to be present at the *attribute* level (rejected if
     the instance fails to synthesize for any input)?

These questions do not block v1.  They are open in the sense of
"resolve before committing to v2" — none of them require breaking
the v1 surface.

## 15. Worked examples

This section sketches additional laws beyond §5.2–5.4 to exercise
the language.  These are illustrative; they correspond to existing
kernel modules and are intended to demonstrate that Lex captures
each one without losing fidelity.

### 15.1. `burn` — non-monotonic

```
law burn (r : ResourceId) (burner : ActorId) (amount : Nat)
where
  identifier   legalkernel.burn
  version      "1.0.0"
  action_index 2

  intent {
    Destroy `amount` units of resource `r` from `burner`'s balance.
    Authorised actors only; signature by `burner`.  Non-monotonic
    by design — reduces supply.
  }

  signed_by      burner
  authorized_by  deployment.burn_policy burner r

  pre := fun s => amount > 0 ∧ getBalance s r burner ≥ amount

  impl := do
    burn r: amount from burner

  satisfies := [
    local             [r],
    freeze_preserving [*],
    nonce_advances    [burner],
    registry_preserving
  ]
  -- Neither `conservative [r]` nor `monotonic [r]` is claimed.
  -- The kernel ships `burn_not_conservative` and `burn_not_monotonic`
  -- as negative witnesses.

  events := do
    let pre_balance := getBalance s r burner
    if amount > 0 then emit BalanceChanged r burner (pre_balance - amount) pre_balance
```

### 15.2. `freezeResource` — registry- and balance-preserving marker

```
law freezeResource (r : ResourceId)
where
  identifier   legalkernel.freezeResource
  version      "1.0.0"
  action_index 3

  intent {
    Mark resource `r` as frozen.  Future `transfer` / `mint` / `burn`
    invocations on `r` are rejected by their preconditions in any
    deployment that consumes the `FrozenForResource` invariant.
    This law itself is a no-op on the underlying `BalanceMap`.
  }

  signed_by      _governanceActor
  authorized_by  deployment.governance_policy _governanceActor r

  pre := fun _s => True

  impl := do
    freeze_resource r

  satisfies := [
    conservative      [*],
    monotonic         [*],
    local             [],
    freeze_preserving [*],
    nonce_advances    [_governanceActor],
    registry_preserving
  ]

  events := do
    -- no balance event; the freeze marker is observable only via
    -- `disputeStatus`-style reads.
    pure ()
```

### 15.3. `distributeOthers` — fold-of-flow

```
law distributeOthers
    (r : ResourceId) (rewarder : ActorId) (excluded : ActorId)
    (amount : Nat) (recipients : List ActorId)
where
  identifier   legalkernel.distributeOthers
  version      "1.0.0"
  action_index 6

  intent {
    Issue `amount` units of `r` to every recipient in `recipients`
    except `excluded`.  Each recipient receives the same flat
    `amount`; this is *not* proportional to existing balance.  The
    `recipients` list is supplied by the deployment via the
    `Action.distributeOthers` constructor and is bounded.
  }

  signed_by      rewarder
  authorized_by  deployment.reward_policy rewarder r

  pre := fun s => amount > 0

  impl := do
    for recipient in recipients:
      if recipient ≠ excluded then mint r: amount to recipient

  satisfies := [
    monotonic         [r],
    local             [r],
    freeze_preserving [*],
    nonce_advances    [rewarder],
    registry_preserving
  ]

  proof monotonic [r] := by
    -- The structural-induction synthesizer does not (in v1) handle
    -- fold-of-mint over a list.  We discharge it manually via
    -- `Laws.distributeOthers_isMonotonic` from the existing kernel.
    exact distributeOthers_isMonotonic r rewarder excluded amount recipients

  events := do
    for recipient in recipients:
      if recipient ≠ excluded ∧ amount > 0 then
        let pre_balance := getBalance s r recipient
        emit BalanceChanged r recipient (pre_balance + amount) pre_balance
```

This example exercises four mechanisms simultaneously:

  * the `for x in <bounded-list>:` loop construct;
  * the `if <pre>:` guarded statement;
  * a `proof <P> := by …` override for a property the v1 synthesizer
    cannot mechanically discharge (open question §14.4);
  * conditional event emission.

### 15.4. `dispute` — claim-bearing administrative law

```
law dispute (d : Dispute)
where
  identifier   legalkernel.dispute
  version      "1.0.0"
  action_index 8

  intent {
    File a §8.4 dispute against an existing log entry.  The kernel-
    level mutation is a no-op (the dispute is a structured marker
    written to the log; subsequent verdict actions consume it).
    The dispute pipeline's stage-1 acceptance is enforced at the
    runtime layer (`Disputes.fileDispute`), not by this law's
    `pre`.
  }

  signed_by      d.challenger
  authorized_by  deployment.dispute_policy d.challenger

  pre := fun _s => True

  impl := do
    -- All four dispute-pipeline action ctors compile to a no-op at
    -- the kernel level; the dispute's effects are observed via the
    -- `disputeStatus` log walk and the `applyVerdict` flow.
    freeze_resource 0    -- marker no-op (same definitional shape
                         --                as the existing dispute compileTransition)

  satisfies := [
    conservative      [*],
    monotonic         [*],
    local             [],
    freeze_preserving [*],
    nonce_advances    [d.challenger],
    registry_preserving
  ]

  events := do
    emit DisputeFiled d
```

This example shows how the four §8.4 dispute-pipeline action
constructors (`dispute`, `disputeWithdraw`, `verdict`, `rollback`)
are uniformly representable: each is a kernel-level no-op whose
*observable effect* is mediated by the dispute-pipeline modules
(`Disputes/Filing.lean`, `Disputes/Verdict.lean`, etc.).  Lex's
`signed_by` / `authorized_by` discipline applies uniformly.

### 15.5. A speculative deployment-private law: `staking_lock`

This law does not exist in the kernel today; it is sketched to show
how a deployment would add a new law.

```
law staking_lock (r : ResourceId) (staker : ActorId) (amount : Nat) (unlock_height : Nat)
where
  identifier   my_deployment.staking_lock
  version      "1.0.0"
  action_index 12

  intent {
    Lock `amount` units of `r` belonging to `staker` for use as
    voting weight or anti-fraud collateral.  The locked amount
    moves into a deployment-managed escrow account
    (`my_deployment.escrow_actor`).  The `unlock_height` is recorded
    for off-chain consumption; the kernel does not interpret it.
  }

  signed_by      staker
  authorized_by  deployment.staking_policy staker r

  pre := fun s =>
    amount > 0
    ∧ getBalance s r staker ≥ amount

  impl := do
    flow r: amount from staker to deployment.escrow_actor

  satisfies := [
    conservative      [r],
    monotonic         [r],
    local             [r],
    freeze_preserving [*],
    nonce_advances    [staker],
    registry_preserving
  ]

  events := do
    let pre_staker := getBalance s r staker
    let pre_escrow := getBalance s r deployment.escrow_actor
    emit BalanceChanged r staker                     (pre_staker - amount) pre_staker
    emit BalanceChanged r deployment.escrow_actor    (pre_escrow + amount) pre_escrow
    emit StakingLocked  staker amount unlock_height        -- user-defined event
```

The `unlock_height` field is captured into the event but does not
affect the kernel state.  Off-chain processes read the event log
and act on `unlock_height` (e.g. by submitting an `unstake`
SignedAction at the right height); the kernel itself never compares
heights.

This example demonstrates two things:

  1. The same `flow` calculus that captures `transfer` captures any
     escrow-style law verbatim.  The `satisfies` synthesizers
     discharge `conservative [r]` mechanically because the underlying
     `impl` is a single `flow`.
  2. User-defined events (`StakingLocked`) compose with the
     auto-emitted `BalanceChanged` and `NonceAdvanced` events; the
     deployment registers `Event.stakingLocked` as a constructor in
     its private event vocabulary (a v3 feature; see §13.3).

---

## Appendix A: Comparison to the Phase-4 `law` macro

| Aspect                               | Phase-4 macro (current)           | Lex (proposed)                                     |
|--------------------------------------|-----------------------------------|----------------------------------------------------|
| Output                               | `Transition` only                 | `Transition` + `Action` ctor + 5 supporting branches + instances |
| Mandatory clauses                    | `pre`, `impl`                     | + `signed_by`, `authorized_by`, `satisfies`, `intent`, `action_index` |
| Property synthesis                   | none                              | typeclass-driven library + `proof` overrides       |
| Authority binding                    | hand-written elsewhere            | macro-required, structural                         |
| Decidability discipline              | enforced via `[DecidablePred pre]` failure | + grammar restriction, structured diagnostics |
| Action-index management              | hand-managed in `Authority/Action.lean` | mechanically enforced via `lex_index_registry.txt` |
| Versioning                           | none                              | semver, mechanically checked, refinement obligations |
| Manifest                             | none                              | `deployment` macro with `invariant_claims`         |
| Documentation                        | docstring on the `def`            | `intent` block + `lex_diff` semantic diff          |
| TCB impact                           | none (non-TCB)                    | none (non-TCB; macros only)                        |

Phase-4's macro is a *primitive*; Lex is the *language built on
that primitive plus the rest of the kernel*.

## Appendix B: Relationship to existing project artefacts

Lex builds on the following existing components.  This appendix
gives reviewers a single index for cross-checking specific claims
against existing modules.

| Existing component                                 | Used by Lex for…                                                            |
|----------------------------------------------------|-----------------------------------------------------------------------------|
| `LegalKernel/Kernel.lean`                          | the `Transition` record, the `step_impl` semantics, the §4.10 invariants    |
| `LegalKernel/RBMapLemmas.lean`                     | the `find?_insert_*` lemmas the `flow` desugaring relies on                 |
| `LegalKernel/Conservation.lean`                    | `IsConservative` / `IsMonotonic` typeclasses; `MonotonicLawSet`             |
| `LegalKernel/Authority/Action.lean`                | the closed `Action` inductive Lex extends                                   |
| `LegalKernel/Authority/SignedAction.lean`          | the `Admissible` predicate Lex wires `signed_by` / `authorized_by` into     |
| `LegalKernel/DSL/Law.lean` (Phase-4 WU 4.9)        | the existing `law` macro Lex supersedes (kept compiling for one minor)      |
| `LegalKernel/Encoding/Action.lean`                 | the encode / decode / fieldsBounded branches Lex generates                  |
| `LegalKernel/Encoding/SignInput.lean`              | the cross-deployment-replay layer Lex's `deployment_id` flows into          |
| `LegalKernel/Events/Extract.lean`                  | the `actionEvents` branches Lex generates                                   |
| `LegalKernel/Test/Property.lean` (Audit-3.9)       | the property-test harness Lex's auto-generation builds on                   |
| `LegalKernel/Runtime/AttestedSnapshot.lean` (Audit-3.2) | the attestation pattern Lex manifests reuse for governance signing     |
| `Tools/CountSorries.lean`, `Tools/TcbAudit.lean`   | the audit-binary template Lex's `lex_lint` / `lex_codegen` follow           |
| `tcb_allowlist.txt`                                | the TCB-import gate; Lex modules go on a non-TCB list, no allowlist edits   |
| `lex_index_registry.txt`                           | new file Lex introduces; tracks frozen action indices                       |
| `docs/decidability_discipline.md` (WU 1.6)         | the decidability rule §6.1 enforces by grammar                              |
| `docs/economic_invariants.md`                      | the firewall semantics §7.3's `MonotonicLawSet` synthesis preserves         |
| `docs/abi.md`                                      | the on-disk format the action-index commitments surface in                  |

No existing artefact is modified incompatibly by Lex.  M2 (§12.2)
regenerates four files, but the regenerated content is byte-
equivalent (modulo formatting) to the hand-written form they replace.

---

*End of document.*  See `docs/GENESIS_PLAN.md` §12 for the wider
implementation roadmap; this document fits between Phase 6
(Disputes) and Phase 7 (Advanced capabilities) as a deployment-
ergonomics deliverable that is itself non-TCB.
