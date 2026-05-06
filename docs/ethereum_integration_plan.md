<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

# Canon-on-Ethereum: Minimum Viable Integration — Workstream Plan

This document plans the engineering effort needed to deploy Canon as
a proof-carrying optimistic rollup anchored to Ethereum L1.  It is a
roadmap, not a specification; the formal design lives in the Genesis
Plan amendment that workstream G.1 is charged with drafting.

The plan deliberately constrains itself to a *minimum viable*
integration: the smallest set of changes that lets a real Ethereum
user deposit ETH (or an ERC-20), execute a Canon transaction, and
withdraw the result back to L1, with on-chain dispute resolution
backed by the existing Phase-6 fraud-proof pipeline.

## Status

  * **Drafted on branch:** `claude/ethereum-kernel-integration-HMexY`.
  * **Phase prefix:** `E` (Ethereum) — workstreams labelled `A.1`,
    `B.2`, …, `G.5` to disambiguate from the Genesis-Plan
    `Phase 1`/`Phase 2`/… numbering.  This phase is parallel to,
    not a successor of, the Genesis-Plan Phase 7.
  * **Build-posture target:** `lake build`, `lake test`,
    `lake exe count_sorries`, `lake exe tcb_audit`, and
    `lake exe stub_audit` all green throughout; no new sorries; no
    new axioms; no expansion of the kernel TCB.

## Executive summary

The MVP makes Canon usable by any Ethereum wallet against any
EVM chain.  Concretely:

  * **Seven workstreams**, twenty-eight work units (3 + 3 + 6 + 3
    + 4 + 4 + 5), ≈ 8 wall-clock weeks with two engineers
    (≈ 5 weeks with four).
  * **Three new `Action` constructors** (`deposit`, `withdraw`,
    `registerIdentity`) at frozen indices 12, 13, 14, plus two new
    `Event` constructors at indices 9, 10.  Constructor indices
    are append-only; once landed they are immutable.
  * **One new `ExtendedState` field** (`bridge : BridgeState`),
    holding the consumed-deposit set and pending withdrawals.
    `ExtendedState` is non-TCB; the field addition does not
    expand the kernel.
  * **Two extern-linked Rust adaptors**: ECDSA secp256k1
    (`canon_verify`) and keccak256 (`canon_hash_bytes`), wiring
    Canon's existing `Verify` opaque and `hashBytes` swap-point
    to production-grade implementations.
  * **Four Solidity contracts**: `CanonBridge.sol`,
    `CanonDisputeVerifier.sol`, `CanonIdentityRegistry.sol`,
    `CanonSequencerStake.sol`.  Behind transparent proxies; a
    3-of-5 Safe multisig holds the upgrade key with a 7-day
    timelock.
  * **Forty-one proof obligations** enumerated in §12, every one
    a full Lean proof under the canonical three-axiom set.  A
    handful (the EIP-712 wrap and the Merkle-soundness theorems)
    are stated under a `keccak_collision_free` hypothesis (a
    `Prop` parameter, not an axiom); the rest are unconditional.
  * **One headline composition theorem**, `bridge_deployment_safety`
    (§12.13), bundling per-resource bridge accounting, per-actor
    nonce monotonicity, once-registered-always-registered, and
    first-time-registration discipline into a single
    four-conjunct `And` proposition the L1 contracts rely on.

The architecture deliberately avoids any kernel TCB change: the
two-reviewer §13.6 gate applies only to G.1 (the Genesis Plan
amendment).  Every other WU lands under the standard one-reviewer
discipline.

