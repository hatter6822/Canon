<!--
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-->

# Rust Host Runtime — Engineering Plan

This document plans the unified Rust-side runtime that ports the
Lean kernel's deployment-supplied substrates (crypto, hash, L1
event watcher) to production-grade implementations and ships the
host-level deliverables Phase 5 deferred (network adaptor,
subscription server, indexer, benchmark).  It also lands the
off-chain fault-proof observer deferred by Workstream H.

The Lean side is complete: every kernel theorem stands today on
the existing `@[extern]` swap-points and `opaque` declarations.
This workstream materialises the *production* implementations
behind those interface contracts.

## Status

  * **Workstream prefix:** `RH` (Rust Host).  Sub-streams:
    - **RH-A** Cryptographic adaptors (E-A Rust).
    - **RH-B** L1 ingestor (E-B Rust).
    - **RH-C** Network adaptor (Phase 5 WU 5.4).
    - **RH-D** Event subscription (Phase 5 WU 5.7).
    - **RH-E** SQLite indexer + Rust DB layer (Phase 5 WU 5.8).
    - **RH-F** Performance benchmark (Phase 5 WU 5.11).
    - **RH-G** Fault-proof observer (Workstream H, WU H.10.5).
    - **RH-H** Workspace + CI harness (the cross-cutting unit).
  * **Effort estimate:** 14–22 calendar weeks for one full-time
    Rust engineer (or ~9–14 weeks with two engineers post-RH-H).
  * **Build-posture target:** All Rust crates build under `cargo
    +stable build --workspace`, pass `cargo clippy
    --workspace -- -D warnings`, pass `cargo test --workspace`,
    and pass the cross-stack equivalence corpus.  Lean side is
    unchanged.
  * **TCB delta:** zero on the Lean side.  The Rust crates
    materialise existing `opaque`/`@[extern]` contracts; they do
    not extend the Lean TCB.
  * **Trust-assumption delta:** the existing `Verify`, `hashBytes`,
    and `l1FaultProofVerifier` opaques become *real* (linkable)
    symbols.  The EUF-CMA, collision-resistance, and L1-watcher
    assumptions documented in CLAUDE.md are unchanged in
    substance; this workstream realises them rather than adding
    new ones.

## Table of contents

  * §1 Goals and non-goals
  * §2 Architectural background
    * §2.1 The `@[extern]` swap-point contract
    * §2.2 Workspace layout
    * §2.3 Process model
    * §2.4 ABI / wire formats
  * §3 Work-unit dependencies
  * §4 Work-unit specifications (RH-A through RH-H)
  * §5 Sequencing and PR structure
  * §6 Quality gates
  * §7 Risk register
  * §8 Acceptance criteria for the workstream
  * §9 Out-of-scope items
  * §10 References

## §1 Goals and non-goals

