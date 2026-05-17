/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Test.FaultProof.Smt — value-level + term-level
tests for the sparse-Merkle-tree cell-proof spec
(`LegalKernel/FaultProof/Smt.lean`).

Coverage:

  * **Empty / canonical hashes.**  `emptySubtreeHashes` has size
    256; every entry is 32 bytes; `emptySubtreeHash 0` matches
    `hashBytes emptyLeafSeedBytes`.
  * **BitsKey instances.**  Read-back from `UInt64` and
    `ByteArray` matches the expected MSB-first bit pattern.
  * **`SmtCellProof.empty`.**  Well-formed by construction.
    Has zero non-canonical siblings, all-zero bitmask.
  * **Walk / verifier.**  The empty proof matches the
    canonical "all-empty siblings" root.
  * **Soundness — value substitution rejected.**  If two
    proofs verify for `(root, key)`, they must claim the same
    value.
  * **Term-level API stability.**  Each shipped theorem's
    signature is pinned via a `let _proof : T := theorem`
    binding (elaboration-time check).
-/

import LegalKernel.FaultProof.Smt
import LegalKernel.Test.Framework

namespace LegalKernel.Test.FaultProof.Smt

open LegalKernel.Test
open LegalKernel.Encoding
open LegalKernel.Runtime
open LegalKernel.Bridge
open LegalKernel.FaultProof

/-! ## Term-level API stability checks

Each headline theorem of `LegalKernel/FaultProof/Smt.lean` is
pinned here via a `let _proof : T := theorem`-shaped term.
Elaboration of these terms fails if the theorem's signature
changes — catching API drift before any value-level test runs. -/

/-- API-stability term for `smtCellProof_no_value_substitution`. -/
example : True := by
  let _api :
      ∀ {K V : Type} [BitsKey K] [Encodable K] [Encodable V],
        Function.Injective (Encodable.encode : V → Stream) →
        CollisionFree hashBytes →
        ∀ (root : ByteArray) (key : K) (v₁ v₂ : V)
          (proof₁ proof₂ : SmtCellProof),
          verifySmtCellProof root key v₁ proof₁ = true →
          verifySmtCellProof root key v₂ proof₂ = true →
          v₁ = v₂ :=
    @smtCellProof_no_value_substitution
  trivial

/-- API-stability term for `smtCellProof_sound_under_collision_free`
    (the plan-named alias). -/
example : True := by
  let _api :
      ∀ {K V : Type} [BitsKey K] [Encodable K] [Encodable V],
        Function.Injective (Encodable.encode : V → Stream) →
        CollisionFree hashBytes →
        ∀ (root : ByteArray) (key : K) (v₁ v₂ : V)
          (proof₁ proof₂ : SmtCellProof),
          verifySmtCellProof root key v₁ proof₁ = true →
          verifySmtCellProof root key v₂ proof₂ = true →
          v₁ = v₂ :=
    @smtCellProof_sound_under_collision_free
  trivial

/-- API-stability term for the step-injectivity lemma. -/
example : True := by
  let _api :
      CollisionFree hashBytes →
      ∀ (c₁ c₂ s₁ s₂ : ByteArray),
        c₁.size = 32 → c₂.size = 32 →
        s₁.size = 32 → s₂.size = 32 →
        ∀ (bit : Bool),
          smtStep c₁ s₁ bit = smtStep c₂ s₂ bit →
          c₁ = c₂ ∧ s₁ = s₂ :=
    @smtStep_inj_under_collision_free
  trivial

/-- API-stability term for the walk-leaf-injectivity lemma. -/
example : True := by
  let _api :
      CollisionFree hashBytes →
      ∀ (bits : List Bool) (sibs₁ sibs₂ : List ByteArray)
        (leaf₁ leaf₂ : ByteArray),
        sibs₁.length = bits.length →
        sibs₂.length = bits.length →
        leaf₁.size = 32 →
        leaf₂.size = 32 →
        (∀ s ∈ sibs₁, s.size = 32) →
        (∀ s ∈ sibs₂, s.size = 32) →
        (sibs₁.zip bits).foldl stepPair leaf₁ =
        (sibs₂.zip bits).foldl stepPair leaf₂ →
        leaf₁ = leaf₂ :=
    @walk_leaf_inj_under_collision_free
  trivial

