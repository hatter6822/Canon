// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SmtVerifier} from "src/lib/SmtVerifier.sol";

/// @title SmtVerifierProxy
/// @notice External wrapper around `SmtVerifier`'s internal library
///         functions so test fixtures can be passed as `bytes32[]
///         memory` and converted to the internal calldata signature.
contract SmtVerifierProxy {
    function recomputeRoot(uint256 idx, bytes32 leaf, bytes32[] memory siblings)
        external
        pure
        returns (bytes32)
    {
        return SmtVerifier.recomputeRoot(idx, leaf, siblings);
    }

    function verifyProof(uint256 idx, bytes32 leaf, bytes32[] memory siblings, bytes32 root)
        external
        pure
        returns (bool)
    {
        return SmtVerifier.verifyProof(idx, leaf, siblings, root);
    }

    function emptyHashAtLevel(uint256 level) external pure returns (bytes32) {
        return SmtVerifier.emptyHashAtLevel(level);
    }

    function defaultHashTop() external pure returns (bytes32) {
        return SmtVerifier.defaultHashTop();
    }
}

/// @title SmtVerifierTest
/// @notice Tests for the SMT verifier.  Each test exercises one
///         invariant; the suite is the on-chain mirror of Lean's
///         `Test/Bridge/WithdrawalRoot.lean` core property tests.
contract SmtVerifierTest is Test {
    SmtVerifierProxy private smt;

    /// @notice The level-`i` empty-subtree hash, recomputed once
    ///         per test for deterministic comparison.
    bytes32 private emptyAt0; // = bytes32(0)
    bytes32 private emptyAt1; // = keccak256(0 ‖ 0)
    bytes32 private emptyAt63; // leaf-of-root level
    bytes32 private emptyAt64; // root level

    function setUp() public {
        smt = new SmtVerifierProxy();
        emptyAt0 = bytes32(0);
        emptyAt1 = keccak256(abi.encodePacked(bytes32(0), bytes32(0)));
        emptyAt63 = smt.emptyHashAtLevel(63);
        emptyAt64 = smt.emptyHashAtLevel(64);
    }

    // ---- emptyHashAtLevel tests ----

    function test_emptyHashAtLevel_zero_is_zero_bytes32() public view {
        assertEq(smt.emptyHashAtLevel(0), bytes32(0));
    }

    function test_emptyHashAtLevel_one_recursion_step() public view {
        bytes32 expected = keccak256(abi.encodePacked(bytes32(0), bytes32(0)));
        assertEq(smt.emptyHashAtLevel(1), expected);
    }

    function test_emptyHashAtLevel_two_recursion_steps() public view {
        bytes32 step1 = keccak256(abi.encodePacked(bytes32(0), bytes32(0)));
        bytes32 step2 = keccak256(abi.encodePacked(step1, step1));
        assertEq(smt.emptyHashAtLevel(2), step2);
    }

    function test_emptyHashAtLevel_64_matches_defaultHashTop() public view {
        assertEq(smt.emptyHashAtLevel(64), smt.defaultHashTop());
    }

    // ---- recomputeRoot / verifyProof shape tests ----

    function test_recomputeRoot_revert_on_wrong_siblings_length() public {
        bytes32[] memory short_ = new bytes32[](63);
        vm.expectRevert(abi.encodeWithSelector(SmtVerifier.SmtBadProofShape.selector, 64, 63));
        smt.recomputeRoot(0, bytes32(0), short_);
    }

    /// @notice The all-empty proof for an empty-leaf at index 0
    ///         should recompute to the empty-tree top hash.
    function test_recomputeRoot_empty_proof_at_index_0_returns_top_default() public view {
        bytes32[] memory siblings = _emptyProofSiblings();
        bytes32 root = smt.recomputeRoot(0, bytes32(0), siblings);
        assertEq(root, emptyAt64);
    }

    /// @notice Same as above but at a different index.  The root
    ///         should still be the empty-tree top hash because
    ///         `bit ? H(s ‖ c) : H(c ‖ s)` with `c = s = defaultHash`
    ///         collapses identically regardless of bit.
    function test_recomputeRoot_empty_proof_at_arbitrary_index() public view {
        bytes32[] memory siblings = _emptyProofSiblings();
        bytes32 root = smt.recomputeRoot(0xDEADBEEF, bytes32(0), siblings);
        assertEq(root, emptyAt64);
    }

    /// @notice A populated leaf at index 0 with all-empty siblings:
    ///         the root should be the canonical hash chain
    ///         leaf → H(leaf ‖ emptyAt0) → H(prev ‖ emptyAt1) → ...
    ///         (since bit_k = 0 for all k when idx = 0).
    function test_recomputeRoot_populated_leaf_index_0() public view {
        bytes32 leaf = keccak256("withdrawal-fixture-1");
        bytes32[] memory siblings = _emptyProofSiblings();
        bytes32 expected = leaf;
        // For idx = 0, every bit is 0, so combiner is `H(current ‖ sibling)`.
        // The siblings the verifier consumes (in unwind order from leaf)
        // are siblings[63], siblings[62], ..., siblings[0] which equal
        // emptyAt0, emptyAt1, ..., emptyAt63 respectively.
        for (uint256 i = 0; i < 64; ++i) {
            bytes32 sib = smt.emptyHashAtLevel(i);
            expected = keccak256(abi.encodePacked(expected, sib));
        }
        bytes32 root = smt.recomputeRoot(0, leaf, siblings);
        assertEq(root, expected);
    }

    /// @notice A populated leaf at index 1 with all-empty siblings:
    ///         bit_0 = 1, all higher bits = 0, so the bottom level
    ///         hashes as `H(sibling ‖ leaf)` and every upper level
    ///         hashes as `H(current ‖ sibling)`.
    function test_recomputeRoot_populated_leaf_index_1() public view {
        bytes32 leaf = keccak256("withdrawal-fixture-2");
        bytes32[] memory siblings = _emptyProofSiblings();

        // Bottom level (i = 0): bit_0 = 1, sibling is emptyAt0 = bytes32(0).
        bytes32 expected = keccak256(abi.encodePacked(emptyAt0, leaf));
        // Levels 1..63: bit_k = 0, sibling is emptyAt_k.
        for (uint256 i = 1; i < 64; ++i) {
            bytes32 sib = smt.emptyHashAtLevel(i);
            expected = keccak256(abi.encodePacked(expected, sib));
        }
        bytes32 root = smt.recomputeRoot(1, leaf, siblings);
        assertEq(root, expected);
    }

    function test_verifyProof_returns_true_on_match() public view {
        bytes32 leaf = keccak256("ok");
        bytes32[] memory siblings = _emptyProofSiblings();
        bytes32 root = smt.recomputeRoot(42, leaf, siblings);
        assertTrue(smt.verifyProof(42, leaf, siblings, root));
    }

    function test_verifyProof_returns_false_on_wrong_root() public view {
        bytes32 leaf = keccak256("ok");
        bytes32[] memory siblings = _emptyProofSiblings();
        bytes32 wrong = keccak256("wrong");
        assertFalse(smt.verifyProof(42, leaf, siblings, wrong));
    }

    function test_verifyProof_returns_false_on_wrong_index() public view {
        bytes32 leaf = keccak256("ok");
        bytes32[] memory siblings = _emptyProofSiblings();
        bytes32 root = smt.recomputeRoot(42, leaf, siblings);
        assertFalse(smt.verifyProof(43, leaf, siblings, root));
    }

    function test_verifyProof_returns_false_on_wrong_leaf() public view {
        bytes32 leaf = keccak256("ok");
        bytes32 wrongLeaf = keccak256("evil");
        bytes32[] memory siblings = _emptyProofSiblings();
        bytes32 root = smt.recomputeRoot(42, leaf, siblings);
        assertFalse(smt.verifyProof(42, wrongLeaf, siblings, root));
    }

    function test_verifyProof_returns_false_on_tampered_sibling() public view {
        bytes32 leaf = keccak256("ok");
        bytes32[] memory siblings = _emptyProofSiblings();
        bytes32 root = smt.recomputeRoot(42, leaf, siblings);

        // Tamper one byte of the leaf-adjacent sibling.
        siblings[63] = keccak256("tampered");
        assertFalse(smt.verifyProof(42, leaf, siblings, root));
    }

    /// @notice Two distinct leaves at the same index with the same
    ///         sibling path produce different roots.  This is the
    ///         critical property under collision-resistance: the
    ///         leaf bytes uniquely determine the root for a fixed
    ///         path.
    function test_recomputeRoot_distinct_leaves_distinct_roots() public view {
        bytes32 leafA = keccak256("alpha");
        bytes32 leafB = keccak256("beta");
        bytes32[] memory siblings = _emptyProofSiblings();
        bytes32 rootA = smt.recomputeRoot(7, leafA, siblings);
        bytes32 rootB = smt.recomputeRoot(7, leafB, siblings);
        assertTrue(rootA != rootB);
    }

    /// @notice Two distinct indices with the same leaf and the same
    ///         siblings produce different roots (the bit pattern
    ///         changes the per-level hash ordering).
    function test_recomputeRoot_distinct_indices_distinct_roots() public view {
        bytes32 leaf = keccak256("same-leaf");
        bytes32[] memory siblings = _emptyProofSiblings();
        // Index 0 and index 1 differ at bit_0; the bottom-level
        // hash changes from `H(leaf ‖ s)` to `H(s ‖ leaf)`.
        bytes32 root0 = smt.recomputeRoot(0, leaf, siblings);
        bytes32 root1 = smt.recomputeRoot(1, leaf, siblings);
        assertTrue(root0 != root1);
    }

    /// @notice Determinism: the same inputs always produce the same
    ///         root.
    function test_recomputeRoot_deterministic() public view {
        bytes32 leaf = keccak256("det");
        bytes32[] memory siblings = _populatedSiblings();
        bytes32 root1 = smt.recomputeRoot(0xCAFE, leaf, siblings);
        bytes32 root2 = smt.recomputeRoot(0xCAFE, leaf, siblings);
        assertEq(root1, root2);
    }

    // ---- Fuzz tests ----

    /// @notice Fuzz: tampering with any single bit of the proof
    ///         siblings or the leaf invalidates the proof under a
    ///         specific (non-trivial) leaf-path pair.  This
    ///         empirically validates the soundness property under
    ///         keccak256's collision resistance.
    function testFuzz_tampered_proof_rejected(uint8 tamperLevel, uint256 idx)
        public
        view
    {
        // Bound levels into [0, 64).
        tamperLevel = uint8(uint256(tamperLevel) % 64);
        bytes32 leaf = keccak256("fuzz");
        bytes32[] memory siblings = _populatedSiblings();
        bytes32 root = smt.recomputeRoot(idx, leaf, siblings);

        // Tamper exactly one sibling.
        siblings[tamperLevel] = keccak256(abi.encodePacked(siblings[tamperLevel], "tamper"));

        bool ok = smt.verifyProof(idx, leaf, siblings, root);
        assertFalse(ok);
    }

    // ---- Helpers ----

    /// @notice The canonical "all-empty subtree" siblings — the
    ///         proof shape for any index in an empty SMT.  Mirrors
    ///         Lean's `emptyProofSiblings`.
    function _emptyProofSiblings() internal view returns (bytes32[] memory) {
        bytes32[] memory siblings = new bytes32[](64);
        // siblings[0] = root-adjacent = defaultHash 63
        // siblings[63] = leaf-adjacent = defaultHash 0
        for (uint256 i = 0; i < 64; ++i) {
            siblings[i] = smt.emptyHashAtLevel(63 - i);
        }
        return siblings;
    }

    /// @notice A populated-but-arbitrary siblings array used by the
    ///         tampering-sensitivity fuzz.  Each sibling is a
    ///         deterministic hash so the fixture is reproducible
    ///         across runs.
    function _populatedSiblings() internal pure returns (bytes32[] memory) {
        bytes32[] memory siblings = new bytes32[](64);
        for (uint256 i = 0; i < 64; ++i) {
            siblings[i] = keccak256(abi.encodePacked("populated-sibling-", i));
        }
        return siblings;
    }
}