### §1.1 Goals

  1. **Materialise the three `@[extern]` / `opaque` swap-points.**
    Production deployments link real implementations against:
     * `canon_hash_bytes` / `canon_hash_stream` /
       `canon_hash_identifier` — BLAKE3 (CLAUDE.md §"Trust
       assumptions") or keccak256 (Workstream E-A).
     * `canon_verify_ecdsa` — secp256k1 verification with low-s
       canonicalisation.
     * `canon_l1_fault_proof_verifier` — L1 event watcher with
       Ethereum JSON-RPC source.
  2. **Ship the Phase-5 host runtime stack.**  Network adaptor,
    event subscription, SQLite indexer, and 10k tx/sec
    benchmark.  These deliverables turn `canon` from a single-
    process executable into a real network service.
  3. **Ship the fault-proof off-chain observer.**  The
    long-running daemon that watches L1, computes honest-strategy
    bisection responses, and submits them to the L1 game
    contract.  Closes Workstream H Rust deliverable.
  4. **Preserve byte-identical cross-stack equivalence.**  Every
    Rust output (signature verification, hash, encoded
    `SignedAction`) byte-equals the Lean reference under the
    cross-stack fixture corpus.
  5. **Zero kernel changes.**  No `.lean` file changes outside
    of (a) ABI-cite-update doc strings and (b) test-fixture
    expansion.  The Lean kernel is the wire-format authority;
    the Rust crates conform.

### §1.2 Non-goals

  1. **No new trust assumptions.**  RH realises the existing
    swap-point contracts; it does not introduce new ones.
  2. **No Rust port of the Lean kernel.**  Lean's `step_impl` is
    the *only* canonical state-transition function.  The Rust
    runtime is a *shell* around `step_impl`: it receives signed
    actions over the network, forwards them via a sub-process or
    FFI call to the Lean executable, and returns the verdict.
  3. **No alternative encoding format.**  CBE is the wire format.
  4. **No deployment-specific configuration files.**  Each crate
    accepts a small CLI-flag set; full operator deployment is
    out of scope (the operator runbooks live separately).
  5. **No telemetry / metrics framework.**  Minimal counters
    (admitted vs rejected, p99 latency) are in scope; full
    Prometheus / OpenTelemetry export is a follow-up.

### §1.3 Reading guide

  * **Implementer (Rust):** read §2 (architecture) then §4 in
    order RH-H → RH-A → RH-G → ... .  RH-H establishes the
    workspace; RH-A is the simplest crypto crate (no I/O); RH-G
    has the operator runbook already drafted in
    `docs/fault_proof_runbook.md` §7.
  * **Implementer (Lean):** RH does not require Lean changes
    except for ABI docstring cross-references.  No new theorems.
  * **Reviewer:** check the cross-stack fixture corpus passes
    for every crate; check `cargo test` and clippy are clean.

### §1.4 Glossary

  * **Cross-stack fixture corpus.**  The set of test inputs
    where Lean and Solidity (and now Rust) all agree on output
    byte-for-byte.  Lives under `solidity/test/CrossStack/` and
    `runtime/canon-host/tests/cross-stack/`.
  * **Swap-point.**  A Lean declaration annotated `@[extern]` or
    `opaque` whose body is supplied at link time (for `@[extern]`)
    or at deployment-instance time (for `opaque`).  Three are
    relevant here: `hashBytes`, `Verify`, `l1FaultProofVerifier`.
  * **Honest strategy.**  The set of bisection-game responses
    computed from the canonical Lean replay; the observer
    daemon's job is to compute and submit these.

## §2 Architectural background

### §2.1 The `@[extern]` swap-point contract

Each swap-point is a Lean declaration of the form:

```lean
@[extern "canon_hash_bytes"]
def hashBytes (bs : ByteArray) : ByteArray :=
  hashBytesFallback bs
```

Lean's code-generator emits a call to the C symbol
`canon_hash_bytes` at runtime.  If the symbol is not provided by
the link environment, the compiled Lean falls back to the inline
`hashBytesFallback` body (an FNV-1a-64 stand-in shipped in
`runtime/canon-hash-fallback.c`).

The contract for a swap-point implementation is:

  1. **Same C ABI.**  The symbol name, argument types (`b_lean_obj_arg`
    of `ByteArray`), and return type (`lean_obj_res ByteArray`)
    must match Lean's `extern` declaration exactly.
  2. **Same byte-output.**  The Rust implementation must produce
    identical bytes to the documented production hash / signature
    scheme, validated against the cross-stack fixture corpus.
  3. **No side effects.**  Pure function.  No global state, no
    file I/O, no network I/O.

The `opaque` declarations (`Verify`, `l1FaultProofVerifier`) have
the same shape but no fallback body — calling them returns
`False` / `false` at the Lean level by Lean's
`Inhabited`-derivation default.  Production deployments must
supply a real implementation by replacing the `opaque` with an
`@[extern]` decl in a deployment-specific module *or* by linking
a substitute through the C-ABI surface.  This is the existing
deployment-instance pattern; RH does not change it.

### §2.2 Workspace layout

```
runtime/                          (project-relative root)
├── Cargo.toml                    -- workspace manifest
├── rust-toolchain.toml           -- pinned (stable 1.83+)
├── canon-host/                   -- RH-C network adaptor binary
│   ├── Cargo.toml
│   ├── src/main.rs               -- TCP/Unix-socket listener
│   ├── src/lean_subprocess.rs    -- spawns canon executable
│   └── src/abi.rs                -- CBE frame parser
├── canon-hash-keccak256/         -- RH-A.2 keccak256 adaptor
│   ├── Cargo.toml
│   ├── build.rs                  -- emits cdylib
│   └── src/lib.rs                -- #[no_mangle] canon_hash_bytes
├── canon-verify-secp256k1/       -- RH-A.1 ECDSA adaptor
│   ├── Cargo.toml
│   ├── build.rs
│   └── src/lib.rs                -- #[no_mangle] canon_verify_ecdsa
├── canon-l1-ingest/              -- RH-B L1 event ingestor
│   ├── Cargo.toml
│   └── src/main.rs               -- Ethereum JSON-RPC → SignedAction
├── canon-event-subscribe/        -- RH-D subscription server
│   ├── Cargo.toml
│   └── src/main.rs               -- ordered, bounded-lag dispatcher
├── canon-indexer/                -- RH-E SQLite indexer
│   ├── Cargo.toml
│   └── src/main.rs               -- event stream → SQLite views
├── canon-storage/                -- Rust DB layer (RH-E.0)
│   ├── Cargo.toml
│   └── src/lib.rs                -- KV/SQLite abstraction trait
├── canon-faultproof-observer/    -- RH-G off-chain observer
│   ├── Cargo.toml
│   └── src/main.rs               -- L1-event watcher daemon
├── canon-bench/                  -- RH-F benchmark
│   ├── Cargo.toml
│   └── benches/transfer_10k.rs
├── canon-cli-common/             -- shared CLI helpers
│   ├── Cargo.toml
│   └── src/lib.rs
└── tests/cross-stack/            -- cross-stack equivalence fixtures
    ├── hash_inputs.cbor
    ├── ecdsa_vectors.cbor
    └── signed_action_corpus.cbor
```

`canon-cli-common` and `canon-storage` are library crates
consumed by the binaries.  All binaries depend on
`canon-cli-common`; `canon-indexer` depends on `canon-storage`.

### §2.3 Process model

```
Operator                                                  Ethereum L1
   │                                                            │
   ▼                                                            ▼
canon-host (TCP) ─── spawns ───► canon (Lean exe) ◄── reads ── canon-l1-ingest
   │                                  │                            │
   │                                  ▼                            │
   │                              log.jsonl                        │
   │                                  │                            │
   ▼                                  ▼                            ▼
client                          canon-event-subscribe       canon-faultproof-observer
                                    │                            │
                                    ▼                            ▼
                              canon-indexer                  L1 game contract
                                    │
                                    ▼
                              indexer.db (SQLite)
```

Key invariants:

  * `canon-host` is the only writer to the log; all other
    crates are read-only consumers.
  * `canon-event-subscribe` and `canon-faultproof-observer` and
    `canon-indexer` consume the same log frames; ordering and
    durability come from `canon`'s `LogFile.lean` semantics.
  * The Lean `canon` executable is *unchanged*; the Rust shell
    is a process supervisor + ABI shim.

### §2.4 ABI / wire formats

Three wire-level interfaces are introduced (or finalised) in RH:

  1. **`canon-host` ↔ client (TCP).**  Length-prefixed CBE
    `SignedAction` request, length-prefixed CBE `Verdict`
    response.  Verdict bytes: `0 = OK`, `1 = notAdmissible`,
    `2 = parseError`.  TLS termination at the TCP boundary (RH-C
    accepts a `--tls-cert` / `--tls-key` pair; absence implies
    plaintext for local testing).  Full spec lands in
    `docs/abi.md` §10 (RH-C closes the placeholder line at
    `abi.md:724`).
  2. **`canon-host` ↔ `canon` (Unix socket).**  Same CBE framing
    as above, over a filesystem-permission-protected Unix socket
    (`/var/run/canon.sock` by default).  This is the existing
    Lean-side IPC channel; RH-C wires the host to it.
  3. **`canon-event-subscribe` ↔ client (TCP).**  An ordered
    event stream with a small framing header (`uint64` sequence
    number, `uint32` event length, then CBE-encoded event).
    Subscribers may resume from a given sequence number; the
    server enforces bounded subscriber lag and rejects
    out-of-order or dropped subscribers.

The L1 ingestor and observer crates use Ethereum JSON-RPC via
the `ethers-rs` library and consume L1 events directly; they do
not introduce new Canon wire formats.

## §3 Work-unit dependencies

```
RH-H (workspace + CI)
  ├── RH-A.1 (canon-verify-secp256k1)
  ├── RH-A.2 (canon-hash-keccak256)
  ├── RH-C (canon-host network adaptor)  ◄── RH-A.* link-time
  │     │
  │     └── RH-F (10k tx/sec benchmark)
  ├── RH-D (canon-event-subscribe)
  │     │
  │     ├── RH-E.0 (canon-storage / Rust DB layer)
  │     │     │
  │     │     └── RH-E.1 (canon-indexer)
  │     │
  │     └── RH-G (canon-faultproof-observer)
  │           │
  │           └── RH-B (canon-l1-ingest)  -- L1 RPC infrastructure
```

  * **RH-H first.**  Workspace skeleton, shared CI, cross-stack
    fixture corpus extension to Rust.
  * **RH-A in parallel** (no I/O, isolated crypto).
  * **RH-C after RH-A** (links the crypto adaptors at runtime).
  * **RH-D and RH-B in parallel** (different event sources).
  * **RH-E.0 before RH-E.1.**  The DB layer abstraction is the
    structural blocker for the indexer.
  * **RH-G after RH-D + RH-B** (consumes both).
  * **RH-F last** (depends on RH-C for end-to-end measurement).

## §4 Work-unit specifications

---

### RH-H — Workspace and CI harness

**Finding map.**  Common infrastructure for the entire Rust
runtime workstream.

**Scope.**  `runtime/` workspace skeleton; CI pipeline
extension; cross-stack fixture corpus packaging for Rust.

**Implementation steps.**

  1. Create `runtime/Cargo.toml` with workspace `[workspace]
    members = [...]` listing all eight crates.
  2. Add `runtime/rust-toolchain.toml` pinning stable Rust
    (recommend 1.83 stable LTS as of 2026; bump in a separate
    PR if a newer LTS is preferred).
  3. Extend `.github/workflows/ci.yml` with a `rust-build`
    job that runs `cargo build --workspace --all-targets`,
    `cargo test --workspace`, `cargo clippy --workspace
    --all-targets -- -D warnings`, and `cargo fmt --check`.
    Gate the job behind a `paths` filter so PRs that touch only
    `LegalKernel/*` don't trigger Rust CI.
  4. Implement `runtime/tests/cross-stack/` fixture loader.
    Each fixture is a CBE-encoded test vector (input bytes plus
    expected Lean output bytes).  The loader is a thin Rust
    helper that other crates import as a dev-dependency.
  5. Add `runtime/README.md` describing the workspace and
    pointing at this plan.
  6. Add to `CLAUDE.md` "Build and run" section: a "Rust host
    runtime" sub-section with `cargo build --workspace` and
    `cargo test --workspace` commands.

**Acceptance criteria.**

  * `cargo build --workspace` succeeds in CI.
  * `cargo clippy --workspace -- -D warnings` is clean.
  * Cross-stack fixture loader is consumable as a dev-dep.
  * Lean-side CI unaffected for `.lean`-only PRs.

**Risk.**  Low.  Standard Rust workspace setup.

**Effort.**  ~3 engineer-days.

---

### RH-A.1 — `canon-verify-secp256k1`

**Finding map.**  E-A Rust adaptor crate (deferred per
`ethereum_integration_plan.md:1075`).

**Scope.**  `runtime/canon-verify-secp256k1/` — a `cdylib`
exposing the `canon_verify_ecdsa` C symbol.

**Implementation steps.**

  1. Crate skeleton with `[lib] crate-type = ["cdylib", "rlib"]`.
  2. Depend on the audited `k256` crate (Rust Crypto project).
  3. Implement the C ABI shim:
     ```rust
     #[no_mangle]
     pub unsafe extern "C" fn canon_verify_ecdsa(
         pk: *const u8, pk_len: usize,
         msg: *const u8, msg_len: usize,
         sig: *const u8, sig_len: usize,
     ) -> bool { … }
     ```
  4. Enforce low-s canonicalisation: reject signatures whose `s`
    component exceeds `secp256k1_n / 2`.  This matches the
    Ethereum convention and the Solidity-side verifier.
  5. Add `tests/cross_stack.rs` that loads the cross-stack ECDSA
    fixtures and asserts the verifier agrees with each fixture's
    expected outcome.

**Math / soundness.**

The crate implements:
  - Input parse: 33-byte compressed public key, 32-byte message
    hash (keccak256 already applied by caller), 64-byte raw
    `(r, s)` signature.
  - Verify: standard ECDSA-secp256k1 with low-s rejection.
  - Boundary check: every malformed input returns `false`
    (never panics, never UB).

The Lean side's `Verify : PublicKey → ByteArray → Signature → Bool`
contract requires *total* function semantics; this crate must
not panic on malformed input.  Test plan covers parse failures
explicitly.

**Acceptance criteria.**

  * Cross-stack fixture vectors all pass.
  * No panics on malformed inputs (proptest with `quickcheck` or
    `proptest` crate at a minimum of 10k random inputs).
  * `cargo clippy -- -D warnings` clean.

**Test plan.**

  * Cross-stack equivalence: Lean test fixtures replay against
    this Rust crate.
  * Negative: low-s rejection, invalid public-key encoding,
    invalid signature length, malformed `r`/`s`.
  * Fuzz: 10k random byte arrays per input slot via `proptest`.

**Risk.**  Low.  Well-audited library.

**Effort.**  ~5 engineer-days.

---

### RH-A.2 — `canon-hash-keccak256`

**Finding map.**  E-A Rust adaptor crate (deferred per
`ethereum_integration_plan.md:1136`).

**Scope.**  `runtime/canon-hash-keccak256/` — a `cdylib`
exposing `canon_hash_bytes`, `canon_hash_stream`, and
`canon_hash_identifier`.

**Implementation steps.**

  1. Crate skeleton (parallel to RH-A.1).
  2. Depend on `tiny-keccak` or `sha3` (both audited Rust
    Crypto-ecosystem crates; recommend `sha3` for actively
    maintained status).
  3. Implement three C ABI shims.  `canon_hash_bytes` takes
    `(ptr, len)` and returns a 32-byte hash.  `canon_hash_stream`
    is a streaming variant (init / update / finalize).
    `canon_hash_identifier` returns a deployment-distinguishing
    constant (the byte string `"keccak256"`).
  4. Memory-management discipline: returned ByteArrays must be
    valid Lean `ByteArray` heap objects.  Use `lean_alloc_array`
    via the `lean-sys` crate (or hand-rolled FFI).
  5. Cross-stack tests via fixture corpus.

**Math / soundness.**

Standard keccak256 over byte arrays.  No deviation from FIPS-202
keccak permutation (256-bit output variant).

**Acceptance criteria + test plan + risk + effort.**  As RH-A.1.

**Effort.**  ~4 engineer-days (skeleton shared with RH-A.1).

---

### RH-B — `canon-l1-ingest`

**Finding map.**  E-B Rust ingestor (deferred per
`ethereum_integration_plan.md:91`).

**Scope.**  `runtime/canon-l1-ingest/` — long-running daemon
that watches Ethereum L1, translates relevant events to
`SignedAction`s via the bridge-actor signing flow, and submits
them to the local `canon-host`.

**Implementation steps.**

  1. Crate skeleton; depend on `ethers-rs` for JSON-RPC.
  2. Implement L1 watcher: subscribe to `eth_newHeads`, scan
    each block for events emitted by Canon's L1 contracts
    (`CanonBridge`, `CanonIdentityRegistry`).
  3. For each relevant event, construct the corresponding
    `Action` (e.g. `Action.deposit`), sign it with the
    bridge-actor key (loaded from a CLI flag pointing at a
    `keystore.json`), and submit via the `canon-host` TCP
    interface.
  4. Implement re-org handling: track the last-confirmed L1
    block; on detection of a chain re-org (parent hash
    mismatch), re-process events from the divergence point.
  5. Add metrics: event-counter, signing-latency histogram.

**Math / soundness.**

The crate is the operational counterpart to
`LegalKernel.Bridge.Ingest.lean`.  Each Rust call to "translate
event E to Action A" must produce the same `Action.encode` byte
string as `Bridge.Ingest.ingest E` on the Lean side.  This is
verified via cross-stack fixtures: the corpus pairs `(L1 event
hex, expected Action CBE bytes)`.

**Acceptance criteria.**

  * Cross-stack fixture corpus passes.
  * Re-org handling regression: forge a 2-deep re-org, confirm
    the daemon rewinds correctly.
  * Bridge-actor private key handled via secure-memory crate
    (`zeroize`).

**Test plan.**

  * Cross-stack equivalence: 30+ fixture pairs.
  * Integration: spin up `anvil` (Ethereum testnet emulator) +
    `canon-host` + this crate; deposit on L1, confirm the L2
    state reflects the deposit.
  * Re-org test as above.

**Risk.**  Medium.  Re-org handling is the historical hard part
of L1 ingestors.

**Effort.**  ~12 engineer-days.

---

### RH-C — `canon-host` (network adaptor, Phase 5 WU 5.4)

**Finding map.**  WU 5.4 deferred per GENESIS_PLAN line 3807.

**Scope.**  `runtime/canon-host/` — TCP/Unix-socket service
that accepts CBE-framed `SignedAction` requests and forwards
them to the Lean `canon` executable.

**Implementation steps.**

  1. Crate skeleton.  Use `tokio` for async I/O.
  2. Listener: TCP socket (default port 7456) plus optional TLS
    via `rustls`.  Local Unix socket optional for client-local
    testing.
  3. For each connection: read length-prefixed CBE frames,
    forward to `canon` via the existing Unix-socket interface
    (the Lean side already exposes this; consult
    `LegalKernel/Runtime/Loop.lean` for the protocol).
  4. Read back the verdict; write to the client.
  5. Wire format documentation: extend `docs/abi.md` §10 to a
    full specification (currently a placeholder).
  6. Backpressure: bounded request queue per connection; drop
    excess and respond with a "busy" verdict variant (add a new
    verdict code `3 = busy`; this is a wire-format extension,
    so coordinate with E-G documentation).

**Math / soundness.**

The host is a pure shell: it does not parse or interpret the
CBE bytes beyond length-prefixing.  All semantic checks happen
in the Lean `canon` subprocess.  This means the host has zero
attack surface against the Lean admissibility predicate.

**Acceptance criteria.**

  * Cross-stack: send a corpus of pre-recorded
    `SignedAction`/verdict pairs through `canon-host`; every
    verdict matches.
  * TLS: handshake with a self-signed cert in integration test.
  * Bounded queue: stress test confirms graceful degradation
    under load (no OOM).

**Test plan.**

  * Smoke: single request/response.
  * Stress: 1000 concurrent connections, each sending 100
    requests.
  * Adversarial: malformed frames (over-length, under-length,
    truncated), invalid CBE bytes.

**Risk.**  Medium.  Backpressure under load is the historical
hard part.

**Effort.**  ~10 engineer-days.

---

### RH-D — `canon-event-subscribe` (Phase 5 WU 5.7)

**Finding map.**  WU 5.7 deferred per GENESIS_PLAN line 3823.

**Scope.**  `runtime/canon-event-subscribe/` — subscription
service that streams ordered events to subscribers.

**Implementation steps.**

  1. Crate skeleton.  Async (`tokio`).
  2. Reader: tail `log.jsonl` (the canonical event log) for new
    frames; extract events via `Events.extractEvents` (re-using
    the Lean library through subprocess or via a re-implemented
    Rust event-extraction function — recommend subprocess for
    soundness; the Lean side is the wire-format authority).
  3. Per-subscriber state: last sequence number sent, bounded
    backpressure (drop subscriber if it lags by more than N
    events).
  4. Wire format: small fixed header + CBE-encoded event
    payload.
  5. Re-subscribe-from-sequence support: subscriber sends a
    `resume <seq>` command; server replays from that sequence.

**Acceptance criteria.**

  * Ordering: events delivered strictly in log order.
  * Bounded lag: subscriber that falls behind by N events is
    disconnected with a "lag exceeded" frame.
  * Resume: a subscriber that disconnects and re-connects with
    `resume <seq>` receives the missing events.

**Test plan.**

  * Single subscriber: 1000 events, verify all received in
    order.
  * Lagged subscriber: subscriber sleeps; verify disconnect
    after threshold.
  * Resume: disconnect, reconnect, verify backfill.

**Risk.**  Medium.

**Effort.**  ~7 engineer-days.

---

### RH-E.0 — `canon-storage` (Rust DB layer)

**Finding map.**  Structural blocker for WU 5.8 per GENESIS_PLAN
line 3826.

**Scope.**  `runtime/canon-storage/` — a small abstraction crate
exposing a `Storage` trait with `get / put / scan` semantics,
plus a SQLite-backed implementation.

**Implementation steps.**

  1. Crate skeleton (library only).
  2. Define `trait Storage` with:
     ```rust
     trait Storage: Send + Sync {
         fn get(&self, key: &[u8]) -> Result<Option<Vec<u8>>>;
         fn put(&mut self, key: &[u8], value: &[u8]) -> Result<()>;
         fn delete(&mut self, key: &[u8]) -> Result<()>;
         fn scan(&self, prefix: &[u8]) -> Box<dyn Iterator<Item = (Vec<u8>, Vec<u8>)>>;
         fn snapshot(&self) -> Result<Box<dyn StorageSnapshot>>;
     }
     ```
  3. SQLite implementation via `rusqlite`.  Use a single-table
    schema: `kv(key BLOB PRIMARY KEY, value BLOB)`.
  4. Migration scaffolding: a `current_schema_version` row plus
    a list of `MigrationFn`s applied in order at open time.
  5. WAL mode enabled by default.

**Math / soundness.**

  * Storage operations are strictly read-write KV; no SQL surface
    is exposed to callers.
  * Snapshots use SQLite's WAL-mode read transactions for
    point-in-time consistency.
  * No async; SQLite is sync.  Callers wanting async run this
    on a blocking-task pool (`tokio::task::spawn_blocking`).

**Acceptance criteria.**

  * Trait surface stable (no `_v2` follow-ups expected).
  * 100% test coverage on the SQLite impl.
  * Migration regression: open a v1 schema with a v2 binary;
    confirm migration runs and idempotent re-open works.

**Risk.**  Low-medium.  Storage abstractions historically suffer
scope creep; resist.

**Effort.**  ~5 engineer-days.

---

### RH-E.1 — `canon-indexer` (Phase 5 WU 5.8)

**Finding map.**  WU 5.8 deferred per GENESIS_PLAN line 3826.

**Scope.**  `runtime/canon-indexer/` — daemon that consumes
events via `canon-event-subscribe` and maintains a per-resource
balance view in `canon-storage`.

**Implementation steps.**

  1. Crate skeleton.
  2. Subscribe to events; for each `Event.transfer` /
    `Event.mint` / `Event.burn` / `Event.deposit` / `Event.withdraw`,
    update the balance row keyed by `(actor, resource)`.
  3. Idempotency: track the last processed sequence number;
    on restart, resume from that sequence.
  4. Verification: `--verify-against-canon` flag that, for every
    actor, queries the live `canon-host` for the canonical
    balance and asserts equality.  Regression-test in CI.
  5. CLI: `canon-indexer query <actor> <resource>` for ad-hoc
    queries.

**Acceptance criteria.**

  * Balance view matches `canon-host`'s `getBalance` for
    arbitrary actors after a 10k-event load.
  * Idempotent restart: kill mid-stream, restart, no
    double-application.

**Risk.**  Low.

**Effort.**  ~6 engineer-days.

---

### RH-F — `canon-bench` (10k tx/sec benchmark, Phase 5 WU 5.11)

**Finding map.**  WU 5.11 deferred per GENESIS_PLAN line 3840.

**Scope.**  `runtime/canon-bench/benches/` — Criterion-style
benchmark suite measuring transfer-only throughput end-to-end.

**Implementation steps.**

  1. Pre-fund 1000 actor accounts with a synthetic genesis
    log.
  2. Generate 10000 valid transfer `SignedAction`s in advance.
  3. Submit them via `canon-host` over Unix socket (TCP adds
    spurious latency for benchmarking purposes); measure
    end-to-end p50 / p99 / p999.
  4. Target: ≥ 10k tx/sec sustained, p99 < 10 ms.
  5. If miss: profile (use `flamegraph` crate), identify
    bottlenecks (likely CBOR decode or RBMap rebalancing per
    GENESIS_PLAN line 3741), and either ship optimisations or
    document the gap in the benchmark report.

**Acceptance criteria.**

  * Benchmark suite runs in CI on a fixed reference machine.
  * Latency / throughput regression alerts if numbers drop by
    more than 10% over a baseline.

**Risk.**  High.  Performance targets historically drift;
mitigation is the profile-and-document escape hatch.

**Effort.**  ~5 engineer-days, plus 0–10 days optimisation work
depending on baseline performance.

---

### RH-G — `canon-faultproof-observer` (Workstream H, WU H.10.5)

**Finding map.**  H.10.5 deferred per
`LegalKernel/FaultProof/Witness.lean:65`; runbook drafted at
`docs/fault_proof_runbook.md` §7.

**Scope.**  `runtime/canon-faultproof-observer/` — daemon that
watches L1 for fault-proof game events, computes the honest
bisection response, and submits it.

**Implementation steps.**

  1. Crate skeleton.  Depend on `ethers-rs` for L1 RPC and on
    `canon-storage` for state persistence.
  2. L1 event watcher: subscribe to `CanonFaultProofGame`
    events (game opened, bisection responded, settlement).
  3. Honest-strategy computation: for each open game where the
    observer's deployment is a participant, compute the
    canonical Lean replay output via subprocess to the `canon`
    executable + the bisection-game state machine
    (`FaultProof/Game.lean` reference Rust port).
  4. Response submission: sign and submit transactions to the
    L1 game contract.
  5. Persistence: track each open game's state in
    `canon-storage`; resume after restart.

**Math / soundness.**

The observer's correctness rests on:
  - **Convergence theorem** (`bisection_converges_after_enough_rounds`,
    `LegalKernel/FaultProof/Convergence.lean`).  The honest
    strategy always converges to a winning settlement.
  - **Honesty theorem** (`honest_challenger_wins_against_invalid_state_root`,
    `LegalKernel/FaultProof/Settlement.lean`).  Submitting the
    canonical Lean reply at each bisection step wins.

The Rust observer is therefore *operationally* sound iff:
  - It submits the canonical Lean reply at each step (verified
    by byte-equality with the Lean subprocess output).
  - It does not miss a game (verified by L1 event-watch
    completeness, same machinery as RH-B's re-org handling).

**Acceptance criteria.**

  * Integration test against `anvil`: open an adversarial game
    with a wrong state root, run the observer, confirm the
    observer wins the bisection.
  * Cross-stack byte-equivalence: every observer response
    byte-equals the Lean reference produced by the same input.
  * Persistence: kill mid-game, restart, observer resumes and
    wins.

**Test plan.**

  * Unit: bisection-state-machine port matches Lean reference
    on the cross-stack corpus.
  * Integration: full game vs synthetic adversary on anvil.
  * Chaos: simulate L1 re-orgs during a game; observer must
    recover correctly.

**Risk.**  High.  The fault-proof observer is the most
operationally critical Rust deliverable; bugs here can cost
real money in adversarial settings.  Mitigation: extensive test
suite + documented "audit cellProof submissions off-chain"
mitigation already in place per GENESIS_PLAN §15B until SMT
cell-proofs ship (see `docs/smt_cell_proofs_plan.md`).
**Cross-workstream interaction:** when SC ships, the observer's
cell-proof construction (which RH-G calls "the canonical reply")
changes from the witness-state shape to the SMT-path shape.
RH-G should be implemented against the SMT shape from day one
(SC.1 ships the Lean reference); pre-SC, RH-G emits witness-
state proofs only as a fallback for L1 contracts that have not
upgraded to `SmtVerifier`.

**Effort.**  ~15 engineer-days.

---

## §5 Sequencing and PR structure

```
Sprint 1 (week 1–2)           RH-H (workspace)
Sprint 2 (week 3–4)           RH-A.1 + RH-A.2 (parallel)
Sprint 3 (week 5–6)           RH-C (depends on RH-A)
Sprint 4 (week 7–8)           RH-D + RH-B (parallel; depend on RH-H)
Sprint 5 (week 9–10)          RH-E.0 (DB layer)
Sprint 6 (week 11)            RH-E.1 (indexer)
Sprint 7 (week 12–14)         RH-G (observer)
Sprint 8 (week 15)            RH-F (benchmark)
```

Total: ~15 calendar weeks for one full-time engineer.  Two
engineers compress to ~9–10 weeks after RH-H.

PR title convention: `RH-<sub-unit>: <one-line summary>`.  Each
PR's CI must include the Rust workflow gate (introduced by RH-H).

## §6 Quality gates

  * `cargo build --workspace --all-targets`
  * `cargo test --workspace`
  * `cargo clippy --workspace --all-targets -- -D warnings`
  * `cargo fmt --all -- --check`
  * Cross-stack fixture corpus passes for the touched crate(s)
  * Lean-side gates (`lake build`, `lake test`, audits) remain
    green for any PR that touches the Lean side (most RH PRs
    don't).

## §7 Risk register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `lean-sys` / Lean FFI ABI drift across toolchain bumps | Medium | High | Pin Lean toolchain; vendor FFI bindings; re-verify on every bump |
| `ethers-rs` API churn | High | Medium | Pin a minor version; budget for upgrade work |
| Bench targets unmeetable on commodity hardware | Medium | Medium | Document gap; profile; ship optimisations as separate PRs |
| Observer re-org handling bug in production | Low | Catastrophic | Extensive chaos testing pre-deployment; documented mitigation (off-chain audit) |
| `canon-storage` schema migration loses data | Low | Catastrophic | Migrations are append-only; full backup taken before migration |
| Rust toolchain bump breaks reproducibility | Medium | Medium | Pin toolchain.toml; treat bumps as workspace-level PRs |

## §8 Acceptance criteria for the workstream

RH is **complete** when:

  1. Eight crates ship under `runtime/`.
  2. Cross-stack fixture corpus passes for all crates with a
    cross-stack contract (RH-A.1, RH-A.2, RH-C, RH-G).
  3. `cargo build --workspace` and `cargo test --workspace` are
    green on CI.
  4. Phase 5 status updates:
     - WU 5.4 → complete
     - WU 5.7 → complete
     - WU 5.8 → complete
     - WU 5.11 → complete (with benchmark report attached)
  5. Workstream H status update:
     - H.10.5 → complete; CLAUDE.md "Rust off-chain observer
       deferred" note removed.
  6. Workstream E-A status update:
     - E-A.1 / E-A.2 Rust adaptors → complete.
  7. Workstream E-B status update:
     - E-B Rust ingestor → complete.
  8. README.md and CLAUDE.md updated to reflect new build
    commands and status.
  9. `docs/abi.md` §10 (network ABI) finalised; placeholder
    line at line 724 retired.

## §9 Out-of-scope items

  * **Production deployment infrastructure** (Kubernetes,
    systemd units, monitoring dashboards).  Operator-team work.
  * **Multi-tenant `canon-host`** (one host serving multiple
    deployment IDs).  Single-deployment per host is sufficient
    for MVP; multi-tenant is a v2 concern.
  * **Hardware security module (HSM) integration** for the
    bridge-actor key.  Software-keystore is MVP; HSM is v2.
  * **Alternative DB backends** (RocksDB, foundationDB).
    SQLite is MVP; the `Storage` trait makes alternative
    backends a future drop-in.
  * **`canon-host` cluster mode** (load-balancing across multiple
    `canon` subprocesses).  Single-process is MVP.
  * **GraphQL / REST API layer.**  CBE wire format is the v1
    interface; richer APIs are v2.

## §10 References

  * `docs/abi.md` §10 (Network ABI placeholder; closed by RH-C).
  * `docs/GENESIS_PLAN.md` §12 Phase 5 status; §15B Workstream
    H Rust observer reference.
  * `docs/ethereum_integration_plan.md` §5 (E-A Rust adaptors),
    §11 (E-B Rust ingestor).
  * `docs/fault_proof_runbook.md` §7 (observer runbook
    skeleton).
  * `LegalKernel/Runtime/Hash.lean` — `@[extern]` swap-point
    declarations.
  * `LegalKernel/Authority/Crypto.lean` — `opaque Verify`
    declaration.
  * `LegalKernel/FaultProof/Witness.lean` — `opaque
    l1FaultProofVerifier` declaration.

---

**End of plan.**  Landing RH realises every production
swap-point and closes the four deferred Phase-5 work units, the
two deferred Ethereum Rust adaptors, the deferred L1 ingestor,
and the deferred fault-proof observer.
