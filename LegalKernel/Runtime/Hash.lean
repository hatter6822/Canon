/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Runtime.Hash — deterministic content hash for the
runtime's log-chain, snapshot identifiers, and torn-write detection.

Phase 5 WU 5.1 (foundation) / WU 5.2 / WU 5.5 / WU 5.12.

Genesis Plan §8.8.4 calls for **BLAKE3** (256-bit output) for
`ActionHash`, `LogEntryHash`, `StateHash`, and `GenesisHash`.  BLAKE3
is not part of Lean core and the kernel's "Std core only" rule
forbids pulling in a third-party crypto library.  Phase 5 ships a
**deterministic Lean-native fallback** — the well-known FNV-1a-64
hash — so that the runtime, replay tool, and snapshot machinery can
compose end-to-end without an external dependency, and so that every
chain-related theorem (`hashBytes_deterministic`,
`hashStream_deterministic`) is provable inside Lean.

**Production deployments MUST replace `hashBytes` with BLAKE3 via
`@[extern]` linkage to a vetted C/Rust implementation.**  The runtime
adaptor (Genesis Plan §8.8.4 + §13.2) is the right boundary for that
swap: the Phase-5 Lean modules call `hashBytes` through the
`LegalKernel.Runtime.Hash` API, so a single FFI shim replaces the
entire fallback without touching kernel or law modules.

The fallback's collision-resistance is **64 bits** (vs BLAKE3's 256).
This is sufficient for:

  * **Torn-write detection.**  WU 5.2 / 5.3's framing uses the hash
    to detect partial writes; an attacker would have to find a
    pre-image, not a collision, and torn-write detection only needs
    to distinguish the truncation point from a complete frame.
  * **Replay verification.**  WU 5.5 compares the runtime's
    on-the-fly state hash with the replay tool's recomputed hash;
    both call into the same Lean function, so any discrepancy
    indicates a non-deterministic computation (a kernel bug), not a
    hash collision.
  * **Snapshot identification.**  WU 5.12's snapshots are identified
    by their state hash; the same in-Lean-only verification applies.

