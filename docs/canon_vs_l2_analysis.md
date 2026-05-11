<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

# Canon vs. Traditional L2s — A Comparative Analysis

> **Document status.** Exploratory analysis, not part of the canonical
> design corpus. Where this document disagrees with
> [`docs/GENESIS_PLAN.md`](GENESIS_PLAN.md), the Genesis Plan wins. The
> purpose here is to situate Canon's design choices against the
> contemporary L2 (optimistic and ZK rollup) landscape, identify what
> is genuinely novel, what is structurally familiar, and what the
> trade-offs cost.

## 0. TL;DR

Canon is **not primarily an L2**. It is a proof-carrying state
transition system that happens to ship a rollup-shaped Ethereum
bridge as one of its deployment targets. The pieces of Canon that
look most like a rollup (bridge, sequencer, attestor, dispute
window, withdrawal proofs) are conventional; the pieces underneath
(the kernel, the typeclass firewalls, the dispute pipeline as a
deterministic Lean function, the immutable-by-construction L1
contracts, the three-axiom proof discipline) are genuinely
different from anything shipped by Optimism / Arbitrum / zkSync /
StarkNet / Polygon zkEVM / Scroll.

Whether this is "a decent path to explore" depends on the question
you are trying to answer:

- **"Can we make Ethereum cheaper / faster?"** — No, Canon is not
  competitive here, and is not trying to be. EVM-incompatibility is
  the headline cost; throughput is bounded by single-threaded
  execution; the design deliberately rejects the "scale by parallel
  proving" thesis that modern rollups are built on.

- **"Can we make a state machine whose invariants are
  machine-checked end-to-end, with a TCB a single specialist can
  review in a day, no admin keys, no upgradeable proxies, and a
  dispute resolution mechanism that is a pure function rather than
  an interactive bisection game?"** — Yes, and Canon is one of very
  few systems pursuing this seriously. The intellectual reference
  class is seL4 and CompCert, not the rollup landscape.

The honest answer to "is this designing the same thing all over
again?" is: **the bridge layer is, the kernel is not.** The
unfortunate corollary is that Canon's most distinctive
contributions — the typeclass firewalls, the three-axiom kernel,
the deterministic dispute pipeline, the immutability discipline —
are mostly invisible from the L2 user's perspective. They show up
only when you ask the question "what would have to be wrong for
this system to lose user funds?" and look at the answer.

The rest of this document expands each claim. §1 sketches what
Canon actually is. §2 sketches what traditional L2s actually are.
§3 — §8 compares them along seven axes. §9 lists the structural
similarities (where Canon and rollups overlap). §10 lists the
genuine novelties. §11 lists the honest costs. §12 returns to the
question and gives a verdict.

---

## 1. What Canon actually is

The full design lives in [`docs/GENESIS_PLAN.md`](GENESIS_PLAN.md).
For this comparison the relevant facts are:

1. **A Lean 4 trusted core of ~200 lines** (`LegalKernel/Kernel.lean`).
   The kernel defines `State`, `Transition`, `Legal`,
   `CertifiedTransition`, `Reachable`, plus the four headline
   theorems: `impl_refines_spec`, `impl_noop_if_not_pre`,
   `invariant_preservation`, and `apply_certified_eq_step_impl`. The
   kernel has zero external Lake dependencies; it imports only
   `Std.Data.TreeMap` (Lean core) and the sibling proof-library
   `LegalKernel.RBMapLemmas.lean`. Every kernel theorem
   `#print axioms` reduces to exactly
   `[propext, Classical.choice, Quot.sound]` — the three Lean
   built-ins. There are no custom axioms.

2. **Laws are values, not code.** A `Transition` is a triple
   `(pre : State → Prop, decPre : Decidable witness, apply_impl :
   State → State)`. Specific laws (`transfer`, `mint`, `burn`,
   `freeze`, `reward`, `deposit`, `withdraw`, etc.) live one per
   file under `LegalKernel/Laws/` and are not part of the TCB.
   Bugs in a law cannot violate any invariant the kernel proved
   the law preserves — they can only introduce *new* legal
   behaviour, which is mitigated by published, version-controlled
   law sets.

3. **Typeclass firewalls for global properties.** `IsConservative`
   and `IsMonotonic` are typeclasses (`LegalKernel/Conservation.lean`).
   `ConservativeLawSet` and `MonotonicLawSet` deployments do not
   elaborate if their law list contains a non-conservative or
   supply-destroying law, because no instance can be synthesised.
   `mint_not_conservative`, `burn_not_conservative`, and
   `burn_not_monotonic` ship as the negative witnesses that make
   the firewall sound.

4. **Replay protection as a Lean theorem.** Per-actor nonces are
   tracked in `Authority/Nonce.lean`; `expectsNonce_strict_mono`,
   `nonce_uniqueness`, and `replay_impossible` are theorems, not
   conventions. The kernel's authority layer is bounded by the
   `Verify` opaque (a deployment-supplied signature primitive,
   assumed EUF-CMA secure).

5. **Canonical, deterministic encoding (CBE).** Every `Action`,
   `SignedAction`, `State`, and `ExtendedState` has a canonical
   byte form with proved round-trip and injectivity. The decoder
   rejects non-canonical inputs (unsorted / duplicate map keys).
   `signInput` prefixes a deployment-ID hash so signatures cannot
   replay across deployments.

6. **A four-stage dispute pipeline** (`LegalKernel/Disputes/`):
   `fileDispute → checkEvidence → proposeVerdict → applyVerdict`.
   Every stage is a *pure Lean function* over a closed inductive
   of five claim variants (`preconditionFalse`, `signatureInvalid`,
   `nonceMismatch`, `oracleMisreported`, `doubleApply`). Two
   adjudicators given the same inputs reach the same verdict; the
   safe `applyVerdict` entry point requires a
   `VerdictPassedStage3` propositional witness, making every error
   path mechanically unreachable.

7. **An Ethereum-anchored bridge** (`LegalKernel/Bridge/` +
   `solidity/`) implementing deposit, withdraw, state-root
   submission, dispute filing, and one-shot migration. The L1
   contracts are deployed **immutably** — no proxy, no
   `initialize`, no upgrade authority, no `Pausable`, no mutable
   role grants. Recovery from sequencer or attestor misbehaviour
   uses the dispute pipeline plus an attested-handoff
   `CanonMigration.sol` mechanism.