## Table of contents

  1. [Purpose and scope](#1-purpose-and-scope)
  2. [Goals and non-goals](#2-goals-and-non-goals)
  3. [Architecture overview](#3-architecture-overview)
  4. [Design principles](#4-design-principles)
  5. [Workstream A — cryptographic adaptors](#5-workstream-a--cryptographic-adaptors)
  6. [Workstream B — identity and authority](#6-workstream-b--identity-and-authority)
  7. [Workstream C — bridge laws](#7-workstream-c--bridge-laws)
  8. [Workstream D — withdrawal proofs](#8-workstream-d--withdrawal-proofs)
  9. [Workstream E — Solidity contracts](#9-workstream-e--solidity-contracts)
  10. [Workstream F — cross-stack verification](#10-workstream-f--cross-stack-verification)
  11. [Workstream G — documentation and amendment](#11-workstream-g--documentation-and-amendment)
  12. [Mathematical correctness obligations](#12-mathematical-correctness-obligations)
  13. [Sequencing and dependencies](#13-sequencing-and-dependencies)
  14. [Acceptance gates](#14-acceptance-gates)
  15. [Risks and mitigations](#15-risks-and-mitigations)
  16. [Out of scope (post-MVP)](#16-out-of-scope-post-mvp)
  17. [Glossary](#17-glossary)

---

## 1. Purpose and scope

Canon (Phases 0–6, complete as of the parent branch) is a
proof-carrying state-transition system specified for the security
model of a sequenced, signed, append-only log with a per-actor
nonce ledger and a four-stage dispute pipeline.  Ethereum L1
supplies a settlement layer with economic finality, a public
identity layer (ECDSA secp256k1 keys, optionally EIP-1271
smart-contract signers), and a permissionless dispute substrate
(a Solidity contract anyone can call).

The architectural fit between the two systems is unusually clean:
Canon's existing primitives map almost 1-to-1 onto rollup
primitives (see §3 for the alignment table).  The MVP is therefore
not a *reimplementation* but a *deployment*: the kernel and laws
stay untouched, and the bridge surface is a new non-TCB module set
that plugs into existing typeclass and opaque slots.

This document plans the engineering effort to land that deployment.
It enumerates the workstreams (§5–§11), the proof obligations each
workstream owes (§12), the dependency DAG (§13), and the acceptance
gates each work unit must clear before merging (§14).

## 2. Goals and non-goals

### 2.1 Goals (what shipping the MVP means)

  1. **A real ETH or ERC-20 token can be deposited** by an EOA via
     a single L1 transaction; the funds appear in the depositor's
     Canon balance within one settlement window.
  2. **A Canon transaction signed with a standard Ethereum wallet**
     (MetaMask, hardware wallet, etc.) is admissible without any
     custom signing software on the user's side.  This requires the
     signing-input round-tripping cleanly through EIP-712.
  3. **A Canon withdrawal can be redeemed on L1** by presenting a
     Merkle proof of inclusion in a finalised state root.
  4. **A misbehaving sequencer is provably challengeable on L1**
     using the existing Phase-6 dispute pipeline — at minimum, the
     `signatureInvalid`, `nonceMismatch`, and `doubleApply` claim
     variants must round-trip through the L1 dispute verifier.
  5. **All Phase-0–6 type-level guarantees survive verbatim.**
     `lake build`, `lake test`, `lake exe count_sorries`,
     `lake exe tcb_audit`, and `lake exe stub_audit` continue to
     pass.  `#print axioms` on every kernel theorem returns
     exactly `[propext, Classical.choice, Quot.sound]`.
  6. **The trust-assumption inventory is documented** in
     `docs/extraction_notes.md` §2 — every new opaque or
     `@[extern]` dependency lists its security assumption.

### 2.2 Non-goals (deferred to v2 or later)

  1. **Widening `ActorId` from `UInt64` to a 20-byte address type.**
     A registry indirection (workstream B.1) suffices for the MVP;
     widening is a kernel TCB change requiring two reviewers and
     a §13.6 Genesis-Plan amendment.
  2. **ZK proofs of `apply_admissible`.**  The MVP is optimistic
     only.  ZK extension is a candidate Phase 8 deliverable.
  3. **Bisection dispute games.**  The MVP uses one-shot fraud
     proofs over a bounded log prefix; bisection is the right
     answer for production-scale logs but is out of scope here.
  4. **Account abstraction (ERC-4337).**  EIP-1271 is in scope
     (workstream A.1); ERC-4337's UserOperation envelope is not.
  5. **Cross-rollup interop.**  `deploymentId` already gives
     cross-rollup replay rejection; bidirectional cross-rollup
     bridges are not in the MVP.
  6. **Native ETH gas accounting.**  The MVP's economic model is
     "the sequencer is paid out-of-band"; on-chain gas markets
     and fee burning are post-MVP.
  7. **Sequencer decentralisation.**  The MVP runs a single
     sequencer with a published attestation key; rotated /
     multi-attestor / leader-election schemes are post-MVP.

### 2.3 The minimum-viable acceptance test

The MVP is "done" when the following acceptance script passes
end-to-end on a public Ethereum testnet (Sepolia or Holesky):

  1. Alice deposits 1 ETH to `CanonBridge.sol`.
  2. The Canon sequencer ingests the deposit event and credits
     1 ETH to Alice's Canon address.
  3. Alice signs an `Action.transfer 1_eth Bob 0.5_eth` via
     MetaMask using the EIP-712 envelope.
  4. The sequencer applies the transfer; Bob's Canon balance shows
     0.5 ETH.
  5. Bob signs an `Action.withdraw 1_eth Bob 0.5_eth` via MetaMask.
  6. The sequencer applies the withdrawal; the post-state root is
     submitted to `CanonBridge.sol`.
  7. After the dispute window closes, Bob calls
     `CanonBridge.withdrawWithProof(...)` and receives 0.5 ETH at
     his L1 address.

Each of those seven steps maps onto a closed workstream below.

## 3. Architecture overview

### 3.1 Alignment table (Canon ↔ rollup primitives)

| Canon primitive                           | Defined in                              | Ethereum / rollup role                         |
|-------------------------------------------|-----------------------------------------|------------------------------------------------|
| `Verify` opaque                           | `Authority/Crypto.lean:138`             | ECDSA secp256k1 (with EIP-1271 dispatch)       |
| `Runtime.Hash.hashBytes` (FNV-1a-64)      | `Runtime/Hash.lean`                     | keccak256 (linked via `@[extern]`)             |
| `signingInput` with `deploymentId`        | `Encoding/SignInput.lean` + Audit-3.4   | EIP-712 envelope; cross-chain replay rejection |
| `KeyRegistry`                             | `Authority/Identity.lean`               | Mirror of `CanonIdentityRegistry.sol`          |
| `Snapshot` + `AttestedSnapshot`           | `Runtime/Snapshot.lean`, Audit-3.2      | Periodic state-root commit on L1               |
| `Disputes` pipeline (Phase 6)             | `LegalKernel/Disputes/`                 | One-shot fraud proofs in `CanonDisputeVerifier.sol` |
| `IsConservative` / `IsMonotonic`          | `Conservation.lean`                     | Bridge-safety invariants                       |
| `replay_impossible` / `nonce_uniqueness`  | `Authority/SignedAction.lean`           | Per-actor anti-replay; matches EOA tx-nonce    |
| CBE canonicality + `*_encode_deterministic` | `Encoding/State.lean`                 | Byte-stable Merkle leaves for state roots      |
| `apply_admissible_with_eq_kernelOnlyApply` | Audit-3.6                              | Off-chain ↔ on-chain coherence theorem         |
| `VerdictPassedStage3` witness             | Phase-6 Option-C / `Disputes/Verdict.lean` | Type-level Stage-3 enforcement on L1 finalisation |

### 3.2 Layered diagram

```
┌────────────────────────────────── Ethereum L1 ──────────────────────────────────┐
│                                                                                 │
│   ┌───────────────────────┐     ┌───────────────────────────┐                   │
│   │  CanonBridge.sol      │     │  CanonIdentityRegistry    │                   │
│   │    deposit(token, a)  │     │    register(addr, pk)     │                   │
│   │    submitStateRoot()  │     │    revoke(addr)           │                   │
│   │    withdrawWithProof  │     │    emits events           │                   │
│   └───────────────────────┘     └───────────────────────────┘                   │
│                                                                                 │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │  CanonDisputeVerifier.sol                                               │   │
│   │    fileDispute(claim, evidenceBlob)    — mirrors Phase-6 Stage 1        │   │
│   │    checkEvidence(...)                  — ports Stage 2 verifiers        │   │
│   │    finalizeUpheld(verdict, sigs)       — mirrors applyVerdict           │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
└────────────┬────────────────────────────────────────────────────┬───────────────┘
             │ deposit / register / revoke events                 │ state roots,
             │                                                    │ disputes
┌────────────┴────────────────────────────────────────────────────┴───────────────┐
│                       Canon Runtime (sequencer / replica)                       │
│                                                                                 │
│   ┌──────────────────────────────┐    ┌─────────────────────────────────────┐   │
│   │  L1 ingestor                 │    │  L1 publisher                       │   │
│   │  (L1 event log -> Action)    │    │  (snapshot -> state-root tx)        │   │
│   └──────────────────────────────┘    └─────────────────────────────────────┘   │
│                                                                                 │
│   ┌─────────────────────────── extern bindings ─────────────────────────────┐   │
│   │    Verify  := ECDSA secp256k1 (low-s canonical)        [WU A.1]         │   │
│   │    Hash    := keccak256                                [WU A.2]         │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│   ┌───────────────────── Phase-5 runtime (untouched) ───────────────────────┐   │
│   │   processSignedAction · bootstrap · replay · snapshot                   │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│   ┌──────────────── Phase-6 dispute pipeline (untouched) ───────────────────┐   │
│   │   fileDispute · checkEvidence · proposeAndApplyVerdict                  │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│   ┌───────────────── Phase-0–4 kernel + laws (TCB unchanged) ───────────────┐   │
│   │   apply_admissible_with · step_impl · IsConservative / IsMonotonic      │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│   ┌───────────────────────── new bridge layer ──────────────────────────────┐   │
│   │   Laws.deposit · Laws.withdraw · Bridge.AddressBook · Bridge.Ingest     │   │
│   │   Bridge.WithdrawalRoot · Bridge.Eip712 · Bridge.Conservation           │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Trust-boundary inventory

The MVP introduces the following new trust assumptions, all
cryptographic or economic, none Lean-axiomatic:

  1. **EUF-CMA on ECDSA secp256k1** (existing for Phase 3, made
     concrete by workstream A.1).
  2. **Collision resistance of keccak256** (existing for Audit-3.1
     in skeletal form, made concrete by workstream A.2).
  3. **Ethereum L1 finality** at the sequencer's chosen depth
     (configurable; default 64 blocks ≈ 12 minutes post-Casper).
  4. **Solidity contract correctness** for `CanonBridge.sol`,
     `CanonDisputeVerifier.sol`, `CanonIdentityRegistry.sol`
     (workstream E; mitigated by F.1 cross-stack equivalence).
  5. **EIP-1271 contract correctness** for any contract signers
     the deployment chooses to admit (workstream A.1; opt-in).

Every new assumption is enumerated in `docs/extraction_notes.md`
§2 by workstream G.4.

## 4. Design principles

### 4.1 The TCB never grows

`Kernel.lean` and `RBMapLemmas.lean` stay untouched.  Every WU
that is tempted to import or modify either of them is
re-architected to live in a non-TCB module.  Two-reviewer reviews
under Genesis Plan §13.6 are explicitly out of scope for the MVP;
any WU that requires one is *by definition* deferred.

### 4.2 No new axioms

Every new opaque (e.g. `eip712Wrap`) is declared `opaque`, never
`axiom`, so `#print axioms` continues to yield only the three Lean
built-ins.  Cryptographic assumptions surface as opaque-extern
bindings, not as Lean axioms.

### 4.3 Append-only constructor indices

`Action`'s frozen indices 0..11 stay frozen.  New constructors
take indices 12 (`deposit`), 13 (`withdraw`), and 14
(`registerIdentity`; see §6.3 design note).  `Event`'s frozen
indices 0..8 stay frozen; new constructors take indices 9
(`withdrawalRequested`) and 10 (`depositCredited`).  Once landed,
these indices are immutable forever — re-grouping is forbidden
under the same rule that governs the Phase-3 / Phase-6 indices.

### 4.4 Type-level firewalls preserved

The new bridge laws ship explicit `IsMonotonic` instances or
explicit non-monotonicity witnesses.  `MonotonicLawSet`
constructions involving the bridge are gated by the witnesses, so
deployments that want strict supply-non-decrease can refuse the
`withdraw` law at the type level.

### 4.5 Determinism end-to-end

Every new function from `(L1 event) → (Canon SignedAction)` is a
pure function.  Where ECDSA is used to author bridge-emitted
actions (B.3), the runtime adaptor uses RFC 6979 deterministic
ECDSA to keep test vectors stable.

### 4.6 Mathematical correctness is non-negotiable

Every WU's exit criterion includes a list of theorems that *must*
be proved before merge — not as `sorry`-bearing scaffolds, not as
admitted axioms, not as `unsafe` declarations, but as full Lean
proofs whose `#print axioms` output is the canonical built-in set.
Workstream-level theorem inventories appear in §12.

### 4.7 No process markers in identifier names

Per the existing CLAUDE.md rule, new declaration names describe
content (`deposit_isMonotonic`, `bridge_supply_account`), never
provenance (no `eth_`, `mvp_`, `wu_`, `phase_e_` tokens in
identifier names).  Process markers may appear in docstrings and
commit messages.

## 5. Workstream A — cryptographic adaptors

This workstream replaces the two opaque/fallback primitives
(`Verify`, `hashBytes`) with production Ethereum-native
implementations linked via `@[extern]`.  Both are runtime-side
deliverables; the Lean side gains tests and stability theorems
but no new TCB.

### 5.1 WU A.1 — ECDSA secp256k1 verify with low-s canonicalisation

**Owner:** runtime (Rust); **Reviewer count:** 1; **Depends on:** none.

**Deliverable.**  A Rust crate `runtime/canon-verify-secp256k1`
exporting one C-ABI symbol matching the
`Authority/Crypto.lean:138` opaque signature:

```c
extern "C" bool canon_verify(
  const uint8_t* pk,  size_t pk_len,
  const uint8_t* msg, size_t msg_len,
  const uint8_t* sig, size_t sig_len);
```

The implementation:
  1. Parses `pk` as a 33-byte compressed or 65-byte uncompressed
     secp256k1 point; rejects malformed input with `false`.
  2. Parses `sig` as a 65-byte `(r ‖ s ‖ v)` Ethereum-style
     signature; rejects malformed input with `false`.
  3. **Rejects high-s signatures** (the canonical EIP-2 / BIP-62
     constraint `s ≤ n/2`).  This blocks the malleability vector
     where two different `(r, s)` pairs verify the same message
     under the same key.
  4. Runs `secp256k1_ecdsa_verify` (via the audited
     `libsecp256k1`).
  5. Returns the boolean result.

**Lean-side stability tests** (`Test/Bridge/VerifyAdaptor.lean`):

  * `verifyAdaptor_accepts_canonical : Verify pk msg sig = true`
    on a hardcoded `(pk, msg, sig)` triple lifted from a real
    Ethereum testnet transaction.
  * `verifyAdaptor_rejects_high_s : Verify pk msg sigHighS = false`
    using the same triple with `s' := n - s`.
  * `verifyAdaptor_rejects_corrupt : Verify pk msg' sig = false`
    when `msg'` differs from `msg` by one byte.

**Acceptance criteria.**

  * 100 / 100 passes on a property-based corpus of randomly
    generated `(seed, msg)` pairs (sign with seed-derived key,
    verify, expect `true`); seeds are reproducible via the
    `CANON_PROPERTY_SEED` env var (`Audit-3.9`).
  * 0 / 100 false-accepts on a corpus of random `(pk, msg, sig)`
    triples (none are real signatures; all should reject).
  * Cross-check against `geth`'s `crypto.VerifySignature` on a
    100-signature golden file.

**Threat-model note.**  EUF-CMA on secp256k1 is the cryptographic
assumption that backs every signature-derived guarantee in Phase 3
(`replay_impossible`, `nonce_uniqueness`).  The Phase-3 proofs do
not depend on the assumption (they reason purely about nonces);
the assumption is what closes the gap between "the proofs hold
for any `Verify`" and "the proofs hold for the real signature
scheme".

### 5.2 WU A.2 — keccak256 hash adaptor

**Owner:** runtime (Rust); **Reviewer count:** 1; **Depends on:** A.1
(shares Rust crate skeleton).

**Deliverable.**  A Rust crate `runtime/canon-hash-keccak256`
exporting the three C-ABI symbols already documented in
`docs/abi.md §11` (Audit-3.1):

```c
extern "C" void canon_hash_bytes (const uint8_t* in, size_t len,
                                  uint8_t out[32]);
extern "C" void canon_hash_stream(/* CBE stream input */);
extern "C" void canon_hash_identifier(uint8_t out[32]);
```

`canon_hash_identifier` returns the 32-byte ASCII identifier
`"keccak256/EVM-compatible/v1\0\0\0\0"` so deployments can
distinguish hash schemes at runtime.

**Lean-side stability tests** (`Test/Bridge/HashAdaptor.lean`):

  * `hashAdaptor_matches_l1_keccak : hashBytes input₀ =
    expected₀` for a 32-tuple golden file lifted from
    `keccak256.spec` test vectors and from real Ethereum block
    headers.
  * `hashAdaptor_deterministic` — already proved generically;
    re-asserted at the value level for the new binding.
  * `hashAdaptor_thirty_two_byte_output` — output length is 32
    for every input (the Audit-3.1 size invariant).

**Acceptance criteria.**

  * 32 / 32 goldens match.
  * `canon-replay --allow-fallback-hash` is *not* required to be
    set; the binary refuses to start without the keccak256
    binding.

**Threat-model note.**  Collision resistance of keccak256 is the
cryptographic assumption that backs every state-root guarantee
(`replicaFromSnapshot`'s seed-hash check, the dispute pipeline's
log-prefix-replay check).  No Lean theorem depends on the
*structure* of keccak256; the assumption only enters at the
deployment boundary.

### 5.3 WU A.3 — EIP-712 sign-input wrapping

**Owner:** Lean + runtime; **Reviewer count:** 1; **Depends on:**
A.1 (verify must understand wrapped form), A.2 (keccak256 used
inside the wrap).

**Deliverable.**  A new module `LegalKernel/Bridge/Eip712.lean`
exporting:

```lean
namespace LegalKernel.Bridge

/-- EIP-712 domain separator for Canon-on-Ethereum.  Hashed once
    per deployment; cached in the runtime adaptor. -/
def eip712DomainSeparator (chainId : Nat) (rollupId : Nat)
                           (verifyingContract : ByteArray)
    : ByteArray

/-- Wrap a Canon `signInput` as an EIP-712 typed-structured-data
    message.  The wallet signs `\x19\x01 ‖ domainSep ‖ structHash`
    where `structHash := keccak256 (typeHash ‖ canonSignInput)`. -/
def eip712Wrap (canonSignInput : ByteArray)
                (domainSep : ByteArray) : ByteArray

end LegalKernel.Bridge
```

and the proof obligations:

```lean
/-- The wrap is injective in its message argument under a fixed
    domain separator. -/
theorem eip712Wrap_injective :
  ∀ d m₁ m₂, eip712Wrap m₁ d = eip712Wrap m₂ d → m₁ = m₂

/-- Domain separation: distinct chain / rollup / contract triples
    yield distinct domain separators. -/
theorem eip712DomainSeparator_distinguishes :
  ∀ c₁ r₁ v₁ c₂ r₂ v₂,
    (c₁, r₁, v₁) ≠ (c₂, r₂, v₂) →
    eip712DomainSeparator c₁ r₁ v₁ ≠ eip712DomainSeparator c₂ r₂ v₂

/-- The wrap is content-distinguishing across all (msg, domain)
    pairs. -/
theorem eip712Wrap_distinguishes :
  ∀ m₁ m₂ d₁ d₂, (m₁, d₁) ≠ (m₂, d₂) →
    eip712Wrap m₁ d₁ ≠ eip712Wrap m₂ d₂
```

The first two are direct corollaries of keccak256 collision
resistance plus injectivity of the prefix-concat envelope; the
third combines them.  Each gets a non-trivial Lean proof — the
keccak256 collision-resistance assumption is *not* introduced as
a Lean axiom; the theorems are stated with a hypothesis "assuming
hash_collision_resistant" and the test corpus exercises the
implication value-level.

**Acceptance criteria.**

  * The three theorems above ship without `sorry`.
  * Round-trip test: a MetaMask-produced EIP-712 signature on a
    Canon `signInput` verifies via the A.1 binding.
  * Cross-protocol distinguishability: an EIP-712-wrapped
    `signInput` produces bytes structurally distinct from
    a plain Canon `signedActionDomain`-prefixed `signInput`
    (already required by Audit-2; A.3 inherits the test).

## 6. Workstream B — identity and authority

This workstream wires Ethereum's address-based identity model into
Canon's `KeyRegistry` infrastructure without changing the kernel's
`ActorId : UInt64` abbreviation.

### 6.1 WU B.1 — `AddressBook` module

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** none.

**Deliverable.**  A new module `LegalKernel/Bridge/AddressBook.lean`:

```lean
/-- An Ethereum 20-byte address.  Represented as `BoundedNat
    (2^160)` rather than `ByteArray` so that the standard
    `Nat`-derived `compare` works directly with `Std.TreeMap`
    (no custom `Ord ByteArray` instance needed) and so the
    20-byte width is enforced at the type level rather than
    by a runtime check. -/
abbrev EthAddress : Type := BoundedNat (2^160)

structure AddressBook where
  /-- Mapping from Ethereum 20-byte addresses to Canon ActorIds. -/
  forward  : Std.TreeMap EthAddress ActorId compare
  /-- Inverse mapping for log-extraction.  Maintained as the
      key-by-key inverse of `forward`; the `addressBook_invariant`
      below pins the relationship at the type level. -/
  reverse  : Std.TreeMap ActorId EthAddress compare
  /-- The next `ActorId` to assign on first-time registration.
      Strictly monotonic; never decreases. -/
  nextActorId : ActorId

namespace AddressBook
def empty : AddressBook
def lookup    (b : AddressBook) (addr : EthAddress)  : Option ActorId
def lookupRev (b : AddressBook) (id   : ActorId)     : Option EthAddress
def assign    (b : AddressBook) (addr : EthAddress)  : AddressBook × ActorId
end AddressBook
```

with theorems:

```lean
theorem addressBook_invariant (b : AddressBook) :
  ∀ addr id, b.lookup addr = some id ↔ b.lookupRev id = some addr

theorem assign_fresh_actorId :
  ∀ b addr, b.lookup addr = none →
    let (b', id) := b.assign addr
    b'.lookup addr = some id ∧ b.nextActorId ≤ b'.nextActorId

theorem assign_idempotent_for_known :
  ∀ b addr id, b.lookup addr = some id →
    let (b', id') := b.assign addr
    b' = b ∧ id' = id
```

**Acceptance criteria.**

  * The three theorems above ship without `sorry`.
  * `Test/Bridge/AddressBook.lean` covers: empty / single /
    duplicate / collision (never collide because IDs are
    monotonic) / serialisation round-trip.
  * The module imports only `Std.Data.TreeMap` and
    `LegalKernel.Kernel`; no kernel-TCB imports beyond those
    already on the allowlist.

### 6.2 WU B.2 — L1-event ingestor for identity events

**Owner:** Lean + runtime; **Reviewer count:** 1; **Depends on:** B.1.

**Deliverable.**  A new module `LegalKernel/Bridge/Ingest.lean`
defining an inductive of L1 events Canon ingests:

```lean
inductive L1Event
  | identityRegistered (addr : EthAddress) (pk : PublicKey)
                        (blockNum : Nat) (logIdx : Nat)
  | identityRevoked    (addr : EthAddress) (blockNum : Nat) (logIdx : Nat)
  | depositInitiated   (addr : EthAddress) (resource : ResourceId)
                        (amount : Amount)  (receiptHash : ByteArray)
                        (blockNum : Nat)   (logIdx : Nat)
  deriving Repr, DecidableEq
```

and a deterministic translator:

```lean
/-- Translate an L1 event to its Canon-side effect.  Every L1
    event becomes either:
      - `none` (event ignored: e.g. duplicate-receipt deposit),
      - `some sa` (one bridge-authored `SignedAction` to feed
                   into `processSignedAction`).
    Identity events compile to a `SignedAction` carrying an
    `Action.replaceKey`; deposits compile to `Action.deposit`. -/
def ingest (b : AddressBook) (e : L1Event)
    : AddressBook × Option SignedAction

/-- Project an L1 event to the Canon address it touches.  Used
    by the per-address-commutativity theorem below. -/
def L1Event.address : L1Event → EthAddress
```

The function is pure (no `IO`), so determinism is automatic — no
theorem needed.  The non-trivial property is *order-independence*
across distinct addresses, which lets replicas consume the L1
event stream out of order:

```lean
/-- Per-address commutativity.  Independent L1 events (those
    touching distinct Ethereum addresses) compose in either
    order to the same `AddressBook`.  Same-address events are
    *not* commutative (registration-then-revocation differs from
    revocation-then-registration), so the hypothesis is necessary. -/
theorem ingest_commutes_for_distinct_addresses :
  ∀ b e₁ e₂, e₁.address ≠ e₂.address →
    let (b₁,  _) := ingest b  e₁
    let (b₂,  _) := ingest b₁ e₂
    let (b₁', _) := ingest b  e₂
    let (b₂', _) := ingest b₁' e₁
    b₂ = b₂'

/-- The emitted `SignedAction`'s signer is always the bridge
    actor (workstream B.3).  This pins the bridge's authority
    boundary at the type level. -/
theorem ingest_emits_bridge_actor_signature :
  ∀ b e sa,
    (ingest b e).snd = some sa →
    sa.signer = Bridge.bridgeActor
```

**Acceptance criteria.**

  * Both theorems above ship without `sorry`.
  * `Test/Bridge/Ingest.lean` covers all three L1 event variants
    plus the per-address commutativity case at concrete fixtures.
  * The ingestor binary (Rust adaptor) consumes a `web3.eth.Filter`
    stream against a real Ethereum node, deduplicates by
    `(blockHash, logIndex)`, and feeds the resulting `L1Event`
    list to the Lean function via FFI.

### 6.3 WU B.3 — Bridge actor reservation

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** B.1, B.2,
C.4 (which lands the new `Action.registerIdentity` constructor at
index 14; see design note below).

**Deliverable.**  Reserves `ActorId 0` as the *bridge actor* — the
authority under which all L1-derived Canon actions are signed.
The bridge actor's public key is set at deployment time and is
*not* rotatable except via a dedicated governance event (out of
MVP scope).

```lean
namespace LegalKernel.Bridge
def bridgeActor : ActorId := 0

/-- The bridge actor's authority policy admits only the
    L1-derivable action variants: `registerIdentity` for first-
    time identity events (see design note), `replaceKey` for
    rotation events, and `deposit` for balance crediting.
    Everything else is rejected. -/
def bridgePolicy : AuthorityPolicy
end LegalKernel.Bridge
```

with theorems:

```lean
theorem bridgePolicy_rejects_transfer :
  ∀ a, ¬ bridgePolicy.authorized 0 (.transfer ..)
theorem bridgePolicy_rejects_withdraw :
  ¬ bridgePolicy.authorized 0 (.withdraw ..)
theorem bridgePolicy_authorizes_deposit :
  bridgePolicy.authorized 0 (.deposit ..)
theorem bridgePolicy_authorizes_registerIdentity :
  bridgePolicy.authorized 0 (.registerIdentity ..)
theorem bridgePolicy_authorizes_replaceKey :
  bridgePolicy.authorized 0 (.replaceKey ..)
```

All five theorems are direct decidable computations on the
`AuthorityPolicy.authorized` field and ship by `decide` /
`native_decide`.

**Design note: why `registerIdentity` is a separate constructor.**
The existing `Action.replaceKey actor newKey` is signed by the
*old* key (Phase-3 WU 3.10): the registry holds an existing
mapping for `actor`, and the new key replaces it.  But for an
EOA registering for the first time via L1, the Canon
`KeyRegistry` has no prior mapping — there is no old key to
sign with.

The MVP therefore introduces a new `Action.registerIdentity
(actor : ActorId) (pk : PublicKey)` constructor at frozen index 14
(workstream C.4).  Its admissibility precondition is
`KeyRegistry.lookup registry actor = none` (registration is
first-time only); its authority precondition is
`bridgePolicy.authorized bridgeActor (.registerIdentity ..)`
(only the bridge actor may register).  Subsequent rotations go
through the existing `replaceKey` machinery unchanged.

This keeps the two flows distinct at the type level, so a
deployment that wants to disable bridge-driven first-time
registration (e.g. a permissioned consortium) simply omits
`registerIdentity` from its law set.

**Acceptance criteria.**

  * The five theorems above + a `MonotonicLawSet`-compatibility
    note (the bridge actor's actions are classified per
    workstream C).
  * The bridge-actor `ActorId 0` reservation is documented in
    `docs/abi.md §12` (workstream G.3).

## 7. Workstream C — bridge laws

This workstream introduces two new `Action` constructors at frozen
indices 12 and 13, the `BridgeState` ledger that tracks consumed
deposit receipts and pending withdrawals, and the per-resource
*bridge accounting invariant* that grounds the deployment's
solvency claim.

### 7.1 WU C.1 — `BridgeState` and its embedding into `ExtendedState`

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** B.1.

**Deliverable.**  A new structure `BridgeState` and its
embedding:

```lean
namespace LegalKernel.Bridge

/-- A canonical 32-byte L1 deposit receipt hash. -/
abbrev DepositId : Type := ByteArray

/-- A monotonically-incrementing per-resource withdrawal index. -/
abbrev WithdrawalId : Type := Nat

/-- One pending L2 withdrawal, awaiting L1 redemption. -/
structure PendingWithdrawal where
  resource  : ResourceId
  recipient : EthAddress    -- where the L1 redemption pays out
  amount    : Amount
  l2Block   : Nat           -- which Canon snapshot window holds it

structure BridgeState where
  consumed    : Std.TreeMap DepositId Unit compare
  pending     : Std.TreeMap WithdrawalId PendingWithdrawal compare
  nextWdId    : WithdrawalId

end LegalKernel.Bridge
```

The embedding extends `ExtendedState` with a single new field:

```lean
structure ExtendedState where
  base     : State
  nonces   : NonceState
  registry : KeyRegistry
  bridge   : BridgeState        -- NEW field at the end
```

This is a non-TCB change (`ExtendedState` lives in
`Authority/Nonce.lean`), but it is invasive: every existing
function that pattern-matches `ExtendedState` must be rebuilt.
The discipline: every existing branch passes `bridge` through
unchanged (rfl-witness), so no proof rewriting beyond pattern
expansion is required.

**Theorems.**

```lean
/-- All Phase-3+ apply functions preserve `bridge` exactly. -/
theorem apply_admissible_with_preserves_bridge :
  ∀ vp p es sa h,
    (apply_admissible_with vp p es sa h).bridge = es.bridge
```

(The hypothesis `h : AdmissibleWith vp p es.deploymentId sa`
unrelated to bridge state.)  Proof: case-split on
`sa.action`; every existing case is `rfl`.

**Acceptance criteria.**

  * The theorem ships without `sorry`.
  * Every existing test continues to pass after the field
    addition.
  * `Test/Bridge/State.lean` covers `BridgeState` round-trip
    through CBE.

### 7.2 WU C.2 — `deposit` law

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** C.1.

**Deliverable.**  A new module `LegalKernel/Laws/Deposit.lean`
defining a balance-crediting law gated by deposit-id uniqueness:

```lean
namespace LegalKernel.Laws

/-- Credit `amount` units of `r` to `recipient`, marking
    `depositId` as consumed.  Pre-condition: `depositId` is not
    already consumed.  Implementation: `setBalance` plus
    `BridgeState.consumed.insert depositId ()`. -/
def deposit (r : ResourceId) (recipient : ActorId)
            (amount : Amount) (depositId : Bridge.DepositId)
    : Transition where
  pre s := True   -- the kernel-level pre is trivial; the
                  -- bridge-level pre lives in the `Action`-layer
                  -- compile, where it has access to `BridgeState`
  apply_impl s := setBalance r recipient
                    (getBalance r recipient s + amount) s
  decPre := fun _ => inferInstance

end LegalKernel.Laws
```

Note that `Transition.pre` cannot reference `BridgeState`
directly (it operates on `State`, not `ExtendedState`).  The
deposit-id-uniqueness check therefore lives in the
`Action`-layer compile path, alongside the existing authority-
level `apply_admissible_with` machinery.  This is the same
pattern that already governs `replaceKey` (kernel pre is trivial;
the registry mutation lives in `applyActionToRegistry`).

**Theorems.**

```lean
/-- Locality (other resources untouched). -/
theorem deposit_other_resource_untouched :
  ∀ r r' recipient amount depositId s,
    r ≠ r' →
    (Laws.deposit r recipient amount depositId).apply_impl s
       |>.balances.find? r' = s.balances.find? r'

/-- Pointwise locality (other actors untouched at the same r). -/
theorem deposit_other_actor_untouched :
  ∀ r recipient recipient' amount depositId s,
    recipient ≠ recipient' →
    getBalance r recipient'
      ((Laws.deposit r recipient amount depositId).apply_impl s)
    = getBalance r recipient' s

/-- Per-resource accounting: total supply at `r` increases by
    exactly `amount`. -/
theorem totalSupply_after_deposit :
  ∀ r recipient amount depositId s,
    totalSupply r ((Laws.deposit r recipient amount depositId).apply_impl s)
    = totalSupply r s + amount

/-- Monotonicity instance. -/
instance deposit_isMonotonic
    (r : ResourceId) (recipient : ActorId)
    (amount : Amount) (depositId : Bridge.DepositId) :
  IsMonotonic (Laws.deposit r recipient amount depositId)

/-- Explicit non-conservation witness (deposits expand supply by
    construction, so this law is *not* `IsConservative`). -/
theorem deposit_not_conservative :
  ∀ r recipient amount depositId,
    amount > 0 →
    ¬ IsConservative (Laws.deposit r recipient amount depositId)
```

The first three theorems reduce to the §4.3 balance lemmas
(`getBalance_setBalance_*`) and the §8.1 master lemma
(`totalSupply_setBalance`); their proofs are short.  The
typeclass instance follows from the third theorem.  The
non-conservation witness is the existing `mint_not_conservative`
proof shape.

**Acceptance criteria.**

  * All five theorems ship without `sorry`.
  * `Test/Laws/Deposit.lean` mirrors `Test/Laws/Mint.lean`
    case-for-case (10–12 cases).
  * `lake exe count_sorries` zero kernel-TCB hits.

### 7.3 WU C.3 — `withdraw` law

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** C.1.

**Deliverable.**  A new module `LegalKernel/Laws/Withdraw.lean`
defining a balance-debiting law gated by sufficient balance:

```lean
namespace LegalKernel.Laws

/-- Burn `amount` units of `r` from `sender`, scheduling an L1
    redemption to `recipientL1`.  Pre-condition: sender's balance
    is at least `amount`.  Implementation: `setBalance` minus
    `amount`; the `Bridge.PendingWithdrawal` record is inserted at
    the Action-layer compile path (analogous to `deposit`). -/
def withdraw (r : ResourceId) (sender : ActorId) (amount : Amount)
             (recipientL1 : Bridge.EthAddress)
    : Transition where
  pre s := getBalance r sender s ≥ amount
  apply_impl s := setBalance r sender
                    (getBalance r sender s - amount) s
  decPre := fun _ => inferInstance

end LegalKernel.Laws
```

**Theorems.**

```lean
theorem withdraw_other_resource_untouched : /- as above -/
theorem withdraw_other_actor_untouched     : /- as above -/

theorem totalSupply_after_withdraw :
  ∀ r sender amount recipientL1 s,
    getBalance r sender s ≥ amount →
    totalSupply r ((Laws.withdraw r sender amount recipientL1).apply_impl s)
    = totalSupply r s - amount

/-- Explicit non-monotonicity witness (withdraw decreases supply
    by construction). -/
theorem withdraw_not_monotonic :
  ∀ r sender amount recipientL1, amount > 0 →
    ¬ IsMonotonic (Laws.withdraw r sender amount recipientL1)

/-- Explicit non-conservation witness. -/
theorem withdraw_not_conservative :
  ∀ r sender amount recipientL1, amount > 0 →
    ¬ IsConservative (Laws.withdraw r sender amount recipientL1)
```

The locality and accounting theorems mirror C.2.  The two
negative witnesses follow `burn_not_monotonic` /
`burn_not_conservative` in proof shape.

**Acceptance criteria.**

  * All five theorems ship without `sorry`.
  * `Test/Laws/Withdraw.lean` mirrors `Test/Laws/Burn.lean`
    case-for-case (12–13 cases) plus 2 extra cases for
    insufficient-balance precondition rejection.

### 7.4 WU C.4 — `Action` constructor extension

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** C.2, C.3.

**Deliverable.**  Three new `Action` constructors at frozen
indices 12, 13, and 14:

```lean
inductive Action
  /- ... existing 0..11 ... -/
  | deposit          (r : ResourceId) (recipient : ActorId)
                      (amount : Amount) (depositId : Bridge.DepositId)
  | withdraw         (r : ResourceId) (sender : ActorId)
                      (amount : Amount) (recipientL1 : Bridge.EthAddress)
  | registerIdentity (actor : ActorId) (pk : PublicKey)
```

`registerIdentity` compiles to a kernel-level no-op (like
`replaceKey`); the registry mutation lives in the Action-layer
compile path, gated by the *first-time-only* check
`KeyRegistry.lookup registry actor = none`:

```lean
def Action.compileTransition : Action → Transition
  | /- existing 0..11 ... -/
  | .deposit  r recipient amount depositId   =>
      Laws.deposit  r recipient amount depositId
  | .withdraw r sender    amount recipientL1 =>
      Laws.withdraw r sender    amount recipientL1
  | .registerIdentity _ _                    =>
      Laws.freezeResource 0   -- kernel-level no-op
```

The Phase-3 `applyActionToRegistry` is correspondingly extended:
on `registerIdentity actor pk`, the registry is updated via
`KeyRegistry.register registry actor pk` (provided
`KeyRegistry.lookup registry actor = none`).

**Theorems.**

```lean
/-- `Action.compile_injective` extends to the new constructors.
    Proof: `congrArg CompiledAction.source` is unchanged; only
    the inductive grew. -/
theorem Action.compile_injective_extends :
  ∀ a₁ a₂, Action.compile a₁ = Action.compile a₂ → a₁ = a₂

/-- `non_replaceKey_preserves_registry` extends to deposit and
    withdraw (neither mutates the registry). -/
theorem non_replaceKey_preserves_registry_extends :
  ∀ vp p es sa h,
    (∀ a' newKey, sa.action ≠ .replaceKey a' newKey) →
    (apply_admissible_with vp p es sa h).registry = es.registry
```

Both theorems extend existing ones; the deposit / withdraw
branches close by `rfl` since their `apply_impl` does not touch
the registry.

The CBE encoder (`Encoding/Action.lean`) gains two new
constructor branches at indices 12 and 13:

```lean
def Action.encode : Action → Encoding.Stream
  | /- existing ... -/
  | .deposit r recipient amount depositId =>
      [12]  -- constructor tag
      ++ encode r ++ encode recipient ++ encode amount
      ++ encode depositId
  | .withdraw r sender amount recipientL1 =>
      [13]
      ++ encode r ++ encode sender ++ encode amount
      ++ encode recipientL1
```

with `action_roundtrip` and `action_encode_injective`
correspondingly extended.  Each new branch's roundtrip / injectivity
case closes by `simp` plus the per-field roundtrips
(`nat_roundtrip`, `byteArray_roundtrip`).

**Acceptance criteria.**

  * Both `compile`-extension theorems ship without `sorry`.
  * The CBE encoder roundtrip + injectivity theorems ship without
    `sorry`.
  * `Test/Authority/Action.lean` adds 8 new test cases (4 per new
    constructor: distinguishability + compile-shape).
  * `Test/Encoding/Action.lean` adds 2 new test cases
    (per-constructor round-trip).

### 7.5 WU C.5 — `Event` constructor extension

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** C.4.

**Deliverable.**  Two new `Event` constructors at frozen indices
9 and 10 in `LegalKernel/Events/Types.lean`:

```lean
inductive Event
  /- existing 0..8 ... -/
  | withdrawalRequested (r : ResourceId) (sender : ActorId)
                         (amount : Amount)
                         (recipientL1 : Bridge.EthAddress)
                         (withdrawalId : Bridge.WithdrawalId)
  | depositCredited     (r : ResourceId) (recipient : ActorId)
                         (amount : Amount)
                         (depositId : Bridge.DepositId)
```

with `extractEvents` branches in `LegalKernel/Events/Extract.lean`:

  * `Action.deposit` emits one `depositCredited`.
  * `Action.withdraw` emits one `withdrawalRequested` with
    `withdrawalId` derived from the post-state's `BridgeState.nextWdId`.
  * Both also emit the standard `nonceAdvanced` event.

**Theorems.**

```lean
theorem extractEvents_deposit_emits_credited :
  ∀ pre post sa, sa.action = .deposit r recipient amount depositId →
    Event.depositCredited r recipient amount depositId
      ∈ extractEvents pre post sa

theorem extractEvents_withdraw_emits_requested :
  ∀ pre post sa, sa.action = .withdraw r sender amount recipientL1 →
    ∃ wdId, Event.withdrawalRequested r sender amount recipientL1 wdId
              ∈ extractEvents pre post sa
```

**Acceptance criteria.**

  * Both theorems ship without `sorry`.
  * `Test/Events/Extract.lean` adds 4 new cases (deposit / withdraw
    × emission / determinism).

### 7.6 WU C.6 — Bridge accounting theorem

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** C.2, C.3,
C.4, C.5.

**Deliverable.**  The pure-Lean half of the cross-chain
solvency invariant.  Defines:

```lean
namespace LegalKernel.Bridge

/-- Total amount credited to resource `r` via consumed deposits,
    summed over the bridge's `consumed` set with per-deposit
    amounts recovered from the deposit-id index. -/
def totalDeposited (es : ExtendedState) (r : ResourceId) : Nat

/-- Total amount burned at resource `r` via pending withdrawals
    summed over the bridge's `pending` set. -/
def totalWithdrawn (es : ExtendedState) (r : ResourceId) : Nat

end LegalKernel.Bridge
```

and proves the master accounting equation:

```lean
/-- The bridge accounting invariant (pure-Lean half).  For every
    state reachable from genesis under the deployment's law set,
    Canon's L2 supply equals genesis-supply plus net deposits
    minus net withdrawals.  The L1-side complement (locked-on-L1
    = totalDeposited - totalWithdrawn) is enforced by
    `CanonBridge.sol` (workstream E.1). -/
theorem bridge_supply_account
    (L : MonotonicLawSet)
    (lawSetIncludesBridgeLaws : L.includes Laws.deposit ∧ L.includes Laws.withdraw)
    (es₀ es : ExtendedState)
    (h : ReachableViaLaws L es₀ es)
    (r : ResourceId) :
  totalSupply r es.base + Bridge.totalWithdrawn es r
    = totalSupply r es₀.base + Bridge.totalDeposited es r
```

The proof proceeds by induction on `ReachableViaLaws`.  The base
case is `rfl` (no deposits or withdrawals at genesis).  The
inductive step case-splits on the action variant:

  * `.deposit` — `totalSupply` and `totalDeposited` both
    increase by `amount`; equation preserved.
  * `.withdraw` — `totalSupply` decreases by `amount` and
    `totalWithdrawn` increases by `amount`; equation preserved.
  * Every conservative action — `totalSupply`, `totalDeposited`,
    `totalWithdrawn` all unchanged.
  * Every other monotonic non-deposit action (`mint`, `reward`,
    `distributeOthers`, `proportionalDilute`) — *the equation
    fails* unless the deployment's `MonotonicLawSet` excludes
    them.  The hypothesis `lawSetIncludesBridgeLaws` is *not*
    sufficient on its own; the full theorem requires
    `L.lawSet ⊆ {transfer, freezeResource, replaceKey, deposit,
                 withdraw}`.

To avoid the bookkeeping burden of an exclusion clause in the
hypothesis, ship a more permissive form:

```lean
/-- The accounting equation tolerates non-bridge monotonic actions
    by separating the supply contribution into bridge and non-
    bridge parts. -/
theorem bridge_supply_account_general
    (L : MonotonicLawSet) (es₀ es : ExtendedState)
    (h : ReachableViaLaws L es₀ es) (r : ResourceId) :
  totalSupply r es.base + Bridge.totalWithdrawn es r
    = totalSupply r es₀.base + Bridge.totalDeposited es r
        + Bridge.totalRewarded es r
```

where `totalRewarded` collapses non-bridge balance increases.
The strict version is then a corollary on the deployment that
disables `mint`/`reward`/`distributeOthers`/`proportionalDilute`.

**Acceptance criteria.**

  * The general theorem ships without `sorry`.
  * The strict corollary ships without `sorry` and is exercised by
    a value-level fixture.
  * `Test/Bridge/Conservation.lean` covers a 4-step trace
    (deposit, transfer, withdraw, transfer) and verifies the
    equation at each step.

## 8. Workstream D — withdrawal proofs

This workstream gives users a Merkle-proof object they can
present to `CanonBridge.sol` to redeem an L2 withdrawal on L1.
Every WU here is purely Lean + runtime; the Solidity-side
verification of these proofs lives in workstream E.1.

### 8.1 WU D.1 — sparse Merkle tree builder for `BridgeState.pending`

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** C.1, A.2.

**Deliverable.**  A new module
`LegalKernel/Bridge/WithdrawalRoot.lean` defining a sparse
Merkle tree over the `pending` map, with leaves
`keccak256(canonical_encode pendingWithdrawal)` and inner nodes
`keccak256(left ‖ right)` (the standard binary SMT construction).

```lean
namespace LegalKernel.Bridge

/-- A 32-byte Merkle root over `BridgeState.pending`.  The tree
    height is fixed at 64 (matching `Nat`-keyed indices ≤ 2^64,
    a hard upper bound from the WithdrawalId type). -/
def withdrawalRoot (b : BridgeState) : ByteArray  -- 32 bytes

/-- A Merkle inclusion proof for a single pending withdrawal,
    consisting of the leaf bytes and 64 sibling hashes. -/
structure WithdrawalProof where
  leaf     : ByteArray  -- canonical encode of PendingWithdrawal
  index    : WithdrawalId
  siblings : List ByteArray  -- exactly 64 elements

/-- Verify a proof against a root. -/
def verifyProof (proof : WithdrawalProof) (root : ByteArray) : Bool

end LegalKernel.Bridge
```

**Theorems.**

```lean
/-- Soundness: a valid proof guarantees the leaf is in the tree. -/
theorem verifyProof_sound :
  ∀ b proof, verifyProof proof (withdrawalRoot b) = true →
    ∃ wd, b.pending.find? proof.index = some wd ∧
          proof.leaf = canonicalEncode wd

/-- Completeness: every pending withdrawal has a verifiable proof. -/
theorem verifyProof_complete :
  ∀ b idx wd, b.pending.find? idx = some wd →
    let proof := constructProof b idx
    verifyProof proof (withdrawalRoot b) = true

/-- Determinism: a proof is uniquely determined by the bridge
    state and the withdrawal id (no choice of "compressed" form). -/
theorem constructProof_deterministic :
  ∀ b idx, constructProof b idx = constructProof b idx
```

`verifyProof_sound` is the *security* property: an attacker
cannot forge a proof for a leaf that isn't in the tree without
breaking keccak256 collision resistance.  The Lean theorem is
proved under a hypothesis `keccak_collision_free : ∀ x y, x ≠ y →
hashBytes x ≠ hashBytes y` introduced as a `Prop` parameter, not
an axiom.  The MVP test corpus exercises soundness at the value
level on the goldens; full cryptographic soundness is the runtime
adaptor's responsibility.

**Acceptance criteria.**

  * The three theorems ship under a `keccak_collision_free`
    hypothesis (a `Prop` parameter, not an axiom).
  * `Test/Bridge/WithdrawalRoot.lean` covers: empty tree (root =
    32 zero bytes); single-leaf tree; multi-leaf tree;
    proof-against-wrong-root rejection; proof-against-wrong-leaf
    rejection.
  * Cross-check against an OpenZeppelin Solidity SMT
    implementation on a 16-leaf golden file.

### 8.2 WU D.2 — withdrawal proof extractor

**Owner:** Lean + runtime; **Reviewer count:** 1; **Depends on:** D.1.

**Deliverable.**  A user-facing API that, given a `WithdrawalId`
and a finalised snapshot, returns a `WithdrawalProof` ready to be
submitted to L1.

```lean
namespace LegalKernel.Bridge

/-- Extract a withdrawal proof from a finalised snapshot.
    Returns `none` if the withdrawal id is not in the snapshot
    or if the snapshot is not yet finalised. -/
def extractProof (snap : Snapshot) (idx : WithdrawalId)
    : Option WithdrawalProof

end LegalKernel.Bridge
```

**Theorems.**

```lean
theorem extractProof_consistent_with_root :
  ∀ snap idx proof,
    extractProof snap idx = some proof →
    verifyProof proof (snap.bridgeWithdrawalRoot) = true
```

The runtime side exposes a CLI subcommand:

```
canon withdrawal-proof <SNAPSHOT_FILE> <WITHDRAWAL_ID>
  -> stdout: hex-encoded WithdrawalProof
```

**Acceptance criteria.**

  * The consistency theorem ships without `sorry`.
  * CLI integration test in `Test/Bridge/WithdrawalProofCLI.lean`.
  * The output is byte-stable across runs (the proof is
    deterministic per D.1).

### 8.3 WU D.3 — snapshot-window finalisation policy

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** D.1, D.2.

**Deliverable.**  A finalisation predicate that determines when a
snapshot's withdrawal root is "redeemable" on L1:

```lean
namespace LegalKernel.Bridge

/-- A snapshot is finalised when both:
    1. Its `submitStateRoot` L1 transaction has at least
       `disputeWindowBlocks` confirmations on L1.
    2. No `Verdict.upheld` has been applied against the snapshot's
       log range.
    The predicate is decidable per Phase-6's `disputeStatus`
    walk-the-log machinery. -/
def isFinalised (snap : Snapshot) (currentL1Block : Nat)
                (disputeWindowBlocks : Nat)
                (log : List LogEntry) : Bool

end LegalKernel.Bridge
```

**Theorems.**

```lean
theorem isFinalised_monotonic_in_currentBlock :
  ∀ snap b₁ b₂ w log, b₁ ≤ b₂ →
    isFinalised snap b₁ w log = true →
    isFinalised snap b₂ w log = true

theorem isFinalised_implies_no_upheld_against :
  ∀ snap b w log, isFinalised snap b w log = true →
    ∀ idx, snap.logIndexLow ≤ idx ∧ idx < snap.logIndexHigh →
      disputeStatus log idx ≠ some (.decided .upheld)
```

The first theorem captures the L1-confirmation monotonicity
(once finalised, always finalised); the second captures the
no-upheld-disputes property (a `.upheld` verdict invalidates the
snapshot for redemption).

**Acceptance criteria.**

  * Both theorems ship without `sorry`.
  * `Test/Bridge/Finalisation.lean` covers the dispute-window
    boundary cases.

## 9. Workstream E — Solidity contracts

This workstream is the on-chain complement.  All contracts target
Solidity ^0.8.20 and use OpenZeppelin libraries
(`MerkleProof`, `ECDSA`, `IERC20`) for primitives — no custom
crypto.  Contracts are deployed behind a transparent proxy
(`TransparentUpgradeableProxy`) for emergency-pause capability;
the upgrade key is held by a Safe multisig at deployment time
(transitionable to a DAO post-MVP).

### 9.1 WU E.1 — `CanonBridge.sol`

**Owner:** Solidity; **Reviewer count:** 1 Solidity + 1 Lean
(for cross-stack equivalence); **Depends on:** A.2 (keccak256),
D.1 (proof verifier shape).

**Deliverable.**  `solidity/contracts/CanonBridge.sol` with the
following surface:

```solidity
function depositETH() external payable;
function depositERC20(address token, uint256 amount) external;

function submitStateRoot(
    bytes32 root,
    uint64  logIndexHigh,
    bytes   calldata attestorSig
) external onlyAttestor;

function withdrawWithProof(
    bytes32          stateRoot,
    bytes   calldata proofBlob,    // canonical encode of WithdrawalProof
    bytes   calldata leafBlob      // canonical encode of PendingWithdrawal
) external returns (bool);

event DepositInitiated(
    address indexed depositor, address token, uint256 amount,
    bytes32 receiptHash
);
event StateRootSubmitted(
    bytes32 indexed root, uint64 indexed logIndexHigh, address attestor
);
event WithdrawalRedeemed(
    bytes32 indexed leafHash, address indexed recipient, uint256 amount
);
```

**Critical correctness obligations.**

  1. **`depositETH` and `depositERC20` are reentrancy-safe.**  Use
     `ReentrancyGuard` from OpenZeppelin and check-effects-
     interactions ordering.  Test with a malicious token
     fixture in F.1.
  2. **`receiptHash`** is computed as `keccak256(abi.encode(
     msg.sender, token, amount, blockhash(block.number-1), nonce))`,
     where `nonce` is a per-depositor counter.  This must match
     the Lean side's `DepositId` derivation in B.2 ingestion
     byte-for-byte.
  3. **`submitStateRoot`** verifies the attestor signature
     against a hardcoded public key (rotatable via governance, out
     of MVP scope).  The `logIndexHigh` is monotonically
     increasing across submissions; rejects any submission that
     does not strictly increase.
  4. **`withdrawWithProof`** verifies the proof against the most
     recent finalised state root (after the dispute window).
     Marks the leaf-hash as redeemed (single-spend) and pays out
     the recipient.

**Acceptance criteria.**

  * 100% line coverage in `forge` test suite.
  * Reentrancy attack fixture rejected.
  * Double-spend attack fixture rejected.
  * Cross-stack equivalence test (workstream F.1): given the
    same `(BridgeState, withdrawalId)`, the Lean-extracted proof
    verifies on-chain.
  * Attestor-signature replay rejected (`logIndexHigh` strict
    monotonicity).

### 9.2 WU E.2 — `CanonDisputeVerifier.sol`

**Owner:** Solidity + Lean (cross-port); **Reviewer count:** 2
(1 Solidity + 1 Lean, given the cross-stack porting risk);
**Depends on:** E.1, the Phase-6 dispute pipeline.

**Deliverable.**  `solidity/contracts/CanonDisputeVerifier.sol`
ports the *MVP-subset* of `Disputes.Evidence`'s per-claim
verifiers.  The MVP supports three of the five claim variants:

  * `signatureInvalid` — re-runs ECDSA verification against the
    signer's currently-registered key (read from
    `CanonIdentityRegistry.sol`).
  * `nonceMismatch` — recomputes the expected nonce by replaying
    the log prefix; rejects if the replay diverges from the
    impugned entry's recorded nonce.
  * `doubleApply` — scans the log for `(signer, nonce)` collisions;
    rejects if found.

Deferred to v2: `preconditionFalse` (requires full kernel replay,
expensive) and `oracleMisreported` (requires deployment-specific
oracle policy).

```solidity
function fileDispute(
    uint64           impugnedIdx,
    DisputeClaim     claim,
    bytes calldata   evidenceBlob
) external returns (uint64 disputeId);

function finalizeUpheld(
    uint64                    disputeId,
    bytes32                   verdictBytes,
    bytes[] calldata          adjudicatorSigs
) external;

event DisputeFiled(uint64 indexed disputeId, address indexed challenger);
event DisputeUpheld(uint64 indexed disputeId, bytes32 newRoot);
event DisputeRejected(uint64 indexed disputeId);
```

**Critical correctness obligations.**

  1. **Each Solidity verifier is byte-equivalent to its Lean
     counterpart.**  The cross-stack equivalence harness
     (workstream F.1) runs the same input through both
     implementations and compares output bit-for-bit.
  2. **Quorum check.**  `finalizeUpheld` requires
     `≥ quorumThreshold` distinct adjudicator signatures (per the
     Phase-6 `countVerifiedSignatures` deduplication invariant).
     The on-chain check is strictly equivalent to the Lean side;
     test with a "duplicate-signer pad" attack to ensure the
     trivial-quorum-forgery fix carries over.
  3. **Rollback.**  On `DisputeUpheld`, the contract calls
     `CanonBridge.revertToPriorRoot` to revert the published
     state root to the snapshot immediately before the impugned
     log range.  This is irrevocable.

**Acceptance criteria.**

  * Forge test coverage 100% on the three MVP claim variants.
  * Cross-stack equivalence: 100/100 random inputs produce the
    same `(verdict, evidence)` on both implementations.
  * Quorum-padding attack fixture rejected.
  * Rollback fixture demonstrably reverts state root.

### 9.3 WU E.3 — `CanonIdentityRegistry.sol`

**Owner:** Solidity; **Reviewer count:** 1; **Depends on:** none.

**Deliverable.**  A minimal pubkey-registration contract.

```solidity
function register(bytes calldata pubkey) external;
function revoke()                       external;
function lookup(address actor) external view returns (bytes memory);

event Registered(address indexed actor, bytes pubkey);
event Revoked   (address indexed actor);
```

EOAs may register their own pubkey (the contract verifies
`recover(keccak256(pubkey)) == msg.sender` to prevent malicious
front-running of someone else's identity); contract signers may
register an EIP-1271-compatible delegate.

**Acceptance criteria.**

  * Front-running attack rejected.
  * Re-registration is allowed (acts as key rotation).
  * Forge test coverage 100%.

### 9.4 WU E.4 — Sequencer staking and slashing

**Owner:** Solidity; **Reviewer count:** 1; **Depends on:** E.1, E.2.

**Deliverable.**  `solidity/contracts/CanonSequencerStake.sol`
holds the sequencer's stake in escrow.  On `DisputeUpheld`, the
stake is slashed: a `slashRatio` portion (configurable, default
50%) is paid to the challenger as the reward documented in
Phase-6's incentive amendment (`DisputeRewardPolicy`); the
remainder is burned (sent to `address(0)`).

```solidity
function deposit() external payable onlySequencer;
function withdraw(uint256 amount) external onlySequencer
    onlyAfter(LAST_DISPUTE + DISPUTE_WINDOW);
function slash(uint64 disputeId, address challenger) external
    onlyDisputeVerifier;
```

**Critical correctness obligations.**

  1. **Withdrawal lock-up.**  The sequencer cannot withdraw stake
     while a dispute is open against any of its published
     snapshots.
  2. **Single-slash-per-dispute.**  Each `disputeId` can be
     slashed at most once (idempotency mirrors
     `applyWithdraw_idempotent`).
  3. **Reward calculation matches Lean.**  The on-chain
     `slashRatio * stake` calculation is byte-equivalent to the
     Lean `DisputeRewardPolicy.proportionalChallengerReward`
     function.

**Acceptance criteria.**

  * Forge tests cover the three obligations above.
  * Cross-stack reward-equivalence test in F.1.

## 10. Workstream F — cross-stack verification

This workstream is the safety net.  Each WU here closes a gap
between the Lean-proven property and the Solidity-deployed
behaviour.

### 10.1 WU F.1 — Lean ↔ Solidity behavioural-equivalence corpus

**Owner:** Lean + Solidity; **Reviewer count:** 1 from each
side; **Depends on:** all of A, C, D, E.

**Deliverable.**  A new module `Test/Bridge/SolidityCrossCheck.lean`
plus a `forge` script `solidity/test/CrossCheck.t.sol`.  Both
share a JSON-encoded fixture file produced by a Lean test driver:

```
solidity/test/fixtures/
  ├── ecdsa_verify.json
  ├── keccak256.json
  ├── deposit_receipt_hash.json
  ├── withdrawal_proof.json
  └── dispute_evidence.json
```

For each fixture: the Lean side produces N inputs, computes the
expected output, and writes both to JSON.  The Solidity side
reads the JSON in a `forge` test, runs the on-chain function,
and asserts equality.  N is at least 100 per fixture; the
property-based seed is recorded for reproducibility.

**Acceptance criteria.**

  * 5 / 5 fixture files present.
  * 100 / 100 cross-stack matches per fixture.
  * Reproducibility: re-running the Lean driver with the recorded
    seed produces byte-identical fixture files.

### 10.2 WU F.2 — Goldens for keccak256 / ECDSA / RLP

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** A.1, A.2.

**Deliverable.**  Three golden files lifted from real Ethereum
mainnet data:

  * `goldens/block_header_hashes.txt` — keccak256 of 32 real
    block headers.
  * `goldens/transaction_signatures.txt` — 32 real
    `(pk, msg, sig)` triples.
  * `goldens/rlp_encodings.txt` — 32 real RLP-encoded
    transactions, alongside their keccak256 hashes.

Stored in the repository under `solidity/test/goldens/` and
exercised by both Lean tests (`Test/Bridge/Goldens.lean`) and
forge tests (`solidity/test/Goldens.t.sol`).

**Acceptance criteria.**

  * 32 / 32 keccak256 matches.
  * 32 / 32 ECDSA verify accepts.
  * 32 / 32 RLP-then-keccak matches.

### 10.3 WU F.3 — End-to-end testnet deployment

**Owner:** ops + Lean + Solidity; **Reviewer count:** 1;
**Depends on:** all preceding WUs.

**Deliverable.**  A scripted deployment to Sepolia (or Holesky)
that runs the §2.3 acceptance script unattended.  The script:

  1. Deploys all four Solidity contracts behind proxies.
  2. Starts the Canon sequencer with the deployment-id derived
     from chainId + the deployed bridge address.
  3. Performs the seven-step acceptance sequence with a single
     scripted EOA + a scripted MetaMask-equivalent signer (e.g.
     ethers.js).
  4. Asserts each step's success conditions on-chain (event
     emissions, balance changes).

**Acceptance criteria.**

  * Single-command `make testnet-acceptance` executes the script
    end-to-end and exits 0.
  * The script logs each step's L1 transaction hash for audit.

### 10.4 WU F.4 — Property-based test extension

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** Audit-3.9
property harness.

**Deliverable.**  Three new properties in
`Test/Properties/Bridge.lean`:

  * `prop_deposit_then_withdraw_roundtrip` — for any
    `(amount, recipient)`, depositing then immediately
    withdrawing the same amount returns the bridge state to its
    pre-deposit form (modulo `nextWdId` + `consumed` records).
  * `prop_bridge_account_invariant_holds` — for any reachable
    state under a `MonotonicLawSet` containing only
    `{transfer, deposit, withdraw}`, the
    `bridge_supply_account` equation holds.
  * `prop_withdrawal_proof_verifies` — for any `BridgeState`
    constructed by an arbitrary deposit / transfer / withdraw
    sequence, every pending withdrawal's extracted proof
    verifies against the published root.

Each property runs against `CANON_PROPERTY_ITERATIONS=100` by
default; failing seeds are logged.

**Acceptance criteria.**

  * 100 / 100 passes per property at the default seed.
  * Reproducible: a recorded failing seed reproduces the failure.

## 11. Workstream G — documentation and amendment

This workstream lands the documentation deliverables.  Each WU is
small but high-leverage; they are listed here as a single
workstream so they can be batched into one PR after the technical
WUs land.

### 11.1 WU G.1 — Genesis Plan amendment §15

**Owner:** Lean reviewer + project maintainer; **Reviewer count:**
2 (this is a Genesis-Plan edit, governed by §13.6); **Depends on:**
substantive completion of A–F.

**Deliverable.**  A new chapter `§15 Ethereum Integration` in
`docs/GENESIS_PLAN.md`.  The chapter covers:

  * The deployment scenario (canon-as-rollup).
  * The trust-assumption inventory delta.
  * The `Action` index extension at 12 / 13.
  * The `Event` index extension at 9 / 10.
  * The `ExtendedState` field extension (`bridge`).
  * The `bridge_supply_account` accounting equation.
  * The MVP non-goals (§2.2 of this document, lifted verbatim
    with cross-references).
  * The pointer to this workstream plan as the authoritative
    engineering roadmap.

**Acceptance criteria.**

  * §15 lands as a single PR with a §13.6 two-reviewer sign-off.
  * The chapter cross-references existing §4 / §5 / §8 sections
    where the bridge layer touches them.

### 11.2 WU G.2 — README and CLAUDE.md updates

**Owner:** project maintainer; **Reviewer count:** 1; **Depends on:**
G.1.

**Deliverable.**

  * `README.md` gains an "Ethereum integration" section pointing
    at this document and at the testnet deployment instructions.
  * `CLAUDE.md` gains:
    * a new `Phase E` row in the implementation roadmap table;
    * new build commands for the bridge modules;
    * the bridge-module dependency-graph extension;
    * the new typeclass / theorem entries in the
      "Type-level design properties" table.

### 11.3 WU G.3 — ABI document additions

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** C.4, C.5,
D.1, E.1.

**Deliverable.**  `docs/abi.md` gains §12 (Ethereum integration
ABI), covering:

  * `Action` constructor encodings at indices 12, 13, and 14.
  * `Event` constructor encodings at indices 9 and 10.
  * `BridgeState`, `PendingWithdrawal`, `WithdrawalProof` CBE
    encodings.
  * The bridge-actor `ActorId 0` reservation.
  * The keccak256 trailer format (replacing the FNV-1a-64 trailer
    in production deployments).
  * The `CanonBridge.sol`, `CanonIdentityRegistry.sol`, and
    `CanonDisputeVerifier.sol` event ABIs (the off-chain
    ingestor's contract).

### 11.4 WU G.4 — Extraction notes update

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** A.1, A.2, A.3.

**Deliverable.**  `docs/extraction_notes.md` §2 gains the new
trust assumptions (§3.3 of this document, formalised):

  * EUF-CMA on secp256k1.
  * Collision resistance of keccak256.
  * L1 finality.
  * Solidity contract correctness.
  * EIP-1271 contract correctness (opt-in).

Each assumption is paired with the workstream WU that introduces
it and the runtime adaptor symbol that implements it.

### 11.5 WU G.5 — Std-dependency audit refresh

**Owner:** Lean; **Reviewer count:** 1; **Depends on:** B.1
(introduces `Std.Data.TreeMap` lookups under new keys).

**Deliverable.**  `docs/std_dependencies.md` gains an entry for
each new `Std`-library lemma the bridge modules invoke.  No new
imports are expected (all bridge modules use `Std.Data.TreeMap`
already on the allowlist), but the audit must verify this
explicitly.

**Acceptance criteria.**

  * `lake exe tcb_audit` continues to pass (TCB modules unchanged).
  * The std-dep audit document lists every bridge-module Std
    lemma with stability annotations.

## 12. Mathematical correctness obligations

This section consolidates every proof obligation introduced by
the workstream plan.  Each entry names the theorem, summarises
the proof strategy, and identifies the WU that owns it.  Every
theorem ships without `sorry` and is `#print axioms`-clean
(only the three Lean built-ins).

### 12.1 Locality theorems (per new law)

| # | Theorem                              | WU  | Proof strategy                       |
|---|--------------------------------------|-----|--------------------------------------|
| 1 | `deposit_other_resource_untouched`   | C.2 | `getBalance_setBalance_other`        |
| 2 | `deposit_other_actor_untouched`      | C.2 | `getBalance_setBalance_other`        |
| 3 | `withdraw_other_resource_untouched`  | C.3 | `getBalance_setBalance_other`        |
| 4 | `withdraw_other_actor_untouched`     | C.3 | `getBalance_setBalance_other`        |

Each reduces to a single application of the §4.3 balance lemma.
Proofs are 1–3 lines each.

### 12.2 Per-resource accounting

| # | Theorem                              | WU  | Proof strategy                       |
|---|--------------------------------------|-----|--------------------------------------|
| 5 | `totalSupply_after_deposit`          | C.2 | `totalSupply_setBalance` + arithmetic|
| 6 | `totalSupply_after_withdraw`         | C.3 | `totalSupply_setBalance` + arithmetic|

Both are direct consequences of the §8.1 master lemma.  The
withdraw form requires the precondition (sufficient balance) so
that the `Nat` subtraction is exact (no truncation).

### 12.3 Classification (typeclass instances and witnesses)

| #  | Theorem                              | WU  | Proof strategy                       |
|----|--------------------------------------|-----|--------------------------------------|
| 7  | `deposit_isMonotonic`                | C.2 | direct from #5                       |
| 8  | `deposit_not_conservative`           | C.2 | mirror of `mint_not_conservative`    |
| 9  | `withdraw_not_monotonic`             | C.3 | mirror of `burn_not_monotonic`       |
| 10 | `withdraw_not_conservative`          | C.3 | mirror of `burn_not_conservative`    |

The negative witnesses use the same fixture-construction pattern
as their Phase-2 counterparts (mint / burn): pick a concrete
state where the inequality is strict, derive a contradiction
from the typeclass instance.

### 12.4 Compile and registry preservation

| #  | Theorem                                       | WU  | Proof strategy           |
|----|-----------------------------------------------|-----|--------------------------|
| 11 | `Action.compile_injective_extends`            | C.4 | `congrArg .source` (extends) |
| 12 | `non_replaceKey_preserves_registry_extends`   | C.4 | rfl on new branches      |
| 13 | `apply_admissible_with_preserves_bridge`      | C.1 | rfl on every branch      |

Each is a structural extension of an existing theorem; no new
proof technique.

### 12.5 Encoding round-trip and injectivity

| #  | Theorem                              | WU  | Proof strategy                |
|----|--------------------------------------|-----|-------------------------------|
| 14 | `action_roundtrip_extends`           | C.4 | per-field `*_roundtrip`       |
| 15 | `action_encode_injective_extends`    | C.4 | per-field `*_encode_injective`|
| 16 | `event_roundtrip_extends`            | C.5 | per-field `*_roundtrip`       |
| 17 | `bridgeState_roundtrip`              | C.1 | new instance + Encodable      |
| 18 | `pendingWithdrawal_roundtrip`        | D.1 | new instance + Encodable      |
| 19 | `withdrawalProof_roundtrip`          | D.1 | list + bytes round-trip       |

All follow the Phase-4 round-trip / injectivity discipline.

### 12.6 EIP-712 wrap (workstream A.3)

| #  | Theorem                              | WU  | Proof strategy                |
|----|--------------------------------------|-----|-------------------------------|
| 20 | `eip712Wrap_injective`               | A.3 | hash-collision-resistance hyp |
| 21 | `eip712DomainSeparator_distinguishes`| A.3 | injectivity of domain-encode  |
| 22 | `eip712Wrap_distinguishes`           | A.3 | composition of #20 + #21      |

The hash-collision-resistance hypothesis is a `Prop` parameter,
not a Lean axiom.  Real-world security depends on the
deployment-supplied keccak256.

### 12.7 Address book (workstream B.1)

| #  | Theorem                              | WU  | Proof strategy           |
|----|--------------------------------------|-----|--------------------------|
| 23 | `addressBook_invariant`              | B.1 | structural induction     |
| 24 | `assign_fresh_actorId`               | B.1 | case-split on lookup     |
| 25 | `assign_idempotent_for_known`        | B.1 | rfl                      |

### 12.8 L1 ingestor (workstream B.2)

| #  | Theorem                                      | WU  | Proof strategy            |
|----|----------------------------------------------|-----|---------------------------|
| 26 | `ingest_commutes_for_distinct_addresses`     | B.2 | case-split on event variant |
| 27 | `ingest_emits_bridge_actor_signature`        | B.2 | direct from constructor    |

### 12.9 Bridge-actor authority (workstream B.3)

| #  | Theorem                                      | WU  | Proof strategy |
|----|----------------------------------------------|-----|----------------|
| 28 | `bridgePolicy_rejects_transfer`              | B.3 | `decide`       |
| 29 | `bridgePolicy_rejects_withdraw`              | B.3 | `decide`       |
| 30 | `bridgePolicy_authorizes_deposit`            | B.3 | `decide`       |
| 31 | `bridgePolicy_authorizes_replaceKey`         | B.3 | `decide`       |
| 32 | `bridgePolicy_authorizes_registerIdentity`   | B.3 | `decide`       |

Plus one structural lemma owned by C.4:

| #  | Theorem                                      | WU  | Proof strategy |
|----|----------------------------------------------|-----|----------------|
| 33 | `registerIdentity_first_time_only`           | C.4 | direct from `applyActionToRegistry` case |

`registerIdentity_first_time_only` states: if
`apply_admissible_with` succeeds on a `registerIdentity actor pk`
action, then the pre-state's registry has no mapping for
`actor`.  This pins the first-time-only invariant at the
type level.

### 12.10 Withdrawal Merkle tree (workstream D.1)

| #  | Theorem                              | WU  | Proof strategy                     |
|----|--------------------------------------|-----|------------------------------------|
| 34 | `verifyProof_sound`                  | D.1 | hash-collision-resistance hyp      |
| 35 | `verifyProof_complete`               | D.1 | structural induction on tree depth |
| 36 | `constructProof_deterministic`       | D.1 | rfl                                |

### 12.11 Snapshot finalisation (workstream D.3)

| #  | Theorem                                  | WU  | Proof strategy                |
|----|------------------------------------------|-----|-------------------------------|
| 37 | `isFinalised_monotonic_in_currentBlock`  | D.3 | case-split on confirmations   |
| 38 | `isFinalised_implies_no_upheld_against`  | D.3 | direct from `disputeStatus` walk |

### 12.12 Bridge accounting (workstream C.6)

| #  | Theorem                              | WU  | Proof strategy                          |
|----|--------------------------------------|-----|-----------------------------------------|
| 39 | `bridge_supply_account_general`      | C.6 | induction on `ReachableViaLaws`         |
| 40 | `bridge_supply_account` (strict)     | C.6 | corollary of #39 + law-set restriction  |

### 12.13 Composition: end-to-end safety theorem

The composition of the above produces the headline safety
theorem for the MVP:

```lean
/-- The bridge deployment law set: transfer + the four
    registry-mutating / balance-mutating bridge laws.  Forms a
    `MonotonicLawSet` because every member is `IsMonotonic`
    (transfer + deposit) or balance-neutral (registerIdentity +
    replaceKey + freezeResource), and `withdraw` is *excluded*
    from this set — deployments wanting strict supply-non-
    decrease build a separate `MonotonicLawSet` without
    `withdraw`. -/
def bridgeLawSet : MonotonicLawSet

/-- Headline safety: under the bridge deployment law set, every
    reachable state simultaneously satisfies four invariants:

      1. **Bridge accounting** — the §C.6 supply-credit-debit
         equation.
      2. **Per-actor nonce monotonicity** — the §3 `expectsNonce`
         invariant lifted across reachability.
      3. **Registry-once-registered** — once an actor's registry
         entry is set, it stays set (possibly with a different
         key after `replaceKey`).
      4. **First-time-registration discipline** — the registry
         field is set via `registerIdentity` only when no prior
         entry existed.

    The conjunction is what `CanonBridge.sol` relies on for
    soundness of `withdrawWithProof`: the recipient address can
    be trusted to hold the claimed balance because (1) supply
    accounting is exact, (2) every authoring signature has a
    fresh nonce, and (3-4) the signing key is bound to the
    identity at the type level. -/
theorem bridge_deployment_safety
    (es₀ es : ExtendedState)
    (h : ReachableViaLaws bridgeLawSet es₀ es) :
    -- (1) bridge accounting:
    (∀ r, totalSupply r es.base + Bridge.totalWithdrawn es r
            = totalSupply r es₀.base + Bridge.totalDeposited es r)
    -- (2) per-actor nonce monotonicity:
  ∧ (∀ a, expectsNonce es.nonces a ≥ expectsNonce es₀.nonces a)
    -- (3) once registered, always registered:
  ∧ (∀ a pk₀, KeyRegistry.lookup es₀.registry a = some pk₀ →
        ∃ pk, KeyRegistry.lookup es.registry a = some pk)
    -- (4) first-time-registration discipline:
  ∧ (∀ a, KeyRegistry.lookup es₀.registry a = none →
        KeyRegistry.lookup es.registry a = none
        ∨ ∃ pk, KeyRegistry.lookup es.registry a = some pk
                ∧ /- registration happened via .registerIdentity -/ True)
```

The conjunction-of-four is proved by `And.intro` of four
independent inductive theorems, each decomposing over
`ReachableViaLaws` per-action-variant.  Owner: workstream C.6
(the conjunction is bundled with the accounting theorem; the
fourth conjunct couples to the C.4 `registerIdentity_first_time_only`
lemma).

Note: the fourth conjunct's `True` placeholder is the residual
witness "registration happened via `registerIdentity`"; a
strengthened form of this conjunct that records the witnessing
log entry is a candidate v2 refinement.

### 12.14 Invariants the runtime adaptor must preserve

The adaptors do *not* prove these in Lean (the proofs would
require modelling the IO substrate).  Instead, they are
contracts the runtime tests assert at the value level:

  * **A.1 ECDSA verify**: deterministic; high-s rejected;
    accepts iff secp256k1 verifies.
  * **A.2 keccak256**: deterministic; output exactly 32 bytes;
    matches NIST KAT vectors and `geth` outputs.
  * **B.2 L1 ingestor**: deterministic on the same `(L1 head,
    AddressBook)` pair; reorg-tolerant up to the configured
    confirmation depth.

Each of these is exercised by `Test/Bridge/*` value-level
fixtures and by the property-based suite (workstream F.4).

## 13. Sequencing and dependencies

### 13.1 Dependency DAG

The DAG is shown as an adjacency list (each WU lists its
prerequisites).  An ASCII rendering follows.

**Adjacency list (prerequisite → dependent):**

| WU   | Title                                | Prerequisites                           |
|------|--------------------------------------|-----------------------------------------|
| A.1  | ECDSA secp256k1                      | (root — no prerequisites)               |
| A.2  | keccak256                            | (root)                                  |
| A.3  | EIP-712 wrap                         | A.1, A.2                                |
| B.1  | AddressBook                          | (root)                                  |
| B.2  | L1 ingestor                          | B.1                                     |
| B.3  | Bridge actor                         | B.1, B.2                                |
| C.1  | BridgeState                          | B.1                                     |
| C.2  | deposit law                          | C.1                                     |
| C.3  | withdraw law                         | C.1                                     |
| C.4  | Action constructor extension         | C.2, C.3                                |
| C.5  | Event constructor extension          | C.4                                     |
| C.6  | Bridge accounting theorem            | C.2, C.3, C.4, C.5                      |
| D.1  | SMT root + proof verifier            | A.2, C.6                                |
| D.2  | Proof extractor                      | D.1                                     |
| D.3  | Snapshot finalisation                | D.1, D.2                                |
| E.1  | `CanonBridge.sol`                    | A.2, D.1                                |
| E.2  | `CanonDisputeVerifier.sol`           | A.1, A.2, E.1, Phase-6 dispute pipeline |
| E.3  | `CanonIdentityRegistry.sol`          | (root, Solidity-side)                   |
| E.4  | Sequencer staking                    | E.1, E.2                                |
| F.1  | Cross-stack equivalence corpus       | A.*, C.*, D.*, E.*                      |
| F.2  | Goldens (keccak / ECDSA / RLP)       | A.1, A.2                                |
| F.3  | End-to-end testnet deployment        | F.1, F.2, all of E.*                    |
| F.4  | Property-based tests                 | C.6, D.1                                |
| G.1  | Genesis Plan §15 amendment           | substantive completion of A–F           |
| G.2  | README + CLAUDE.md                   | G.1                                     |
| G.3  | ABI doc additions                    | C.4, C.5, D.1, E.1                      |
| G.4  | Extraction notes                     | A.1, A.2, A.3                           |
| G.5  | Std-dependency audit                 | B.1                                     |

**ASCII rendering** (left-to-right precedence; arrows omitted
for legibility):

```
             [Phases 0–6 + Audit-3 — pre-existing]
                            │
   ┌─────────┬──────────────┼──────────────┬──────────┐
   │         │              │              │          │
  A.1       A.2            B.1            E.3        G.5
   │         │              │              │
   └────┬────┘              ├─── B.2 ── B.3
        │                   │
       A.3                 C.1
                            │
                  ┌─────────┴─────────┐
                 C.2                 C.3
                  └─────────┬─────────┘
                           C.4
                            │
                           C.5
                            │
                           C.6
                            │
              ┌─────────────┼─────────────┐
              │             │             │
             D.1           E.1           F.4
              │             │
             D.2           E.2
              │             │
             D.3           E.4
              │             │
              └──────┬──────┘
                    F.1
                     │
              ┌──────┴──────┐
             F.2           F.3
                            │
                           G.1
                            │
                  ┌─────────┼─────────┐
                 G.2       G.3       G.4
```

### 13.2 Critical path

The longest dependency chain — and therefore the time floor for
the MVP — runs through the bridge-laws ➜ withdrawal-proofs ➜
cross-stack ➜ testnet ➜ amendment chain:

```
B.1 ──▶ C.1 ──▶ C.2 / C.3 ──▶ C.4 ──▶ C.5 ──▶ C.6 ──▶ D.1
        ──▶ D.2 ──▶ D.3 ──▶ F.1 ──▶ F.3 ──▶ G.1
```

Twelve sequential WUs along the critical path (C.2 and C.3 land
in parallel inside one slot).  D.1 also depends on A.2 (keccak256
adaptor); A.2 itself is a one-week deliverable that runs in
parallel with the early Lean work, so it does not extend the
critical path.

**Estimated effort.**

  * Lean-side WUs (A.3, B.*, C.*, D.*, F.4): ≈ 6 engineer-weeks.
  * Runtime adaptor WUs (A.1, A.2, ingestor binary): ≈ 2
    engineer-weeks.
  * Solidity-side WUs (E.*): ≈ 4 engineer-weeks.
  * Cross-stack + testnet (F.1, F.2, F.3): ≈ 1 engineer-week.
  * Documentation (G.*): ≈ 1 engineer-week.

Wall-clock duration with two engineers in parallel: ≈ 8 weeks.
With four engineers (one on Lean kernel-side, one on Lean bridge,
one on Solidity, one on runtime adaptor + ops): ≈ 5 weeks.

### 13.3 Parallelisation opportunities

  * **A.1 and A.2 are independent** of everything Lean-side and
    of each other.  Two engineers can land them in parallel.
  * **B.1 is independent** of A.* and can land first if a fast
    AddressBook test fixture is desired before the cryptographic
    adaptors land.
  * **E.3 (`CanonIdentityRegistry`)** is independent of everything
    else Solidity-side and can land in week 1.
  * **D.1 and E.1 can develop in parallel** once C.5 lands — D.1
    builds the proof, E.1 verifies it; F.1 closes the gap.
  * **G.* docs WUs** can be drafted in parallel with the
    technical WUs they document, then refined when the technical
    WUs land.

## 14. Acceptance gates

### 14.1 Per-WU exit criteria

Every WU's exit criteria conform to the same template:

  1. **Proof.**  All theorems listed in §12 for the WU ship
     without `sorry`.  `#print axioms` returns the canonical
     three-axiom set on every theorem.
  2. **Tests.**  `lake test` passes; the new WU-specific test
     module lands with the WU.  Test count grows by the number
     listed in the WU's section.
  3. **Build hygiene.**  `lake build`, `lake exe count_sorries`,
     `lake exe tcb_audit`, `lake exe stub_audit` all pass.
  4. **Documentation.**  Every public declaration (def /
     theorem / structure / instance) has a `/-- ... -/`
     docstring; the file has a `/-! ... -/` header citing the
     WU number.
  5. **Naming hygiene.**  The git-diff naming-violation grep
     (CLAUDE.md §"Names describe content, never provenance")
     returns empty.

### 14.2 Phase-level exit criteria (Phase E complete)

The phase is complete when:

  1. All WUs A.* through G.* meet their per-WU exit criteria.
  2. The §2.3 acceptance script passes on the testnet target.
  3. `kernelBuildTag` is bumped to
     `"canon-phase-e-ethereum-integration"` in `LegalKernel.lean`.
  4. `Tests.lean` driver registers the new test suites (estimated
     +12 suites, +120 tests).
  5. `docs/GENESIS_PLAN.md §15` lands with two-reviewer sign-off.
  6. The branch `claude/ethereum-kernel-integration-HMexY` (or
     its successor) merges to `main` via a PR that links every
     WU PR in its body.

### 14.3 Continuous-integration changes

The MVP introduces three new CI jobs:

  * **`forge-test`** — runs the Solidity test suite on every PR
    that touches `solidity/`.
  * **`cross-stack-equivalence`** — regenerates F.1 fixtures from
    Lean and asserts the forge tests still pass.
  * **`testnet-acceptance` (manual trigger)** — runs the §2.3
    sequence on a forked-testnet RPC; fails the run on any
    deviation.

Each job uses the same supply-chain pinning as the existing
GitHub Actions workflow (commit-SHA-pinned actions, no implicit
`@latest` references).

## 15. Risks and mitigations

### 15.1 Cryptographic-binding correctness

  * **Risk.**  The Rust `canon_verify` or `canon_hash_bytes`
    binding contains a subtle bug — e.g. fails to reject high-s
    ECDSA, or zero-pads keccak256 incorrectly — and the rest of
    the system trusts it.
  * **Mitigation.**  Workstreams F.1 and F.2 cross-check both
    bindings against `geth` / OpenZeppelin / NIST KAT vectors.
    Any deviation fails CI before merge.  Additionally, A.1 and
    A.2 each carry a property-based test corpus that reproduces
    failures via the recorded seed.

### 15.2 ECDSA malleability and `s`-canonicalisation drift

  * **Risk.**  An adapter version that *was* low-s-rejecting gets
    silently changed to accept high-s, opening malleability for
    log-bloat attacks.
  * **Mitigation.**  A.1's tests include
    `verifyAdaptor_rejects_high_s` as a hard-fail case.
    `lake exe stub_audit` is extended (workstream F.2 fixture)
    to flag any adapter implementation that omits the
    rejection.

### 15.3 ABI drift between Lean and Solidity

  * **Risk.**  The Lean side computes `DepositId` differently
    from the Solidity side, so a deposit on L1 is never matched
    to a Canon credit (or worse, a synthetic deposit credits
    with no L1 backing).
  * **Mitigation.**  F.1's `deposit_receipt_hash.json` fixture
    covers exactly this byte-equivalence.  E.1's test suite
    asserts `keccak256(abi.encode(...))` equality with the Lean
    value.

### 15.4 Reorg handling at the L1 ingestion boundary

  * **Risk.**  An L1 reorg removes a deposit event the Canon
    sequencer has already credited, producing a phantom credit.
  * **Mitigation.**  B.2's ingestor enforces a
    confirmation-depth gate (default 64 blocks ≈ 12 minutes
    post-Casper finality slot).  Events are *not* ingested until
    they have at least that many confirmations.  The
    confirmation depth is configurable per-deployment and is
    surfaced in the `docs/abi.md §11` documentation.

### 15.5 Sequencer censorship

  * **Risk.**  A malicious sequencer refuses to include a user's
    `Action.withdraw`, trapping their funds on Canon.
  * **Mitigation.**  *Out of MVP scope* but the architecture
    supports an L1-side escape hatch: a future workstream can
    add `forceWithdraw(...)` to `CanonBridge.sol` that lets
    users submit an L1 withdraw directly.  The Phase-6 dispute
    pipeline already gives the corresponding off-chain
    enforcement.  Track as a v2 addition.

### 15.6 Gas costs in the dispute verifier

  * **Risk.**  The on-chain `checkEvidence` for `nonceMismatch`
    requires re-running a log prefix in Solidity, which can be
    expensive for long disputes.
  * **Mitigation.**  *MVP-bounded.*  The MVP restricts disputable
    log prefixes to ≤ 256 entries (configurable), keeping the
    one-shot fraud proof tractable.  A bisection game is
    deferred to v2 when dispute length matters.

### 15.7 Trust-assumption inventory growth

  * **Risk.**  The MVP doubles the number of cryptographic /
    economic assumptions the system rests on, and a future
    auditor cannot easily enumerate them.
  * **Mitigation.**  G.4 lands an explicit table in
    `docs/extraction_notes.md §2` listing every new assumption
    with: name, scope, mitigated-by, reviewer-checklist entry.

### 15.8 Solidity contract upgrade key compromise

  * **Risk.**  The proxy upgrade key (initially a Safe multisig)
    is compromised, allowing the attacker to swap in a malicious
    implementation that drains the bridge.
  * **Mitigation.**  *Operational, not technical.*  The MVP's
    proxy upgrade key is held by a 3-of-5 Safe; key holders are
    geographically distributed; rotation is documented.  A
    timelock (configurable, default 7 days) is enforced on every
    upgrade.

### 15.9 Underestimated Lean-side proof difficulty

  * **Risk.**  Two theorems present non-trivial inductive
    arguments that may push back the timeline:
      1. `bridge_supply_account_general` (C.6) — induction on
         `ReachableViaLaws` over a heterogeneous law set with
         per-action accounting witnesses.
      2. `bridge_deployment_safety` (§12.13) — the four-conjunct
         composition, particularly the fourth conjunct's coupling
         to `registerIdentity_first_time_only`.
  * **Mitigation.**  *Pre-flight de-risking.*  For each: land
    the theorem statement as a `sorry`-stub on a feature
    branch first to sanity-check the type signature; only
    promote to a blocking WU once the proof outline is
    sketched.  The permissive form of #1 (with `totalRewarded`)
    and the `True`-placeholder form of #2's fourth conjunct are
    deliberately easier than the strict forms to give fall-back
    landing points.  Neither stub may merge to `main` —
    `lake exe count_sorries` would reject — but they give
    fast feedback during development.

### 15.10 Naming-policy violation in user-contributed PRs

  * **Risk.**  An external contributor's PR slips a process
    marker (`mvp_`, `eth_`, `phase_e_`) into a declaration name.
  * **Mitigation.**  Extend the existing CI workflow with a
    naming-violation grep step using the regex from CLAUDE.md
    §"Names describe content, never provenance".  Failure of the
    step blocks merge.  This is automation-only — no PR template
    or contributor-side process step is required, keeping the
    discipline mechanical rather than discretionary.

## 16. Out of scope (post-MVP)

The following items are deliberately deferred.  They are listed
here with rationale so that future planners do not re-litigate
them.

  1. **`ActorId` widening to 20 bytes.**  Requires kernel TCB
     change + two-reviewer sign-off.  Registry indirection (B.1)
     is sufficient for the MVP at the cost of one extra TreeMap
     lookup per action.  Re-evaluate when the lookup becomes a
     measured bottleneck.
  2. **ZK proofs of `apply_admissible`.**  Optimistic disputes
     are sufficient for the MVP.  ZK extension requires either
     re-implementing the kernel in a SNARK DSL (Circom / Noir /
     RISC0) or maturing a Lean→ZK extraction pipeline; neither
     is on the MVP critical path.
  3. **Bisection dispute games.**  The MVP's one-shot fraud
     proof works for log prefixes ≤ 256 entries; bisection is
     mandatory for production-scale logs but is not gating.
  4. **ERC-4337 account abstraction.**  EIP-1271 covers contract
     signers; the UserOperation envelope adds significant
     surface that the MVP does not need.
  5. **Cross-rollup interop.**  `deploymentId` already gives
     cross-rollup replay rejection; the bidirectional cross-
     rollup bridge is a future workstream.
  6. **Native ETH gas market.**  Sequencer-as-paymaster is fine
     for the MVP; an on-chain fee market is a v2 concern.
  7. **Sequencer decentralisation.**  Single-sequencer with
     attestation key is fine for the MVP; rotation /
     leader-election / shared-sequencing is a v2 concern.
  8. **L1 escape hatch (`forceWithdraw`).**  Adds censorship
     resistance but increases L1 gas cost and adds attack
     surface.  Track as a v2 priority.
  9. **`preconditionFalse` and `oracleMisreported` claim
     variants in Solidity.**  Both require non-trivial
     state-replay or oracle-policy machinery in Solidity.  MVP
     ships the three simpler variants; v2 ships the remaining
     two.
  10. **Multi-resource bridges.**  The MVP supports a single
      ResourceId per ERC-20 token (1:1 mapping).  Multi-resource
      bundles (e.g. NFT-style ERC-721) are a v2 concern.

## 17. Glossary

  * **CBE** — Canon Binary Encoding, the deterministic byte codec
    documented in `LegalKernel/Encoding/CBOR.lean` and
    `docs/abi.md`.
  * **Deployment** — a single instantiation of Canon's runtime
    against a particular `(chainId, rollupId, attestor key)`
    triple.  Distinguished from other deployments via
    `deploymentId`.
  * **Dispute window** — the period after a state-root submission
    during which `CanonDisputeVerifier.sol` will accept fraud
    proofs.  Configurable per-deployment; default 7 days.
  * **EIP-712** — the Ethereum standard for typed structured
    data signing (`https://eips.ethereum.org/EIPS/eip-712`).
  * **EIP-1271** — the Ethereum standard for contract signers
    (`https://eips.ethereum.org/EIPS/eip-1271`).
  * **Fraud proof** — an L1-verifiable demonstration that a
    sequencer's published state root is wrong.  Maps onto
    Phase-6's `Disputes.Evidence` machinery.
  * **MVP** — minimum viable product; the deliverable scope of
    this plan.
  * **Optimistic rollup** — a rollup architecture in which state
    transitions are presumed valid unless challenged within a
    dispute window.
  * **Sequencer** — the off-chain process that orders Canon
    transactions, applies them via `processSignedAction`, and
    publishes state roots to L1.
  * **Settlement** — the act of finalising an L2 state root on
    L1 such that the L1 contract treats it as canonical.
  * **TCB** — trusted computing base; for Canon, the union of
    `LegalKernel/Kernel.lean` and `LegalKernel/RBMapLemmas.lean`.
  * **WU** — work unit, the atomic unit of engineering effort
    in the Genesis Plan / this document.