The fallback is **NOT** sufficient for adversarial settings (an
attacker could construct two `LogEntry`s with the same `LogEntryHash`
and bypass the chain's tamper-evidence in 2³² operations).
Production deployments swap to BLAKE3 to recover the §8.8.4 security
bound.

This module is **not** part of the trusted computing base: bugs here
produce wrong on-disk hashes, but cannot violate any kernel
invariant.  The kernel's correctness theorems do not depend on
hashing at all.
-/

import LegalKernel.Encoding.CBOR
import LegalKernel.Encoding.Encodable

namespace LegalKernel
namespace Runtime

open Encoding

/-! ## FNV-1a-64 constants

The standard FNV-1a-64 constants from
<http://www.isthe.com/chongo/tech/comp/fnv/>.  These are not secret
parameters; they are part of the FNV-1a specification and any other
FNV-1a implementation produces identical bytes for the same input
(determinism across compatible implementations is the only property
the runtime relies on). -/

/-- FNV-1a-64 offset basis: 14695981039346656037 = 0xcbf29ce484222325. -/
def fnvOffsetBasis : UInt64 := 0xcbf29ce484222325

/-- FNV-1a-64 prime: 1099511628211 = 0x100000001b3. -/
def fnvPrime : UInt64 := 0x100000001b3

/-! ## Core hash function

FNV-1a-64 over a `List UInt8` (= `Stream` in the Encoding namespace):
fold the standard `(acc XOR byte) * prime` step from the offset basis.
-/

/-- FNV-1a-64 of a byte stream.  Returns the 64-bit hash as a `UInt64`.

    The fold step is `acc' := (acc XOR b.toUInt64) * fnvPrime`, run
    over each byte of the input.  `UInt64` arithmetic wraps modulo
    `2^64`, which is exactly the FNV-1a-64 specification.

    Determinism: `fnv1a64Stream` is a `def`, so equal inputs trivially
    produce equal outputs (`fnv1a64Stream_deterministic`). -/
def fnv1a64Stream (bs : Stream) : UInt64 :=
  bs.foldl (fun acc b => (acc ^^^ b.toUInt64) * fnvPrime) fnvOffsetBasis

/-- FNV-1a-64 of a `ByteArray`.  Forwards to `fnv1a64Stream` via
    `ByteArray.toList`. -/
def fnv1a64Bytes (bs : ByteArray) : UInt64 :=
  fnv1a64Stream bs.toList

/-! ## Content hash type

A `ContentHash` is the runtime-layer identifier for a hashed value.
Phase 5 stores the FNV-1a-64 hash as an 8-byte little-endian
`ByteArray` for uniform handling with the future BLAKE3-256 form
(which would be 32 bytes).  The runtime adaptor's FFI shim widens
the byte array to whatever the production hash function emits without
changing the Lean-side type. -/

/-- A content hash: 8 bytes (FNV-1a-64) at the Lean fallback level,
    32 bytes (BLAKE3-256) at the production runtime-adaptor level.
    Stored as `ByteArray` so the same type carries both forms. -/
abbrev ContentHash : Type := ByteArray

/-- Pack a `UInt64` as 8 little-endian bytes.  Used to serialise the
    FNV-1a-64 result as a `ContentHash`. -/
def uint64ToBytesLE (n : UInt64) : ByteArray :=
  ByteArray.mk (natToBytesLE n.toNat 8).toArray

/-- Hash a byte stream and return the 8-byte little-endian `ContentHash`.
    Top-level entry point used by `Runtime/LogFile.lean`,
    `Runtime/Replay.lean`, and `Runtime/Snapshot.lean`. -/
def hashStream (bs : Stream) : ContentHash :=
  uint64ToBytesLE (fnv1a64Stream bs)

/-- Hash a `ByteArray` and return the 8-byte little-endian
    `ContentHash`. -/
def hashBytes (bs : ByteArray) : ContentHash :=
  uint64ToBytesLE (fnv1a64Bytes bs)

/-- Hash an `Encodable` value via its CBE bytes.  Convenience wrapper
    that composes `Encodable.encodeBytes` with `hashBytes`. -/
def hashEncodable {T : Type} [Encodable T] (v : T) : ContentHash :=
  hashBytes (Encodable.encodeBytes v)

/-! ## The empty / "zero" content hash

A 32-byte zero array — distinguishable from any genuine
`hashBytes` output (which is at least one byte and computes through
the FNV chain).  Used as the `prevHash` of the genesis log entry
(no predecessor exists). -/

/-- The zero content hash: 32 zero bytes.  Used as the `prevHash`
    seed of the chain (the value written into the first log entry's
    `prevHash` field). -/
def zeroHash : ContentHash :=
  ByteArray.mk (Array.replicate 32 (0 : UInt8))

/-! ## Determinism (the headline property)

`hashBytes` and friends are pure Lean functions, so equal inputs
trivially produce equal outputs.  Stated explicitly so the Phase-5
acceptance gate ("the replay tool reproduces the runtime's state
hash") is documented. -/

/-- Determinism: equal byte inputs produce equal hashes. -/
theorem hashBytes_deterministic (bs₁ bs₂ : ByteArray) (h : bs₁ = bs₂) :
    hashBytes bs₁ = hashBytes bs₂ :=
  h ▸ rfl

/-- Determinism: equal stream inputs produce equal hashes. -/
theorem hashStream_deterministic (s₁ s₂ : Stream) (h : s₁ = s₂) :
    hashStream s₁ = hashStream s₂ :=
  h ▸ rfl

/-- Determinism: equal `Encodable` inputs produce equal hashes. -/
theorem hashEncodable_deterministic {T : Type} [Encodable T]
    (v₁ v₂ : T) (h : v₁ = v₂) :
    hashEncodable v₁ = hashEncodable v₂ :=
  h ▸ rfl

/-! ## Output-shape lemma

The hash output is exactly 8 bytes (FNV-1a-64 width).  Consumers can
assume this when packing / unpacking hash values into log entries. -/

/-- The FNV-1a-64 hash output is exactly 8 bytes. -/
theorem hashBytes_size (bs : ByteArray) : (hashBytes bs).size = 8 := by
  show (uint64ToBytesLE _).size = 8
  unfold uint64ToBytesLE
  show (List.toArray _).size = 8
  rw [List.size_toArray, natToBytesLE_length]

/-- Same shape lemma for `hashStream`. -/
theorem hashStream_size (bs : Stream) : (hashStream bs).size = 8 := by
  show (uint64ToBytesLE _).size = 8
  unfold uint64ToBytesLE
  show (List.toArray _).size = 8
  rw [List.size_toArray, natToBytesLE_length]

/-- The zero hash has the documented shape (32 bytes — matching
    BLAKE3-256 width even though FNV-1a-64 only fills 8). -/
theorem zeroHash_size : zeroHash.size = 32 := rfl

end Runtime
end LegalKernel