8. **A Lex law-declaration language** (LX milestones M1 – M3,
   complete) that elaborates declarative `lexlaw` blocks into
   Lean `Transition`s, supports deployment manifests with
   deterministic content hashes, and ships governance tooling
   (`lex_diff` for semantic diffs and `patch`/`minor`/`major`
   bump classification, `lex_format` for canonical
   pretty-printing).

Putting the pieces together: Canon is a state machine whose
**rules are programs**, whose **legality is a proof**, whose
**governance is itself a state machine**, and whose **bridge to
Ethereum is a thin, conventional rollup-shaped envelope around
all of that**.

---

## 2. What traditional L2s actually are

The contemporary L2 landscape splits into two camps:

### 2.1 Optimistic rollups

Examples: Optimism, Arbitrum (One, Nova, Orbit chains), Base,
Mantle, Blast, World Chain. Mechanism:

1. A *sequencer* batches L2 transactions and posts state-root
   commitments + transaction data (or pointers to data) to an
   L1 *batcher contract*.
2. State roots are *not* proven correct at submission time.
   They are *assumed* correct until challenged.
3. A *fraud proof* mechanism (Cannon for Optimism, BoLD for
   Arbitrum) lets anyone challenge a state root within a
   dispute window (~7 days). The challenge is an interactive
   bisection game over the L2 transaction trace: the disputing
   parties narrow down to a single contested instruction, which
   the L1 verifier then executes natively (MIPS instructions
   for Cannon, WAVM for Arbitrum BoLD).