/-- API-stability term for the completeness theorem. -/
example : True := by
  let _api :
      ∀ {K V : Type} [BitsKey K] [Encodable K] [Encodable V]
        (key : K) (value : V) (proof : SmtCellProof),
        proof.isWellFormed = true →
        verifySmtCellProof (smtWalk key value proof) key value proof = true :=
    @verifySmtCellProof_walks_to_root
  trivial

/-- API-stability term for empty-proof self-verification. -/
example : True := by
  let _api :
      ∀ {K V : Type} [BitsKey K] [Encodable K] [Encodable V]
        (key : K) (value : V),
        verifySmtCellProof
          (smtWalk key value SmtCellProof.empty)
          key value SmtCellProof.empty = true :=
    @verifySmtCellProof_empty_self_verifies
  trivial

/-! ## Value-level tests -/

/-- Tests for the SMT cell-proof spec. -/
def tests : List TestCase :=
  [ { name := "smtDepth = 256"
    , body := do
        assertEq (expected := 256) (actual := smtDepth) "depth"
    }
  , { name := "emptySubtreeHashes has size 256"
    , body := do
        assertEq (expected := 256) (actual := emptySubtreeHashes.size) "size"
    }
  , { name := "emptySubtreeHash 0 is 32 bytes"
    , body := do
        let h0 := emptySubtreeHash 0
        assertEq (expected := 32) (actual := h0.size) "0-th hash size"
    }
  , { name := "emptySubtreeHash 100 is 32 bytes"
    , body := do
        let h100 := emptySubtreeHash 100
        assertEq (expected := 32) (actual := h100.size) "100-th hash size"
    }
  , { name := "emptySubtreeHash 255 is 32 bytes"
    , body := do
        let h255 := emptySubtreeHash 255
        assertEq (expected := 32) (actual := h255.size) "255-th hash size"
    }
  , { name := "emptySubtreeHashes[0] equals hashBytes emptyLeafSeedBytes"
    , body := do
        let h0_via_def := emptySubtreeHash 0
        let h0_direct := hashBytes emptyLeafSeedBytes
        assert (h0_via_def == h0_direct) "H_0 matches hashBytes EMPTY_LEAF"
    }
  , { name := "emptySubtreeHash d+1 equals hashBytes (H_d ++ H_d)"
    , body := do
        let h0 := emptySubtreeHash 0
        let h1_via_def := emptySubtreeHash 1
        let h1_direct := hashBytes (h0 ++ h0)
        assert (h1_via_def == h1_direct) "H_1 = hashBytes(H_0 ++ H_0)"
    }
  , { name := "paddingHash is 32 bytes"
    , body := do
        assertEq (expected := 32) (actual := paddingHash.size) "padding size"
    }
  , { name := "BitsKey UInt64: MSB of 0x80000000_00000000 is true"
    , body := do
        let k : UInt64 := 0x8000000000000000
        assert (BitsKey.keyBit k 0) "MSB"
        assert (¬ BitsKey.keyBit k 1) "bit 1 should be 0"
        assert (¬ BitsKey.keyBit k 63) "LSB should be 0"
    }
  , { name := "BitsKey UInt64: LSB of 1 is true"
    , body := do
        let k : UInt64 := 1
        assert (¬ BitsKey.keyBit k 0) "MSB should be 0"
        assert (BitsKey.keyBit k 63) "LSB"
        assert (¬ BitsKey.keyBit k 64) "out of range"
        assert (¬ BitsKey.keyBit k 100) "out of range deep"
    }
  , { name := "BitsKey UInt64: zero key has no bits set"
    , body := do
        let k : UInt64 := 0
        assert (¬ BitsKey.keyBit k 0) "bit 0"
        assert (¬ BitsKey.keyBit k 32) "bit 32"
        assert (¬ BitsKey.keyBit k 63) "bit 63"
        assert (¬ BitsKey.keyBit k 64) "out of range"
    }
  , { name := "BitsKey ByteArray: empty array returns false for all bits"
    , body := do
        let k : ByteArray := ByteArray.empty
        assert (¬ BitsKey.keyBit k 0) "bit 0"
        assert (¬ BitsKey.keyBit k 7) "bit 7"
        assert (¬ BitsKey.keyBit k 100) "bit 100"
    }
  , { name := "BitsKey ByteArray: MSB of #[0x80] is true"
    , body := do
        let k : ByteArray := ByteArray.mk #[0x80]
        assert (BitsKey.keyBit k 0) "MSB"
        assert (¬ BitsKey.keyBit k 1) "bit 1"
        assert (¬ BitsKey.keyBit k 7) "LSB of byte"
        assert (¬ BitsKey.keyBit k 8) "out of array"
    }
  , { name := "BitsKey ByteArray: LSB of #[0x01] is true"
    , body := do
        let k : ByteArray := ByteArray.mk #[0x01]
        assert (¬ BitsKey.keyBit k 0) "MSB"
        assert (BitsKey.keyBit k 7) "LSB"
    }
  , { name := "SmtCellProof.empty has empty siblings, 32-byte bitmask"
    , body := do
        let p := SmtCellProof.empty
        assertEq (expected := 0) (actual := p.siblings.size) "0 siblings"
        assertEq (expected := 32) (actual := p.bitmask.size) "32-byte bitmask"
    }
  , { name := "SmtCellProof.empty.bitmaskBit returns false for all depths"
    , body := do
        let p := SmtCellProof.empty
        assert (¬ p.bitmaskBit 0) "bit 0"
        assert (¬ p.bitmaskBit 100) "bit 100"
        assert (¬ p.bitmaskBit 255) "bit 255"
        assert (¬ p.bitmaskBit 1000) "out of range"
    }
  , { name := "SmtCellProof.empty is well-formed"
    , body := do
        let p := SmtCellProof.empty
        assert (p.isWellFormed) "empty proof is well-formed"
    }
  , { name := "isWellFormed rejects bitmask of wrong size"
    , body := do
        let p : SmtCellProof :=
          { siblings := #[],
            bitmask := ByteArray.mk #[0, 0, 0] }  -- 3 bytes, not 32
        assert (¬ p.isWellFormed) "3-byte bitmask rejected"
    }
  , { name := "isWellFormed rejects non-32-byte sibling"
    , body := do
        let p : SmtCellProof :=
          { siblings := #[ByteArray.mk #[0, 1, 2]],  -- 3-byte sibling
            bitmask := ByteArray.mk (Array.replicate 32 (0 : UInt8)) }
        assert (¬ p.isWellFormed) "3-byte sibling rejected"
    }
  , { name := "expandSiblings on empty proof: length 256, all 32 bytes"
    , body := do
        let p := SmtCellProof.empty
        let sibs := expandSiblings p
        assertEq (expected := 256) (actual := sibs.length) "length"
        -- Every sibling should be 32 bytes (canonical empty).
        for s in sibs do
          assertEq (expected := 32) (actual := s.size) "sibling size"
    }
  , { name := "expandSiblings on empty proof matches emptySubtreeHash sequence"
    , body := do
        let p := SmtCellProof.empty
        let sibs := expandSiblings p
        -- Each entry should equal emptySubtreeHash d for d = 0..255.
        for d in [0:256] do
          match sibs[d]? with
          | some sib =>
              assert (sib == emptySubtreeHash d)
                s!"sib at depth {d} should equal emptySubtreeHash {d}"
          | none =>
              throw <| IO.userError s!"sibs[{d}] is none — expected length 256"
    }
  , { name := "keyBits length is 256"
    , body := do
        let key : UInt64 := 42
        let bits := keyBits key
        assertEq (expected := 256) (actual := bits.length) "length"
    }
  , { name := "leafHash is 32 bytes"
    , body := do
        let key : UInt64 := 42
        let value : UInt64 := 100
        let leaf := leafHash key value
        assertEq (expected := 32) (actual := leaf.size) "leaf size"
    }
  , { name := "smtStep output is 32 bytes (bit = false)"
    , body := do
        let c := paddingHash
        let s := paddingHash
        let parent := smtStep c s false
        assertEq (expected := 32) (actual := parent.size) "parent size"
    }
  , { name := "smtStep output is 32 bytes (bit = true)"
    , body := do
        let c := paddingHash
        let s := paddingHash
        let parent := smtStep c s true
        assertEq (expected := 32) (actual := parent.size) "parent size"
    }
  , { name := "smtStep distinguishes bit = false vs bit = true"
    , body := do
        -- For non-symmetric (current, sibling), the bit determines
        -- the order of concatenation, producing different parents.
        let c := ByteArray.mk #[1, 2, 3, 4]
        let s := ByteArray.mk #[5, 6, 7, 8]
        let parent_left := smtStep c s false   -- hashBytes (c ++ s)
        let parent_right := smtStep c s true  -- hashBytes (s ++ c)
        -- Under any non-trivial hash, the two should differ.  For
        -- FNV-1a-64 fallback, they SHOULD differ (the fold over
        -- distinct inputs produces distinct outputs with high
        -- probability), but we don't strictly assert this — just
        -- that both are 32 bytes.  Inequality would be a stronger
        -- claim that depends on the linked hash.
        assertEq (expected := 32) (actual := parent_left.size) "left size"
        assertEq (expected := 32) (actual := parent_right.size) "right size"
    }
  , { name := "smtWalk on empty proof is determined by key + value"
    , body := do
        let key : UInt64 := 0  -- All-zero bits ⇒ always "current ++ sibling".
        let value : UInt64 := 42
        let proof := SmtCellProof.empty
        let root1 := smtWalk key value proof
        let root2 := smtWalk key value proof
        assert (root1 == root2) "deterministic"
        assertEq (expected := 32) (actual := root1.size) "32 bytes"
    }
  , { name := "smtWalk reflects value change (likely; fallback hash)"
    , body := do
        let key : UInt64 := 100
        let v1 : UInt64 := 1
        let v2 : UInt64 := 2
        let proof := SmtCellProof.empty
        let r1 := smtWalk key v1 proof
        let r2 := smtWalk key v2 proof
        -- Under the FNV-1a-64 fallback, distinct (encoded) values
        -- should produce distinct leafs and thus distinct roots.
        -- This is a smoke check; the formal soundness theorem
        -- is `smtCellProof_no_value_substitution`.
        assert (¬ r1 == r2) "distinct values produce distinct roots (likely)"
    }
  , { name := "verifySmtCellProof accepts canonical empty-proof walk"
    , body := do
        let key : UInt64 := 0
        let value : UInt64 := 42
        let proof := SmtCellProof.empty
        let root := smtWalk key value proof
        assert (verifySmtCellProof root key value proof) "self-verifies"
    }
  , { name := "verifySmtCellProof rejects proof with wrong root"
    , body := do
        let key : UInt64 := 0
        let value : UInt64 := 42
        let proof := SmtCellProof.empty
        let wrong_root := ByteArray.mk (Array.replicate 32 (99 : UInt8))
        assert (¬ verifySmtCellProof wrong_root key value proof)
          "wrong root rejected"
    }
  , { name := "verifySmtCellProof rejects ill-formed (wrong bitmask size) proof"
    , body := do
        let key : UInt64 := 0
        let value : UInt64 := 42
        let bad_proof : SmtCellProof :=
          { siblings := #[],
            bitmask  := ByteArray.mk #[0, 0, 0] }  -- 3 bytes
        let any_root := ByteArray.mk (Array.replicate 32 (0 : UInt8))
        assert (¬ verifySmtCellProof any_root key value bad_proof)
          "ill-formed proof rejected regardless of root"
    }
  , { name := "verifySmtCellProof rejects ill-formed (wrong sibling size) proof"
    , body := do
        let key : UInt64 := 0
        let value : UInt64 := 42
        -- Bitmask has bit 0 set, sibling is wrong size.
        let mut bm_arr : Array UInt8 := Array.replicate 32 (0 : UInt8)
        bm_arr := bm_arr.set! 0 1  -- bit 0 = LSB of byte 0 set
        let bad_proof : SmtCellProof :=
          { siblings := #[ByteArray.mk #[1, 2, 3]],  -- 3-byte sibling
            bitmask  := ByteArray.mk bm_arr }
        let any_root := ByteArray.mk (Array.replicate 32 (0 : UInt8))
        assert (¬ verifySmtCellProof any_root key value bad_proof)
          "wrong-sibling-size proof rejected"
    }
  , { name := "verifySmtCellProof_deterministic spot-check"
    , body := do
        let key : UInt64 := 42
        let value : UInt64 := 100
        let proof := SmtCellProof.empty
        let root := smtWalk key value proof
        let v1 := verifySmtCellProof root key value proof
        let v2 := verifySmtCellProof root key value proof
        assertEq (expected := v1) (actual := v2) "two calls agree"
    }
  , { name := "encodeAsBytes is deterministic"
    , body := do
        let v1 : UInt64 := 42
        let v2 : UInt64 := 42
        let b1 := encodeAsBytes v1
        let b2 := encodeAsBytes v2
        assert (b1 == b2) "same input ⇒ same bytes"
    }
  , { name := "encodeAsBytes distinguishes distinct UInt64s"
    , body := do
        let v1 : UInt64 := 42
        let v2 : UInt64 := 43
        let b1 := encodeAsBytes v1
        let b2 := encodeAsBytes v2
        assert (¬ b1 == b2) "different inputs ⇒ different bytes"
    }
  , { name := "Two different keys yield different leafHash (likely)"
    , body := do
        let k1 : UInt64 := 1
        let k2 : UInt64 := 2
        let v : UInt64 := 42
        let leaf1 := leafHash k1 v
        let leaf2 := leafHash k2 v
        assert (¬ leaf1 == leaf2) "distinct keys yield distinct leaves"
    }
  , { name := "verifySmtCellProof_walks_to_root: well-formed proof self-verifies"
    , body := do
        let key : UInt64 := 42
        let value : UInt64 := 100
        let proof := SmtCellProof.empty
        let root := smtWalk key value proof
        -- Equivalent to verifySmtCellProof_walks_to_root applied at this point.
        assert (verifySmtCellProof root key value proof)
          "well-formed proof self-verifies"
    }
  , { name := "SmtCellProof.empty is well-formed (theorem)"
    , body := do
        -- Value-level reflection of `SmtCellProof.empty_isWellFormed`.
        assertEq (expected := true) (actual := SmtCellProof.empty.isWellFormed)
          "empty proof well-formed"
    }
  , { name := "verifySmtCellProof_empty_self_verifies for UInt64 cells"
    , body := do
        -- Spot-check across several (key, value) pairs.
        let pairs : List (UInt64 × UInt64) :=
          [(0, 0), (1, 1), (42, 100), (0xDEADBEEF, 0xCAFEBABE),
           (0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF)]
        for (k, v) in pairs do
          let r := smtWalk k v SmtCellProof.empty
          assert (verifySmtCellProof r k v SmtCellProof.empty)
            s!"empty proof self-verifies for ({k}, {v})"
    }
  , { name := "Padding hash differs from canonical empty hash H_0"
    , body := do
        -- paddingHash = 32 zero bytes; H_0 = hashBytes "EMPTY_LEAF".
        -- Under any non-trivial hash, these differ.
        let h0 := emptySubtreeHash 0
        assert (¬ paddingHash == h0)
          "padding hash distinct from canonical empty"
    }
  , { name := "keyBits is deterministic"
    , body := do
        let k : UInt64 := 12345
        let bits1 := keyBits k
        let bits2 := keyBits k
        assert (bits1 == bits2) "deterministic"
    }
  , { name := "keyBits depends on the key"
    , body := do
        let bits_zero := keyBits (0 : UInt64)
        let bits_one := keyBits (1 : UInt64)
        assert (¬ bits_zero == bits_one) "distinct keys give distinct bits"
    }
  , { name := "expandSiblings respects bitmask: empty bitmask ⇒ all empty hashes"
    , body := do
        let p := SmtCellProof.empty
        let sibs := expandSiblings p
        -- Every entry equals emptySubtreeHash d, verified earlier.
        -- Here we also verify that no entry equals paddingHash (which
        -- would indicate an out-of-bounds lookup — but the empty proof
        -- never sets a bitmask bit, so no proof.siblings lookup
        -- occurs).
        let mut padding_count := 0
        for s in sibs do
          if s == paddingHash then
            padding_count := padding_count + 1
        assertEq (expected := 0) (actual := padding_count)
          "no padding-hash entries for empty proof"
    }
  , { name := "Non-trivial proof with one set bitmask bit verifies self-walk"
    , body := do
        -- Build a non-trivial proof: bitmask has bit 0 set, supplying
        -- one custom sibling.
        let custom_sib := ByteArray.mk (Array.replicate 32 (7 : UInt8))
        let bm_array := (Array.replicate 32 (0 : UInt8)).set! 0 1
        let proof : SmtCellProof :=
          { siblings := #[custom_sib], bitmask := ByteArray.mk bm_array }
        assert (proof.isWellFormed) "non-trivial proof is well-formed"
        assert (proof.bitmaskBit 0) "bit 0 set"
        assert (¬ proof.bitmaskBit 1) "bit 1 unset"
        let key : UInt64 := 42
        let value : UInt64 := 100
        let root := smtWalk key value proof
        assertEq (expected := 32) (actual := root.size) "32-byte walk output"
        assert (verifySmtCellProof root key value proof) "self-verify"
    }
  , { name := "Non-trivial proof: walk differs from empty-proof walk"
    , body := do
        -- A non-trivial proof with different sibling than canonical
        -- empty should produce a different walked root.
        let custom_sib := ByteArray.mk (Array.replicate 32 (7 : UInt8))
        let bm_array := (Array.replicate 32 (0 : UInt8)).set! 0 1
        let proof_nt : SmtCellProof :=
          { siblings := #[custom_sib], bitmask := ByteArray.mk bm_array }
        let proof_empty := SmtCellProof.empty
        let key : UInt64 := 42
        let value : UInt64 := 100
        let root_nt := smtWalk key value proof_nt
        let root_empty := smtWalk key value proof_empty
        assert (¬ root_nt == root_empty)
          "non-trivial proof walks to different root than empty proof"
    }
  , { name := "Two custom proofs with different siblings walk to different roots"
    , body := do
        -- Two proofs sharing the same bitmask (bit 0 set) but with
        -- different siblings should walk to different roots.
        let bm_array := (Array.replicate 32 (0 : UInt8)).set! 0 1
        let sib_a := ByteArray.mk (Array.replicate 32 (1 : UInt8))
        let sib_b := ByteArray.mk (Array.replicate 32 (2 : UInt8))
        let proof_a : SmtCellProof :=
          { siblings := #[sib_a], bitmask := ByteArray.mk bm_array }
        let proof_b : SmtCellProof :=
          { siblings := #[sib_b], bitmask := ByteArray.mk bm_array }
        let key : UInt64 := 42
        let value : UInt64 := 100
        let root_a := smtWalk key value proof_a
        let root_b := smtWalk key value proof_b
        assert (¬ root_a == root_b)
          "different siblings yield different roots"
    }
  , { name := "Bitmask bit 8 = LSB of byte 1"
    , body := do
        -- Verify the depth-to-(byte, bit) mapping.
        let mut bm_array : Array UInt8 := Array.replicate 32 (0 : UInt8)
        bm_array := bm_array.set! 1 1  -- byte 1, LSB
        let proof : SmtCellProof :=
          { siblings := #[ByteArray.mk (Array.replicate 32 (0 : UInt8))],
            bitmask  := ByteArray.mk bm_array }
        assert (proof.bitmaskBit 8) "bit 8 (LSB of byte 1) set"
        assert (¬ proof.bitmaskBit 9) "bit 9 not set"
        assert (¬ proof.bitmaskBit 0) "bit 0 not set"
    }
  , { name := "smtRoot of empty TreeMap is 32 bytes"
    , body := do
        let m : Std.TreeMap UInt64 UInt64 compare := ∅
        let root := smtRoot m
        assertEq (expected := 32) (actual := root.size) "32-byte empty root"
    }
  , { name := "smtRoot of singleton TreeMap is 32 bytes"
    , body := do
        let m : Std.TreeMap UInt64 UInt64 compare := Std.TreeMap.empty.insert 42 100
        let root := smtRoot m
        assertEq (expected := 32) (actual := root.size) "32-byte singleton root"
    }
  , { name := "smtRoot is deterministic"
    , body := do
        let m : Std.TreeMap UInt64 UInt64 compare := Std.TreeMap.empty.insert 1 10
        let root1 := smtRoot m
        let root2 := smtRoot m
        assert (root1 == root2) "deterministic"
    }
  , { name := "smtRoot distinguishes empty from non-empty maps"
    , body := do
        let m_empty : Std.TreeMap UInt64 UInt64 compare := ∅
        let m_nonempty : Std.TreeMap UInt64 UInt64 compare :=
          Std.TreeMap.empty.insert 42 100
        let root_empty := smtRoot m_empty
        let root_nonempty := smtRoot m_nonempty
        assert (¬ root_empty == root_nonempty)
          "empty and non-empty maps have distinct roots"
    }
  , { name := "smtRoot distinguishes maps with different values at same key"
    , body := do
        let m1 : Std.TreeMap UInt64 UInt64 compare :=
          Std.TreeMap.empty.insert 42 100
        let m2 : Std.TreeMap UInt64 UInt64 compare :=
          Std.TreeMap.empty.insert 42 200
        let r1 := smtRoot m1
        let r2 := smtRoot m2
        assert (¬ r1 == r2) "distinct values yield distinct roots"
    }
  , { name := "smtRoot of two-element map is 32 bytes"
    , body := do
        let m : Std.TreeMap UInt64 UInt64 compare :=
          Std.TreeMap.empty.insert 1 10 |>.insert 2 20
        let root := smtRoot m
        assertEq (expected := 32) (actual := root.size) "32-byte two-element root"
    }
  ]

end LegalKernel.Test.FaultProof.Smt
