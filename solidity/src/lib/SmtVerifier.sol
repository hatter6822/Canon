// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/// @title SmtVerifier
/// @notice Solidity port of `LegalKernel.Bridge.WithdrawalRoot.verifyProof`
///         (workstream D.1.2 / D.1.4).  Re-computes the SMT root from a
///         leaf, an index, and a sibling path; compares to the asserted
///         root; returns the boolean equivalence.
///
/// @dev    **Mathematical invariants** (must mirror Lean exactly):
///
///         1. Tree height `SMT_HEIGHT = 64` (matches WithdrawalId domain).
///         2. Sibling array is **root-to-leaf ordered**: `siblings[0]` is
///            root-adjacent, `siblings[63]` is leaf-adjacent.
///         3. Path-bit indexing is **LSB-up**: `bit_k = (idx >> k) & 1`,
///            where `bit_0` selects at the leaf level and `bit_63` at
///            the root level.
///         4. Per-level combinator `hashUp`:
///              - `bit = 0` (left child): `keccak256(current ‖ sibling)`
///              - `bit = 1` (right child): `keccak256(sibling ‖ current)`
///
///         The Solidity recursion in Lean unfolds as: at level `k+1`
///         with sibling `s`, we recurse on the tail with level `k`,
///         then on unwind compute `hashUp(bit_k, inner, s)`.  The
///         iterative form below processes siblings from the
///         leaf-adjacent end (last in the array) up to the root-
///         adjacent end (first in the array), with the bit incrementing
///         from 0 to 63 — exactly mirroring the unwinding order.
///
///         **Cross-stack soundness** (verified by F.1.5 fixtures):
///         the verifier accepts a proof iff the canonical Lean
///         constructor would accept it, byte-for-byte.
library SmtVerifier {
    /// @notice Tree height; matches Lean's `smtHeight`.
    uint256 internal constant SMT_HEIGHT = 64;

    /// @notice Reverts when the supplied proof's siblings array does
    ///         not have exactly `SMT_HEIGHT` entries.  This is a
    ///         shape error — the on-chain decoder for `WithdrawalProof`
    ///         must produce a 64-element vector matching Lean's
    ///         `Vector ByteArray smtHeight`.
    error SmtBadProofShape(uint256 expected, uint256 actual);

    /// @notice Reverts when any sibling is not exactly 32 bytes.
    ///         Used for the canonical "all canonical siblings = 32"
    ///         soundness corollary (Audit-2's
    ///         `verifyProof_sound_all_32`).
    error SmtBadSiblingSize(uint256 level, uint256 actualSize);

    /// @notice Compute the SMT root from a leaf at index `idx` plus
    ///         a sibling path.  Returns the recomputed root.  Caller
    ///         compares to the asserted root.
    ///
    ///         `siblings.length` MUST equal `SMT_HEIGHT`; reverts
    ///         with `SmtBadProofShape` otherwise.
    ///
    ///         Caller is responsible for keccak256 binding.  The
    ///         function uses Solidity's built-in `keccak256` opcode
    ///         (matches the Lean `hashAdaptor` "keccak256" linked
    ///         binding per workstream A.2).
    function recomputeRoot(uint256 idx, bytes32 leaf, bytes32[] memory siblings)
        internal
        pure
        returns (bytes32 root)
    {
        if (siblings.length != SMT_HEIGHT) {
            revert SmtBadProofShape(SMT_HEIGHT, siblings.length);
        }

        bytes32 current = leaf;
        unchecked {
            for (uint256 i = 0; i < SMT_HEIGHT; ++i) {
                // i = 0 → use leaf-adjacent sibling (siblings[63]),
                //         bit at level 0 (idx & 1).
                // i = 63 → use root-adjacent sibling (siblings[0]),
                //          bit at level 63 ((idx >> 63) & 1).
                // Lean's `verifyProofRec` unwinds in this exact order.
                bytes32 sibling = siblings[SMT_HEIGHT - 1 - i];
                uint256 bit = (idx >> i) & 1;
                if (bit == 1) {
                    // current is the right child; sibling is on the left.
                    current = keccak256(abi.encodePacked(sibling, current));
                } else {
                    // current is the left child; sibling is on the right.
                    current = keccak256(abi.encodePacked(current, sibling));
                }
            }
        }
        root = current;
    }

    /// @notice Verify a withdrawal proof against an asserted root.
    ///         Returns `true` iff the recomputed root matches.
    function verifyProof(uint256 idx, bytes32 leaf, bytes32[] memory siblings, bytes32 root)
        internal
        pure
        returns (bool)
    {
        return recomputeRoot(idx, leaf, siblings) == root;
    }

    /// @notice The level-`i` "all-empty subtree" hash — mirror of
    ///         Lean's `defaultHash`.  Used by the canonical
    ///         "non-membership" proof shape and for fixture
    ///         constructors.
    ///
    ///         `emptyHashAtLevel(0) = bytes32(0)` (the
    ///         `emptyLeafHash` sentinel; matches Lean's `zeroHash`).
    ///         `emptyHashAtLevel(i+1) = keccak256(prev ‖ prev)`.
    ///
    ///         Computes recursively in O(level) gas — for production
    ///         use the `defaultHashTop()` constant if the top level
    ///         is needed.
    function emptyHashAtLevel(uint256 level) internal pure returns (bytes32 h) {
        h = bytes32(0);
        unchecked {
            for (uint256 i = 0; i < level; ++i) {
                h = keccak256(abi.encodePacked(h, h));
            }
        }
    }

    /// @notice The top-level empty-subtree hash for the standard
    ///         `SMT_HEIGHT = 64` tree.  Computed once on first call
    ///         then cached at the call site (callers should store
    ///         the result in an `immutable` field).  Provided as a
    ///         convenience for tests; the contract's constructor
    ///         takes its own snapshot to avoid the recompute cost on
    ///         every read.
    function defaultHashTop() internal pure returns (bytes32) {
        return emptyHashAtLevel(SMT_HEIGHT);
    }
}