4. The L1 contracts are typically upgradeable via proxy +
   Security Council multi-sig (Optimism's Security Council:
   8-of-13; Arbitrum's: 9-of-12).

Trust model: at least one honest verifier exists, plus the
Security Council does not collude (under Optimism's "Fault Proof
System" the bond mechanism aligns incentives, but the proxy
upgrade path remains).

### 2.2 ZK rollups

Examples: zkSync Era, StarkNet, Polygon zkEVM, Scroll, Linea,
Taiko (hybrid). Mechanism:

1. A *sequencer* batches L2 transactions and forwards them to a
   *prover*.
2. The prover generates a zero-knowledge proof that the batch was
   executed correctly with respect to the prior state root and
   yields the claimed new state root.
3. An L1 *verifier contract* checks the proof. Verified state
   roots are immediately final (no dispute window).
4. The L1 contracts are typically upgradeable via proxy +
   multi-sig + (for some chains) a time-locked upgrade key.

Trust model: the ZK proof system is sound (cryptographically), the
trusted setup (if any) is honest, the prover's circuit is bug-free,
the verifier contract matches the prover's circuit.

### 2.3 What both camps share

- **Centralised sequencer** in production (decentralisation is
  on every roadmap; near-universally deferred).
- **Upgradeable L1 contracts** via proxy + admin multi-sig +
  (sometimes) time lock. Vitalik's "training wheels" framework
  for L2 maturity (Stage 0 / Stage 1 / Stage 2) treats this
  as a *maturity* axis, not an architectural axis.
- **EVM compatibility** or near-equivalence as a primary value
  proposition: existing Solidity code, existing wallets, existing
  developer tooling.
- **L1 is the source of truth for L2 validity**: whatever the L1
  verifier accepts is final. There is no separate notion of
  "the state machine's rules" — the rules *are* whatever the
  L1 contract (plus the off-chain prover or fraud proof game)
  computes.

---

## 3. Where does "validity" live?

The single sharpest difference between Canon and rollups is the
answer to this question.

| System type | Source of truth for "is this transition valid?"                       |
|-------------|-----------------------------------------------------------------------|
| Optimistic  | An L1 fraud-proof verifier contract, invoked only if challenged.      |
| ZK          | An L1 verifier contract checking a SNARK against the new state root.  |
| Canon       | The Lean type checker, at compile time, for every transition class.   |

The rollup model is **operational**: validity is "what happens
when you run the verifier". This is the model that fits naturally
into the EVM: a contract is a program; programs have semantics;
semantics are operational; correctness is "the program does what
its English-language spec said".

The Canon model is **deductive**: validity is "what the type
system can prove holds". A transition `t` can be applied to state
`s` only when an inhabitant of `Legal s t` can be exhibited; the
inhabitant is a proof of `t.pre s`, and the type system rejects
any non-proof. The kernel never *checks* legality at runtime
beyond reducing the `Decidable` instance; the type-level
guarantee is that *no other reduction path can advance state*.

This sounds like a hair-splitting distinction until you ask: what
*classes* of bug are foreclosed?

- **Reentrancy.** Rollups inherit reentrancy from the EVM and
  defend against it via `nonReentrant` guards (used in
  `CanonBridge.sol` precisely because the *Solidity side* needs
  them). The Lean kernel has no notion of reentrancy because
  `apply_impl : State → State` is a total pure function — you
  cannot call back into the kernel mid-application.

- **Integer overflow.** Canon's `Amount := Nat` is unbounded
  natural numbers; overflow absence is a theorem, not an audit
  finding. Solidity's `uint256` overflows pre-0.8 silently; post-0.8
  it reverts (which is then a liveness bug, not a safety bug, but
  still a class of attack surface).

- **Silent state corruption.** `impl_noop_if_not_pre` (in
  `Kernel.lean`) is the theorem that a failed precondition leaves
  the state byte-identical. There is no rollup analogue: a fraud
  proof can identify *that* the state transitioned wrongly, but
  not *prevent* the wrong transition from being posted in the
  first place; the dispute window is the prevention mechanism.

- **Conservation violations.** This is where the typeclass
  firewall starts mattering. In a rollup, "this batch did not
  inflate the total supply of USDC" is a property someone has to
  audit by reading the batch's effect on contract state. In Canon,
  `ConservativeLawSet` refuses to elaborate if any law in the set
  fails the `IsConservative` instance; an attempt to deploy a
  conservation-claiming chain that includes a non-conservative
  law produces a *compilation error*, not a runtime bug.

The cost of the deductive model is real. Not every property
expressible as "a thing the rollup verifies" can be expressed as a
`Decidable` precondition over a `Transition`. Open Research
Question 15.1 of the Genesis Plan (decidability at the boundary)
explicitly names this as unsolved: the law-author has to keep
preconditions in the decidable fragment by discipline, not by
type-level enforcement.

---

## 4. What is formally guaranteed?

Rollups guarantee, under their respective trust models:

- **Optimistic:** any state root not challenged within the dispute
  window is correct, *given* an honest verifier; any state root
  challenged and not defended is reverted.
- **ZK:** any state root accepted by the L1 verifier was computed
  correctly from the prior state root and a valid batch, *given*
  soundness of the proof system.

Canon guarantees, in addition:

| Property                                  | Theorem                                       | File                                                   |
|-------------------------------------------|-----------------------------------------------|--------------------------------------------------------|
| Determinism (typing-level)                | `step_impl` is a function                     | `LegalKernel/Kernel.lean`                              |
| No silent illegality                      | `impl_noop_if_not_pre`                        | `LegalKernel/Kernel.lean`                              |
| Refinement of impl to spec                | `impl_refines_spec`                           | `LegalKernel/Kernel.lean`                              |
| Inductive invariant preservation          | `invariant_preservation[_via_laws]`           | `LegalKernel/Kernel.lean`                              |
| Composability of invariants               | `invariants_compose`                          | `LegalKernel/Kernel.lean`                              |
| Per-resource supply preservation          | `total_supply_global[_via_law_set]`           | `LegalKernel/Conservation.lean`                        |
| Monotonic non-decrease                    | `total_supply_globally_nondecreasing`         | `LegalKernel/Conservation.lean`                        |
| Action compilation is injective           | `Action.compile_injective`                    | `LegalKernel/Authority/Action.lean`                    |
| Per-actor strict nonce monotonicity       | `expectsNonce_strict_mono`                    | `LegalKernel/Authority/Nonce.lean`                     |
| Replay impossibility                      | `replay_impossible`                           | `LegalKernel/Authority/SignedAction.lean`              |
| Domain-separated sign inputs              | `signInput_*` distinguishes                   | `LegalKernel/Encoding/SignInput.lean`                  |
| Byte-identical replay across architectures| `replay_deterministic`                        | `LegalKernel/Runtime/Replay.lean`                      |
| Withdrawal proof completeness             | `verifyProof_complete`                        | `LegalKernel/Bridge/WithdrawalRoot.lean`               |
| Withdrawal proof soundness                | `verifyProof_sound` (under `CollisionFree`)   | `LegalKernel/Bridge/WithdrawalRoot.lean`               |
| EIP-712 wrap injectivity                  | `eip712Wrap_injective` (under `CollisionFree`)| `LegalKernel/Bridge/Eip712.lean`                       |
| Bridge actor cannot sign user withdrawals | `bridgePolicy_rejects_withdraw`               | `LegalKernel/Bridge/BridgeActor.lean`                  |
| Dispute pipeline determinism              | `checkEvidence_deterministic`                 | `LegalKernel/Disputes/Evidence.lean`                   |
| Verdict totality under Stage-3 witness    | `applyVerdict_under_witness_succeeds`         | `LegalKernel/Disputes/Verdict.lean`                    |

The full table — **221 type-level guarantees** at the time of
LX-M3 — lives in [`CLAUDE.md`](../CLAUDE.md) under "Type-level
design properties". Every theorem is sorry-free and
`#print axioms`-clean.

These are not *more* guarantees than rollups have; they are
*differently scoped* guarantees. A rollup's "the state root was
correctly computed from the batch" is, in some sense, a
strictly stronger statement about a single transition than
`impl_refines_spec`. But Canon's `invariant_preservation` is
strictly stronger than anything rollups state: it says that
*any* deployment-defined property which holds initially and is
preserved by every legal step holds in every reachable state,
across the entire history of the chain. The rollup analogue
would be "Optimism guarantees the total supply of USDC has not
been inflated since genesis" — which is not stated by any rollup,
because rollups don't have a kernel-level mechanism for asserting
it.

The closest analogue to Canon's invariant-preservation in the
rollup world is the *correct-prover-circuit* property of ZK
rollups: if the circuit faithfully encodes EVM semantics, then
verified state roots transitively encode every EVM-level
invariant. The catch is that the circuit's faithfulness is
itself an audit obligation, not a theorem. Canon's
faithfulness-of-execution claim runs the other way: the Lean
side *is* the spec, the Solidity side is a port whose
correspondence is verified by ~656 cross-stack fixtures
(`solidity/test/fixtures/*` produced by Lean test drivers).

---

## 5. Trust assumptions and the TCB

The trusted computing base — the set of things a system's
guarantees rest on, such that any bug there is a system bug — is
where Canon's discipline departs most sharply from typical
rollup practice.

### 5.1 Canon's TCB

Per Genesis Plan §6.6:

1. **The Lean 4 type checker** (a few thousand lines of
   well-reviewed C++).
2. **`Std.Data.TreeMap` and the few other Std modules** the
   kernel imports (audited per `docs/std_dependencies.md`).
3. **The kernel module** — `LegalKernel/Kernel.lean` plus
   `LegalKernel/RBMapLemmas.lean`. Together, ~600 lines of Lean
   including comments.
4. **The OS and hardware** Lean runs on (out-of-scope per
   §10.2).
5. **For authorised transitions only:** the deployment-supplied
   cryptographic primitives (`Verify`, `hashBytes`) and their
   security assumptions (EUF-CMA and collision-resistance,
   respectively).

The `Verify` and `hashBytes` are `opaque` declarations, not
`axiom` declarations. This is a deliberate distinction:
`#print axioms` on every kernel theorem returns exactly the three
Lean built-ins, even theorems whose statements mention these
primitives. The cryptographic security assumptions surface as
trust assumptions, not as Lean axioms.

Mechanical enforcement:

- `lake exe count_sorries` — rejects any `sorry` in
  `Kernel.lean`, `RBMapLemmas.lean`, or `Laws/Transfer.lean`.
- `lake exe tcb_audit` — rejects any TCB-core file importing
  anything not on `tcb_allowlist.txt` or in
  `Tools.Common.tcbInternalImports`.
- `lake exe stub_audit` — flags placeholder-body stubs (e.g.
  `:= ByteArray.empty`) when accompanied by red-flag docstring
  tokens.
- CI's strict-warnings gate fails the build on any `: warning:`
  line, including `linter.missingDocs` and
  `linter.unusedVariables`.

### 5.2 Typical rollup TCB (Stage 0 / Stage 1 maturity)

For an EVM-equivalent rollup at the level of maturity most
chains currently operate at, the TCB includes (non-exhaustively):

- The L1 bridge contract (e.g. Optimism's
  `OptimismPortalProxy` + `OptimismPortal` implementation +
  `L2OutputOracleProxy` + `L2OutputOracle` implementation, plus
  the libraries they import — into the thousands of lines of
  Solidity).
- The L1 fraud-proof or ZK-verifier contract.
- The dispute game contract (for optimistic) or proof aggregator
  (for ZK).
- The off-chain fraud-prover or ZK-prover code (Rust / Go /
  Cairo / etc., into the tens of thousands of lines).
- The sequencer / batcher binary and its key management.
- The Security Council multi-sig and its operational discipline.
- For ZK: the trusted setup (if KZG-based; not for STARKs).
- The Solidity compiler.
- Every library the contracts import (OpenZeppelin, etc.) — and
  every CVE issued against those libraries during the contract's
  deployed lifetime, because the contracts are upgradeable.

The Stage-2 maturity threshold (Vitalik's framework) would
remove the Security Council from the TCB. As of this writing
(May 2026), no major EVM rollup is at Stage 2.

### 5.3 The asymmetry

A skilled reviewer can audit `LegalKernel/Kernel.lean` in an
afternoon. The Lean type checker has been audited in pieces by
the Lean community over a decade. The `Std.Data.TreeMap` lemmas
Canon depends on are explicitly enumerated and re-audited on
every toolchain bump (`docs/std_dependencies.md`).

A skilled reviewer cannot audit Optimism's contracts in an
afternoon. The contracts are not the problem in isolation —
they are well-reviewed individually — but the *graph* of
upgrade authority, proxy patterns, library imports, and the
runtime semantics of the EVM combine into a TCB that no single
reviewer holds in their head. This is *not* a criticism of
Optimism; it is the cost of EVM compatibility.

Canon's TCB story is unprecedented in the L2 design space. It
is more comparable to seL4 (the formally verified microkernel,
~10 KLOC of C with a Coq proof) or CompCert (the formally
verified C compiler, ~80 KLOC of Coq + OCaml). The intellectual
debt is to those projects, not to Optimism's `OptimismPortal`.

---

## 6. Upgrade discipline and governance

This is the cleanest break with rollup practice.

### 6.1 Rollup upgrade model

All major rollups today rely on **upgradeable proxy contracts**.
The proxy points at an implementation address; an upgrade
swaps the implementation address. The upgrade authority is
typically a multi-sig (Security Council). Time locks are
sometimes layered on top, but they always have an emergency
override.

This is a sensible engineering choice for systems that face an
adversarial threat landscape and need the ability to patch live
bugs. It is also, formally, *the entire system is mutable by
the multi-sig*. The L1 contracts say what they say *today*; they
say something different tomorrow if the multi-sig decides so.
Audit reports describe a snapshot of behaviour, not a
permanent commitment.

### 6.2 Canon's upgrade model

Per [`docs/ethereum_integration_plan.md`](ethereum_integration_plan.md)
§7 / §20 and `solidity/src/contracts/CanonMigration.sol`, Canon's
L1 contracts are deployed **immutably**. Every field that could
be mutable is `immutable` or `constant`. There is:

- **No proxy.** Contract addresses are fixed at deployment via
  CREATE3.
- **No `initialize`.** The constructor is the only state-setting
  entry point.
- **No admin role.** There is no `onlyOwner`, no `onlyAdmin`,
  no role grant.
- **No `Pausable`.** Recovery from sequencer / attestor
  misbehaviour is via the dispute pipeline, not a kill switch.
- **No upgrade hook.** Implementation slots are not used.

The single mechanism for changing the rules is `CanonMigration.sol`,
which implements a **one-shot, cryptographically attested handoff**
between a predecessor `CanonBridge` and a successor `CanonBridge`.
The migration contract has exactly two state mutations:

1. The constructor (which sets every field as `immutable` and
   verifies the migration attestation against the predecessor's
   attestor key).
2. A one-shot `activate()` call that flips a single
   `bool activated` field, after a constructor-fixed grace window
   (≥ 30 days by `MIN_GRACE_WINDOW_BLOCKS`).

After activation, the predecessor's `MigrationActivated` circuit
breaker fires, the predecessor refuses new deposits and
withdrawal proofs, and users exit via the predecessor's
`revertToPriorRoot` path or through the migration's attested
state-root handoff to the successor.

The discipline this enforces is closer to a **hard fork** than to
an upgrade. There is no admin who can change `CanonBridge`'s
behaviour in place. Recovery from a kernel bug is "deploy a new
chain, exit through the bridge, re-enter the new chain". The
trade-off is severe operationally (user friction, ecosystem
fragmentation) but mathematically clean: the bridge is what its
bytecode says it is, no exceptions.

The CanonMigration contract's invariants are themselves
mathematically pinned (the audit-3 fix that surfaced the
predecessor-references-this-migration check is documented in
`CanonMigration.sol:62 – 78`): the migration is bound to a
specific predecessor at deployment time and cannot retroactively
freeze any other contract.

### 6.3 Why this is unusual

Most production rollups acknowledge the upgrade authority as
the system's failure mode of last resort and argue that the
ability to fix bugs in production is worth the trust assumption.
Canon's bet is the opposite: that *making the rules immutable
forces the rules to be correct before deployment*. The
discipline is not so much that bugs can't happen as that bugs
must be *expensive enough* to motivate the formal verification
work upstream.

This is not a value-neutral choice. A system with no upgrade
path is one where every bug is a chain split. The mitigation in
Canon's design is the proof discipline: if the kernel is
provably correct against its specified invariants, the residual
bug surface is the gap between the formal spec and the user's
expectation — a much narrower gap than "the contract code might
do something different from what it appears to do".

The cultural reference class here is Bitcoin, which has changed
its consensus rules a handful of times in 17 years and treats
each change as a major engineering event. Canon takes that
discipline and brings it to the level of "the rules of the state
machine", with formal verification as the compensating control
that makes pre-deployment correctness tractable.

---

## 7. Expressiveness vs. correctness

The hardest honest critique of Canon, evaluated as an L2, is
that **it is not Turing-complete in any practical sense**.

A `Transition` is a function `State → State` together with a
`Decidable Prop` precondition. The "decidable" constraint rules
out anything requiring unbounded search or unbounded
quantification over external data. In practice this constrains
the expressible laws to:

- Pure arithmetic predicates over balances and identifiers.
- Finite conjunctions of such predicates.
- Predicates that can be discharged via `inferInstance` from
  Lean core's `Decidable` instances on `Nat`, `Bool`, finite
  lists of bounded types, etc.

Per the **decidability discipline** (`docs/decidability_discipline.md`,
formalised at Genesis Plan §13.6 step 2): every law's
`Transition.decPre` should be definable as
`fun _ => inferInstance` whenever the precondition is built from
arithmetic comparisons, `Nat` operations, and finite conjunctions.
A law needing a hand-written `Decidable` derivation is a signal
that the precondition may contain an unbounded quantifier or a
non-computable predicate.

This is enough to express:

- Ledger laws (transfer, mint, burn, freeze, reward,
  distributeOthers, proportionalDilute, deposit, withdraw).
- Identity laws (register, replaceKey, revoke).
- Local policy laws (declareLocalPolicy, revokeLocalPolicy).
- Dispute pipeline laws (file, withdraw, propose, apply).

This is **not** enough to express, naturally:

- A Uniswap-style AMM that recomputes liquidity invariants over
  arbitrary token sets. (Expressible in principle by
  parameterising the law over a finite set of pools, but
  unwieldy.)
- Arbitrary smart-contract code with internal control flow,
  storage, and external calls.
- Anything requiring on-the-fly compilation of user-supplied
  bytecode.

The contrast with EVM rollups is stark. Solidity is
Turing-complete; any computation expressible in EVM bytecode is
deployable. The trade-off is between Canon's "narrow but
verified" model and rollups' "wide but trust-the-bytecode"
model. Neither dominates the other on every axis.

For deployments where the law set is fixed at deployment and
governance is structural (an issuance system, a registry, a
voting protocol, a clearing-and-settlement layer), Canon's
constraint is not a real cost. For deployments where users
deploy arbitrary code (DeFi, NFTs as expressive contracts,
arbitrary DAO logic), Canon's constraint is a hard limit.

The Lex M3 work (deployment manifests, `lex_diff`'s
semantic-bump classifier) addresses *governance* of the law set
without removing the decidability constraint. The way an
AMM-shaped law would deploy on Canon is by being declared as
a Lex law, undergoing the `major`-bump review process, and
being added to the deployment's law set — *not* by being
submitted as a user transaction at runtime.

---

## 8. Performance envelope

Canon's performance characteristics are set in Genesis Plan §11.

| Operation                       | Cost                       |
|---------------------------------|----------------------------|
| `getBalance s r a`              | O(log R + log n_r)         |
| `setBalance s r a v`            | O(log R + log n_r)         |
| `transfer.apply_impl`           | O(log R + log n_r)         |
| `transfer.pre`                  | O(log R + log n_r)         |
| `step_impl`                     | cost of `pre` + `apply_impl` |
| `apply_certified`               | cost of `apply_impl`       |
| `TotalSupply s r`               | O(n_r)                     |

Per §11.5, the kernel is **single-threaded by design**.
Concurrency is the runtime's problem (serialise and feed one
at a time). The achievable throughput target is "thousands of
transitions per second" for moderate workloads. Memory profile
for a million-actor, ten-resource deployment is ~500 MB
working set (§11.4).

Compare:

- **Optimism**: ~2,000 TPS theoretical, ~300-500 TPS
  practical, scaling through batch size and L1 calldata pricing.
- **Arbitrum One**: similar order of magnitude.
- **StarkNet**: 100-1000+ TPS, depending on proof cadence.
- **Solana** (not a rollup but the relevant scale comparison
  for "throughput-first" chains): ~50,000 TPS theoretical with
  parallel execution; 1,000-3,000 TPS practical.

Canon's design is not throughput-optimised. The kernel's
correctness story is a single-thread of execution because that
is the simplest model to prove invariants over. The roadmap
acknowledges sharding as a post-Phase-7 extension (§11.5);
there is no concrete sharding design today, and the Open
Research Question at §15.4 names cross-shard atomicity as an
unsolved problem.

For deployments where correctness matters more than throughput
(clearing systems, identity registries, regulatory compliance
engines), Canon's throughput is more than adequate. For
deployments where throughput is the headline metric (general
DeFi, gaming), Canon is not competitive.

---

## 9. Structural similarities (where Canon and rollups overlap)

The bridge layer's *shape* is, frankly, conventional.

| Component                       | Canon                                      | Optimism                       | Arbitrum                  |
|---------------------------------|--------------------------------------------|--------------------------------|---------------------------|
| L1 deposit entry point          | `CanonBridge.deposit` (per resource)        | `OptimismPortal.depositTransaction` | `Inbox.depositEth`     |
| State-root commitment           | `CanonBridge.submitStateRoot` (attestor)    | `L2OutputOracle.proposeL2Output`     | `Outbox.executeTransaction` |
| Dispute window                  | Configurable, default ~12 minutes (64 blocks) per §3.3 | 7 days                | 7 days                    |
| Withdrawal proof                | SMT inclusion proof (height 64, keccak256)  | Merkle proof via `OptimismPortal` | Outbox Merkle proof  |
| Withdrawal finalisation         | `withdrawWithProof` after dispute window     | `OptimismPortal.finalizeWithdrawal` | `Outbox.executeTransaction` |
| Dispute filing                  | `CanonDisputeVerifier.fileDispute`           | `DisputeGameFactory.createGame`     | `RollupCore.createNewBatch` |
| Sequencer                       | Single attestor (MVP)                        | Single sequencer (MVP-ish)         | Single sequencer       |
| Recovery from L1 contract bug   | `CanonMigration` one-shot handoff            | Proxy upgrade by Security Council | Same (Arbitrum Sec Council) |

Reading down the column for Canon, you see: deposit, state-root
post, dispute window, withdrawal proof, finalisation, dispute
filing. This is **the rollup playbook**. The structural shape
is the same.

What is different is *what backs each box*:

- The state-root computation is a Lean program with a deterministic
  encoding theorem, not a Solidity program with an audit trail.
- The dispute verifier is a port of pure-Lean dispute pipeline
  functions, with cross-stack equivalence fixtures (656 inputs
  in Workstream F) verifying that the Solidity and Lean sides
  compute the same answer.
- The withdrawal proof structure is an SMT over `BridgeState.pending`
  with a Lean-verified `verifyProof_complete` (unconditional) and
  `verifyProof_sound` (under collision resistance). Most rollups
  use Merkle proofs of varying degrees of careful specification;
  Canon's is one of the few cases where the verifier is the same
  algorithm on both sides (`SmtVerifier.sol` reflects
  `LegalKernel/Bridge/WithdrawalRoot.lean`).
- The recovery model is one-shot handoff (`CanonMigration`) rather
  than upgradeable proxy.

If you squint, Canon looks like an optimistic rollup with a
shorter dispute window, a less expressive state machine, and a
weirder L1 contract suite. If you don't squint, the differences
are constitutional.

---

## 10. The genuine novelties

Setting aside the bridge-layer similarities, here is what Canon
does that no production rollup does:

### 10.1 Three-axiom proof discipline

Every kernel theorem `#print axioms` to exactly
`[propext, Classical.choice, Quot.sound]`. No custom axioms;
custom axioms would be a Genesis Plan amendment and trigger the
two-reviewer gate (§13.6). This is the proof-theoretic
discipline of systems like seL4, brought to a chain state
machine.

### 10.2 TCB-allowlist enforcement

`lake exe tcb_audit` rejects any TCB-core file (`Kernel.lean`,
`RBMapLemmas.lean`) importing anything not on
`tcb_allowlist.txt` or in `Tools.Common.tcbInternalImports`.
The TCB-allowlist is a *specific list of modules*, not a
namespace pattern: a TCB-core file that imports e.g.
`LegalKernel.Laws.Transfer` fails the audit and blocks the
merge. This is unusual; most projects rely on convention to
keep the trusted core small. Canon mechanises it.

### 10.3 Typeclass firewalls for global properties

`ConservativeLawSet` and `MonotonicLawSet` (and the LX-tier
classifications `FreezePreservingLawSet`, `LocalTo`, etc.) are
typeclasses that refuse to elaborate when a non-conforming law
is on the list. This is a compile-time guarantee about a
*global* property of an entire deployment. It is qualitatively
different from "an audit confirmed this property".

The compositional form is what gives this teeth. A deployment
that adds a new conservative law to its list does not
re-trigger audit of every other law; the typeclass machinery
synthesises the new instance, the law set continues to
elaborate, and the conservation theorem
`total_supply_global_via_law_set` continues to hold over the
extended set with no additional proof obligation.

### 10.4 Deterministic dispute pipeline as pure Lean

`fileDispute`, `checkEvidence`, `proposeVerdict`, `applyVerdict`
are pure Lean functions over `(P : AuthorityPolicy,
es : ExtendedState, log : Log, evidence : ByteArray)`. The
theorem `checkEvidence_deterministic` (in `Disputes/Evidence.lean`)
states: any two adjudicators given the same inputs reach the
same `EvidenceVerdict`. This is what makes multi-adjudicator
quorums safe: they cannot disagree on facts, only on which
actions to sign.

Compare optimistic rollup fraud-proof games (Cannon, BoLD).
Those are interactive bisection over execution traces, and the
correctness of the result depends on both players following
the protocol. Canon's pipeline is "compute the answer, sign
the answer"; the trust model collapses to "the adjudicator
signed the deterministic output".

### 10.5 Replay protection as a kernel-level theorem

`replay_impossible` (in `Authority/SignedAction.lean`) is a
theorem that a successfully applied signed action is no longer
admissible at the post-state. `nonce_uniqueness` strengthens
this to "no two distinct admissible actions by the same signer
share a nonce". Both follow from `expectsNonce_strict_mono`
over a per-actor monotone nonce ledger.

Rollups have replay protection (per-EOA tx nonces are an EVM
feature), but it is implementation property, not a theorem
about the state machine.

### 10.6 Canonical encoding with decoder rejection of
non-canonical inputs

CBE (Canon Binary Encoding) ships with theorems like
`action_roundtrip`, `state_encode_deterministic`, and
`signInput_deterministic`. The decoder rejects unsorted map keys,
duplicate keys, and other non-canonical inputs (e.g., audit-3
amendments to `Verdict` decoding reject non-canonical signature
orderings as `nonCanonical`). This forecloses the
"two-signature-orderings-of-the-same-payload" class of attacks
that has bitten ZK rollups in the past.

### 10.7 Cross-stack equivalence fixtures

Workstream F ships 656 cross-stack fixtures (ECDSA: 128,
keccak: 104, deposit-receipt: 128, withdrawal-proof: 96,
dispute-evidence: 168, migration: 32) plus 96 mainnet-shaped
goldens. Each fixture is generated by the Lean test driver and
consumed by a Solidity test contract; CI's
`cross-stack-equivalence` job verifies byte-level equivalence
when the production keccak256 binding is linked.

The hash-binding-conditional behaviour means: when the
production keccak256 binding is *not* linked, the Lean fixture
content is FNV-derived and the Solidity cross-check explicitly
skips with a log line. When the production binding *is* linked,
all 197 Solidity tests pass with no skips. This is one of the
cleaner cross-stack verification stories in the L2 space.

### 10.8 Immutability of L1 contracts

Discussed in §6 above. No proxy, no admin, no `Pausable`. The
upgrade path is `CanonMigration`'s one-shot attested handoff.
This is closer to Bitcoin's discipline than to any production
rollup's.

### 10.9 Lex law-declaration language with manifest hashes

A high-level surface (`lexlaw`) elaborates declaratively into
`Transition` values; a `deployment` macro emits deterministic
manifest hashes that uniquely identify a deployment's law set.
`lex_diff` classifies version bumps as `patch` / `minor` /
`major` and enforces refinement-proof discipline. `lex_format`
canonicalises clause order so two semantically equivalent law
declarations have the same byte representation.

This is governance tooling for a system whose rules are
themselves programs. The rollup analogue would be a governance
process for upgrading contracts; Canon's is a governance process
for upgrading *the language in which the rules are written*.

### 10.10 Actor-scoped local policies with structural exemption

Workstream LP shipped `LocalPolicy` (deny tags / require
recipient ∈ set / cap amount) constraining an actor's *own*
outgoing actions, with a structural meta-action exemption that
prevents lockout. `localPolicy_meta_action_independent` (in
`Authority/SignedAction.lean`) is the theorem that meta-actions
are exempt from the actor's own policy, mechanising the
no-lockout property at the type level.

Smart-contract analogues (per-account allowlists, capability
guards) exist in EVM rollups but rely on contract correctness
rather than kernel-level enforcement.

---

## 11. Honest costs and limitations

A balanced analysis names what Canon trades away.

### 11.1 EVM incompatibility is a huge cost

There is no Solidity-to-Canon compiler, no MetaMask-to-Canon
transaction support beyond the EIP-712 envelope, no
contract-deployment story analogous to `eth_sendTransaction`
with bytecode. Users wanting to interact with Canon as if it
were Ethereum need to learn a new mental model and (for
non-trivial application logic) deploy laws via the Lex
governance process rather than as user transactions.

Workstream E.5 acknowledges this: "A Canon transaction signed
with a standard Ethereum wallet (MetaMask, hardware wallet,
etc.) is admissible without any custom signing software on the
user's side" — but the *transaction* in question is a Canon
`SignedAction`, not arbitrary Solidity bytecode. Wallets see a
typed EIP-712 envelope; what they sign is a Canon action, not
an EVM call.

This is a deliberate trade-off, but it is a real one. Ecosystem
network effects favour EVM compatibility, and any system that
gives that up has to make up the value elsewhere.

### 11.2 Single-sequencer / single-attestor architecture

The MVP runs a single sequencer with a published attestation
key (`docs/ethereum_integration_plan.md` §2.2 non-goal #7).
Multi-attestor and leader-election schemes are deferred.
Censorship resistance is a deployment concern, not a kernel
property (Genesis Plan §10.2). This is structurally similar to
where production rollups were in 2021 – 2022, but is two to
three years behind the *direction* of decentralisation that
the rollup landscape is moving in.

The dispute pipeline mitigates this for safety: a misbehaving
sequencer can be challenged on L1 with a `signatureInvalid`,
`nonceMismatch`, or `doubleApply` claim. But for liveness, the
single sequencer is a single point of failure.

### 11.3 Lean compiler in the TCB

The Genesis Plan acknowledges this as Open Research Question
§15.6 ("Mechanised Proof of Refinement to Extracted Code"):
Lean's compilation strategy is not itself formally verified
end-to-end. The closest current thing is "soundness of the
type theory plus careful manual review of the runtime". A
proof that the extracted code preserves the kernel's
denotational semantics would close this gap; today, it doesn't.

This means Canon's mathematical guarantees apply to the *Lean
source*, not directly to the *compiled binary*. The gap is
small relative to "trust the entire EVM and the Solidity
compiler", but it is non-zero.

### 11.4 Dispute pipeline does not bisect

Canon's dispute pipeline is "compute the deterministic answer
from the log and the evidence". This is a *one-shot* fraud
proof, not an interactive bisection game. For small to medium
logs this is fine; the verifier replays the log up to the
contested index and recomputes the precondition. For
production-scale logs (millions of entries), this approach
becomes expensive on L1, and bisection becomes the right
answer (`docs/ethereum_integration_plan.md` §2.2 non-goal #3
acknowledges this: "Bisection dispute games... is the right
answer for production-scale logs but is out of scope here").

The unstated assumption is that Canon deployments are at
"clearing system" or "identity registry" scale, not "general
DeFi" scale. For the target use cases this is acceptable. For
direct comparison to Optimism's TPS-headline workload, it is
not.

### 11.5 ZK is deferred

The MVP is optimistic only (§2.2 non-goal #2). ZK proofs of
`apply_admissible` are a candidate Phase 8 deliverable.
The Open Research Question §15.3 names two paths:
(a) compile kernel proof terms into ZK circuits (research-grade),
or (b) design a parallel circuit-friendly kernel and prove
observational equivalence to the Lean kernel. Neither is
implemented today.

This means Canon does not currently offer the "fast withdrawal
via ZK proof" UX that zkSync / Polygon zkEVM / Scroll users
expect. Withdrawals wait out the dispute window, just like
optimistic rollups.

### 11.6 Decidability discipline is not type-enforced

The Genesis Plan's Open Research Question §15.1 is explicit:
the kernel admits any `Prop`-valued precondition, but
`step_impl` requires `Decidable (t.pre s)`. A clean way to
enforce decidability at the law-boundary type level (e.g., a
`DecidableTransition` newtype bundling the instance) is
unsolved. Today, decidability is a *discipline* — laws are
expected to define `decPre := fun _ => inferInstance` — not a
type-level guarantee. A law-author who writes a non-decidable
precondition will get a compile error somewhere downstream,
but not at the law's declaration site.

### 11.7 Hash and verify primitives are opaque

`Verify` and `hashBytes` are `opaque` declarations whose
correctness is a *trust assumption*. The kernel's authority
and replay guarantees are conditional on EUF-CMA security of
the signature scheme; the withdrawal-proof soundness theorem
is conditional on `CollisionFree H`. Production deployments
discharge these via the Rust adaptor crates
(`canon-verify-secp256k1`, `canon-hash-keccak256`), which are
deferred to a follow-up PR.

This is honest and standard practice in formal verification,
but it does mean that Canon's claim is not "the system is
mathematically correct, full stop" — it is "the system is
mathematically correct, *given* standard cryptographic
assumptions". Rollups have the same conditional claims
(ECDSA + Keccak); Canon is no worse off but no better off.

### 11.8 No native concurrency, no native sharding

The single-threaded kernel model (§11.5) is a deliberate
correctness simplification. Genesis Plan §15.4 names
cross-shard atomicity as an open question. There is no
short-term path to "Solana-scale throughput on Canon"; the
design choice is to optimise for a different axis.

### 11.9 Bridge architecture inherits rollup risks

Canon's bridge has all the standard rollup attack surfaces:
sequencer censorship, attestor key compromise, withdrawal
proof construction bugs (mitigated by the Lean proofs but
still a non-zero deployment concern), L1 contract bugs (high
cost given immutability), bridge accounting drift between L1
and L2 (mitigated by `BridgeAccountingMismatch` revert path
and `apply_admissible_with_eq_kernelOnlyApply` cross-layer
agreement theorem). The mitigations are arguably stronger than
typical rollup practice, but the threat surface is the same
shape.

---

## 12. Is this a decent path to explore?

Returning to the original question.

### 12.1 If the question is "should we build another Ethereum L2?"

No. The L2 landscape is saturated; the marginal value of one
more EVM rollup is near zero. Canon is not an EVM rollup and
should not be evaluated as one.

### 12.2 If the question is "should we build a state machine
whose invariants are machine-checked end-to-end?"

Yes, and Canon is one of the better-executed attempts at this
in the public ledger space. The technical execution is solid:

- The TCB is real (~200 lines), not a marketing claim.
- The theorems are sorry-free with audited axiom sets.
- The L1 contracts are immutable, not gestured-at.
- The cross-stack equivalence fixtures exist (656 inputs).
- The typeclass firewalls actually firewall (`mint` will not
  compile into a `ConservativeLawSet`).

The intellectual reference class is seL4, CompCert, IronFleet,
F* projects like Project Everest. Canon is *not* doing the same
thing as Optimism; it is doing a different thing that happens
to have an Optimism-shaped Ethereum adapter.

### 12.3 If the question is "should we build a chain whose
governance is structurally constrained?"

Yes, this is one of Canon's more philosophically interesting
contributions. The immutable L1 contracts plus `CanonMigration`
attested-handoff plus Lex `major`-bump discipline together
form a governance model that is mathematically constrained, not
operationally constrained. The closest production analogue is
Bitcoin (consensus changes are hard forks; soft forks are
disciplined by the BIP process). Among "smart-contract-bearing
chains", Canon's discipline is unusual.

Whether this is the *right* governance model depends on
deployment-specific values: a system that wants to be patchable
in hours should not adopt Canon's discipline; a system that
treats every rule change as a constitutional event should.

### 12.4 What would change my mind?

Honestly: a credible end-to-end demonstration. The Lean side
is impressively complete; the Solidity side is comprehensively
mirrored; the cross-stack fixtures pass. What is *not* yet
demonstrated is a public-testnet acceptance run with a real
user depositing real ETH, transacting via MetaMask, withdrawing,
and the dispute pipeline firing on a real misbehaviour
scenario. The acceptance script (`docs/ethereum_integration_plan.md`
§2.3) is documented but not yet executed end-to-end on Sepolia
or Holesky.

If that acceptance run succeeds — particularly the dispute
pipeline firing and producing a verdict that the L1 contract
accepts — Canon will have demonstrated something genuinely new
in this space. If it fails or surfaces unexpected complexity,
the system is still valuable as a research artefact, but the
"production-ready" framing would need to soften.

### 12.5 Are you re-inventing the same thing?

The *bridge* is a conventional optimistic rollup bridge with
some sharper edges (immutable contracts, deterministic dispute
pipeline, cross-stack equivalence). If you measure novelty by
the bridge alone, you would say "yes, mostly".

The *kernel and the layers above it* are not a conventional
anything. The trusted core, the typeclass firewalls, the Lex
law-declaration language, the deterministic dispute pipeline
as pure Lean, the three-axiom proof discipline — these have
no production analogue. They are closer to research-stage
formal verification projects (seL4, CompCert) than to anything
in the L2 landscape.

The right framing is: **Canon is a formally verified state
machine that ships an Ethereum bridge, not an Ethereum L2 that
happens to use formal methods**. The bridge is the wrapper;
the kernel is the contribution. Evaluating Canon as if the
bridge were the headline is reading the project backwards.

---

## 13. Recommendations for evaluating this further

If you want to assess this seriously, the steps are roughly:

1. **Read `LegalKernel/Kernel.lean` end-to-end.** It is the
   §4.12 listing in literal form, ~393 lines including comments,
   readable in 30 minutes. Confirm in your own head that the
   four headline theorems say what they claim to say.

2. **Run `lake exe count_sorries` and `#print axioms` on a few
   key theorems.** Verify the trust claims experimentally.

3. **Pick a law** (`LegalKernel/Laws/Transfer.lean` is the
   canonical one). Trace its precondition, its `apply_impl`,
   its `IsConservative` instance. See how the typeclass
   firewalls compose at the law-set level
   (`LegalKernel/Conservation.lean`).

4. **Read `LegalKernel/Bridge/WithdrawalRoot.lean`** for the
   non-trivial bridge cryptography (SMT, keccak256 binding,
   `verifyProof_complete` and `verifyProof_sound`). Compare
   to the Solidity port (`solidity/src/lib/SmtVerifier.sol`).

5. **Read `LegalKernel/Disputes/Verdict.lean`** for the Stage-3
   witness discipline and the Option-C totality theorem.

6. **Read `solidity/src/contracts/CanonBridge.sol`** for the
   L1 contract. Verify that the contract is immutable (no
   `initialize`, no proxy, no `onlyOwner`); verify that the
   `revertToPriorRoot` floor+ceiling design is what it claims
   to be.

7. **Read `solidity/src/contracts/CanonMigration.sol`** for the
   recovery model. Confirm the single-shot, predecessor-binding,
   grace-window invariants.

8. **Compare** to Optimism's `OptimismPortal` +
   `L2OutputOracle` + dispute game contracts, and to zkSync's
   `Verifier` + diamond-proxy contracts. Note the differences in
   what is mutable, what is auditable, and what is
   pre-committed at deployment.

After that, you will have a more grounded view than this
document can give you, and you will be in a position to
evaluate whether the trade-offs Canon makes are the ones you
want for whatever deployment you have in mind.

---

## 14. Closing

Canon is not "designing the same thing all over again". The
*bridge* is conventional; the *kernel* is not. Whether the
direction is decent depends entirely on whether you value the
properties Canon delivers (small TCB, no upgrade authority,
typeclass-firewalled invariants, deterministic dispute
pipeline, three-axiom proof discipline) above the properties
it trades away (EVM compatibility, throughput, single-step
fraud proofs, native concurrency, runtime-installable code).

For "Ethereum at scale" use cases, the trade is bad. For
"constitutional state machine" use cases — clearing systems,
identity registries, regulatory compliance, anywhere that
"the rules are correct" matters more than "the rules are
fast" — the trade is good, and Canon is one of very few
serious attempts at it.

The path is worth exploring. The path is also not the path
most of the L2 ecosystem is on, and that is a feature of the
design, not a bug.
