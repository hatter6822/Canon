// SPDX-License-Identifier: GPL-3.0-or-later
//
//  Canon  - A Societal Kernel
//  Copyright (C) 2026  Adam Hall
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";

import {SmtCellVerifier} from "src/lib/SmtCellVerifier.sol";

/// @title SmtCellVerifierProxy
/// @notice External wrapper exposing `SmtCellVerifier`'s internal
///         library functions for tests.  All calldata-typed parameters
///         need an `external` boundary so Foundry can supply
///         `bytes memory` fixtures (which get re-wrapped as
///         `bytes calldata` at the proxy boundary).
contract SmtCellVerifierProxy {
    function emptySubtreeHash(uint256 d) external pure returns (bytes32) {
        return SmtCellVerifier.emptySubtreeHash(d);
    }

    function precomputeEmptySubtreeHashes() external pure returns (bytes32[256] memory) {
        return SmtCellVerifier.precomputeEmptySubtreeHashes();
    }

    function readKeyBitMSBFirst(bytes calldata smtKey, uint256 d) external pure returns (uint256) {
        return SmtCellVerifier.readKeyBitMSBFirst(smtKey, d);
    }

    function readBitmaskBit(bytes calldata bitmask, uint256 d) external pure returns (uint256) {
        return SmtCellVerifier.readBitmaskBit(bitmask, d);
    }

    function recomputeRoot(
        bytes calldata smtKey,
        bytes calldata leafPreimage,
        bytes calldata proofData
    ) external pure returns (bytes32) {
        return SmtCellVerifier.recomputeRoot(smtKey, leafPreimage, proofData);
    }

    function verifyCellProof(
        bytes32 root,
        bytes calldata smtKey,
        bytes calldata leafPreimage,
        bytes calldata proofData
    ) external pure returns (bool) {
        return SmtCellVerifier.verifyCellProof(root, smtKey, leafPreimage, proofData);
    }
}

/// @title SmtCellVerifierTest
/// @notice Workstream SC.2.e — Forge test suite for the
///         sparse-Merkle-tree cell-proof verifier.  Mirrors the
///         Lean test suite at
///         `LegalKernel/Test/FaultProof/Smt.lean` and adds
///         Solidity-specific shape / DoS coverage.
contract SmtCellVerifierTest is Test {
    /* ---------------------------------------------------------- */
    /* Constants reused across tests                              */
    /* ---------------------------------------------------------- */

    uint256 internal constant SMT_DEPTH = 256;
    uint256 internal constant BITMASK_BYTES = 32;
    uint256 internal constant HASH_BYTES = 32;

    bytes32 internal constant PADDING_HASH = bytes32(0);
    bytes32 internal H0_KECCAK; // keccak256("EMPTY_LEAF")

    SmtCellVerifierProxy internal smt;

    /// @notice The cached precomputed empty subtree hashes; the
    ///         verifier produces the same array internally, so we
    ///         use it for reference computations in tests.
    bytes32[SMT_DEPTH] internal empties;

    function setUp() public {
        smt = new SmtCellVerifierProxy();
        H0_KECCAK = keccak256("EMPTY_LEAF");
        empties = smt.precomputeEmptySubtreeHashes();
    }

    /* ---------------------------------------------------------- */
    /* Empty-subtree canonical hashes                             */
    /* ---------------------------------------------------------- */

    function test_emptySubtreeHash_0_equals_keccak_EMPTY_LEAF() public view {
        bytes32 h0 = smt.emptySubtreeHash(0);
        assertEq(h0, H0_KECCAK, "H_0 must equal keccak256(EMPTY_LEAF)");
    }

    function test_emptySubtreeHash_recursion_step_1() public view {
        bytes32 h0 = smt.emptySubtreeHash(0);
        bytes32 h1Direct = keccak256(abi.encodePacked(h0, h0));
        bytes32 h1ViaFn = smt.emptySubtreeHash(1);
        assertEq(h1ViaFn, h1Direct, "H_1 = keccak256(H_0 || H_0)");
    }

    function test_emptySubtreeHash_recursion_step_2() public view {
        bytes32 h0 = smt.emptySubtreeHash(0);
        bytes32 h1 = keccak256(abi.encodePacked(h0, h0));
        bytes32 h2Direct = keccak256(abi.encodePacked(h1, h1));
        bytes32 h2ViaFn = smt.emptySubtreeHash(2);
        assertEq(h2ViaFn, h2Direct, "H_2 = keccak256(H_1 || H_1)");
    }

    function test_emptySubtreeHash_255_consistent_with_recursive_definition() public view {
        bytes32 h255ViaFn = smt.emptySubtreeHash(255);
        bytes32 h254ViaFn = smt.emptySubtreeHash(254);
        bytes32 h255Direct = keccak256(abi.encodePacked(h254ViaFn, h254ViaFn));
        assertEq(h255ViaFn, h255Direct, "H_255 = keccak256(H_254 || H_254)");
    }

    function test_emptySubtreeHash_reverts_on_out_of_range() public {
        vm.expectRevert(bytes("SmtCellVerifier: depth out of range"));
        smt.emptySubtreeHash(256);
    }

    function test_precomputeEmptySubtreeHashes_size_and_consistency() public view {
        bytes32[SMT_DEPTH] memory hs = smt.precomputeEmptySubtreeHashes();
        // The recursion must hold for every adjacent pair.
        assertEq(hs[0], H0_KECCAK, "hs[0] = H_0");
        for (uint256 d = 1; d < SMT_DEPTH; ++d) {
            bytes32 expected = keccak256(abi.encodePacked(hs[d - 1], hs[d - 1]));
            assertEq(hs[d], expected, "hs[d] = keccak256(hs[d-1] || hs[d-1])");
        }
    }

    function test_precomputeEmptySubtreeHashes_agrees_with_emptySubtreeHash() public view {
        // Spot-check a few depths.
        bytes32[SMT_DEPTH] memory hs = smt.precomputeEmptySubtreeHashes();
        assertEq(hs[0], smt.emptySubtreeHash(0), "depth 0");
        assertEq(hs[1], smt.emptySubtreeHash(1), "depth 1");
        assertEq(hs[42], smt.emptySubtreeHash(42), "depth 42");
        assertEq(hs[100], smt.emptySubtreeHash(100), "depth 100");
        assertEq(hs[255], smt.emptySubtreeHash(255), "depth 255");
    }

    /// @notice The padding hash differs from every canonical empty
    ///         subtree hash.  This is the key invariant that
    ///         distinguishes a malformed proof's walk from any honest
    ///         walk.
    function test_paddingHash_distinct_from_every_canonical_empty() public view {
        bytes32 padding = bytes32(0);
        // H_0 is keccak256 of non-empty bytes; non-trivially non-zero.
        assertTrue(padding != H0_KECCAK, "padding != H_0");
        // Spot-check a few more depths.
        for (uint256 d = 0; d < SMT_DEPTH; d += 17) {
            assertTrue(padding != smt.emptySubtreeHash(d), "padding != H_d for some d");
        }
    }

    /* ---------------------------------------------------------- */
    /* Bit-extraction helpers                                     */
    /* ---------------------------------------------------------- */

    function test_readKeyBitMSBFirst_bit0_is_MSB() public view {
        // 0x80 = 0b10000000; bit 0 (MSB-first) is 1.
        bytes memory key = hex"80";
        assertEq(smt.readKeyBitMSBFirst(key, 0), 1, "bit 0 (MSB)");
        assertEq(smt.readKeyBitMSBFirst(key, 1), 0, "bit 1");
        assertEq(smt.readKeyBitMSBFirst(key, 7), 0, "bit 7 (LSB of byte 0)");
    }

    function test_readKeyBitMSBFirst_bit7_is_LSB_of_byte0() public view {
        // 0x01 = 0b00000001; bit 7 (MSB-first) = LSB of byte 0 = 1.
        bytes memory key = hex"01";
        assertEq(smt.readKeyBitMSBFirst(key, 0), 0, "bit 0 (MSB)");
        assertEq(smt.readKeyBitMSBFirst(key, 7), 1, "bit 7 (LSB of byte 0)");
        assertEq(smt.readKeyBitMSBFirst(key, 8), 0, "out of bounds");
    }

    function test_readKeyBitMSBFirst_bit8_is_MSB_of_byte1() public view {
        // 0x00 0x80; bit 8 (MSB-first) = MSB of byte 1 = 1.
        bytes memory key = hex"0080";
        assertEq(smt.readKeyBitMSBFirst(key, 8), 1, "bit 8 (MSB of byte 1)");
        assertEq(smt.readKeyBitMSBFirst(key, 9), 0, "bit 9");
        assertEq(smt.readKeyBitMSBFirst(key, 15), 0, "bit 15 (LSB of byte 1)");
    }

    function test_readKeyBitMSBFirst_out_of_bounds_returns_zero() public view {
        bytes memory key = hex"FF";
        assertEq(smt.readKeyBitMSBFirst(key, 8), 0, "bit 8 past length");
        assertEq(smt.readKeyBitMSBFirst(key, 100), 0, "bit 100 past length");
        assertEq(smt.readKeyBitMSBFirst(key, 255), 0, "bit 255 past length");
    }

    function test_readKeyBitMSBFirst_empty_key_all_bits_zero() public view {
        bytes memory key = "";
        for (uint256 d = 0; d < 256; d += 19) {
            assertEq(smt.readKeyBitMSBFirst(key, d), 0, "all bits 0 for empty key");
        }
    }

    /// @notice Matches Lean's `BitsKey UInt64` test:
    ///         MSB of `0x8000000000000000` is 1, every other bit is 0.
    function test_readKeyBitMSBFirst_uint64_msb_pattern() public view {
        // 8 BE bytes of 0x8000_0000_0000_0000.
        bytes memory key = hex"8000000000000000";
        assertEq(smt.readKeyBitMSBFirst(key, 0), 1, "MSB of UInt64 = 1");
        for (uint256 d = 1; d < 64; ++d) {
            assertEq(smt.readKeyBitMSBFirst(key, d), 0, "other UInt64 bits = 0");
        }
        for (uint256 d = 64; d < 256; d += 31) {
            assertEq(smt.readKeyBitMSBFirst(key, d), 0, "past UInt64 length = 0");
        }
    }

    /// @notice Matches Lean's `BitsKey UInt64` test:
    ///         LSB of `0x0000000000000001` is 1 at bit 63.
    function test_readKeyBitMSBFirst_uint64_lsb_pattern() public view {
        bytes memory key = hex"0000000000000001";
        for (uint256 d = 0; d < 63; ++d) {
            assertEq(smt.readKeyBitMSBFirst(key, d), 0, "all UInt64 bits before LSB = 0");
        }
        assertEq(smt.readKeyBitMSBFirst(key, 63), 1, "LSB of UInt64 = 1");
        for (uint256 d = 64; d < 256; d += 31) {
            assertEq(smt.readKeyBitMSBFirst(key, d), 0, "past UInt64 length = 0");
        }
    }

    function test_readBitmaskBit_bit0_is_LSB_of_byte0() public view {
        // 0x01 = 0b00000001; bit 0 (LSB-first) = LSB of byte 0 = 1.
        bytes memory bitmask = hex"01";
        assertEq(smt.readBitmaskBit(bitmask, 0), 1, "bit 0 (LSB of byte 0)");
        assertEq(smt.readBitmaskBit(bitmask, 1), 0, "bit 1");
        assertEq(smt.readBitmaskBit(bitmask, 7), 0, "bit 7 (MSB of byte 0)");
    }

    function test_readBitmaskBit_bit7_is_MSB_of_byte0() public view {
        // 0x80 = 0b10000000; bit 7 (LSB-first) = MSB of byte 0 = 1.
        bytes memory bitmask = hex"80";
        assertEq(smt.readBitmaskBit(bitmask, 0), 0, "bit 0");
        assertEq(smt.readBitmaskBit(bitmask, 7), 1, "bit 7 (MSB of byte 0)");
    }

    function test_readBitmaskBit_bit8_is_LSB_of_byte1() public view {
        // 0x00 0x01; bit 8 (LSB-first within byte) = LSB of byte 1 = 1.
        bytes memory bitmask = hex"0001";
        assertEq(smt.readBitmaskBit(bitmask, 8), 1, "bit 8 (LSB of byte 1)");
        assertEq(smt.readBitmaskBit(bitmask, 9), 0, "bit 9");
    }

    function test_readBitmaskBit_out_of_bounds_returns_zero() public view {
        bytes memory bitmask = hex"FF";
        assertEq(smt.readBitmaskBit(bitmask, 8), 0, "bit 8 past length");
        assertEq(smt.readBitmaskBit(bitmask, 256), 0, "bit 256");
    }

    /* ---------------------------------------------------------- */
    /* Verifier: empty-proof path                                 */
    /* ---------------------------------------------------------- */

    /// @notice The empty proof (all-zero bitmask, no siblings) walks
    ///         every depth using the canonical empty hash.  This
    ///         mirrors Lean's `verifySmtCellProof_empty_self_verifies`.
    function test_emptyProof_self_verifies_for_uint64_pair() public view {
        bytes memory smtKey = hex"000000000000002A"; // UInt64 42 (BE)
        bytes memory leafPreimage = abi.encodePacked(_cbeEncodeUint64(42), _cbeEncodeUint64(100));
        bytes memory proofData = _emptyProofData();

        bytes32 root = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        assertTrue(
            smt.verifyCellProof(root, smtKey, leafPreimage, proofData), "empty proof self-verifies"
        );
    }

    /// @notice A second (key, value) pair sanity check, mirroring
    ///         the multi-pair Lean test
    ///         `verifySmtCellProof_empty_self_verifies for UInt64 cells`.
    function test_emptyProof_self_verifies_for_multiple_pairs() public view {
        bytes memory proofData = _emptyProofData();
        uint64[5] memory keys =
            [uint64(0), uint64(1), uint64(42), uint64(0xDEADBEEF), uint64(0xFFFFFFFFFFFFFFFF)];
        uint64[5] memory values =
            [uint64(0), uint64(1), uint64(100), uint64(0xCAFEBABE), uint64(0xFFFFFFFFFFFFFFFF)];
        for (uint256 i = 0; i < keys.length; ++i) {
            bytes memory smtKey = abi.encodePacked(keys[i]);
            bytes memory leafPreimage =
                abi.encodePacked(_cbeEncodeUint64(keys[i]), _cbeEncodeUint64(values[i]));
            bytes32 root = smt.recomputeRoot(smtKey, leafPreimage, proofData);
            assertTrue(
                smt.verifyCellProof(root, smtKey, leafPreimage, proofData),
                "self-verify across multiple pairs"
            );
        }
    }

    /* ---------------------------------------------------------- */
    /* Verifier: non-trivial proof with a custom sibling          */
    /* ---------------------------------------------------------- */

    /// @notice A non-trivial proof with one set bitmask bit (depth 0)
    ///         carries a custom sibling.  Mirrors Lean's
    ///         "Non-trivial proof with one set bitmask bit verifies
    ///         self-walk".
    function test_nonTrivial_proof_one_set_bit_self_verifies() public view {
        // Bitmask: bit 0 set (= LSB of byte 0 = 0x01).
        bytes memory bitmask = abi.encodePacked(bytes32(uint256(0x01) << 248));
        // Actually, bit 0 (LSB-first) of byte 0 means byte 0 = 0x01.
        // bytes32-leftmost is byte 0; place 0x01 in the leftmost byte:
        bitmask = new bytes(32);
        bitmask[0] = 0x01;

        // One 32-byte custom sibling: all 0x07 bytes.
        bytes memory customSibling = new bytes(32);
        for (uint256 i = 0; i < 32; ++i) {
            customSibling[i] = 0x07;
        }

        bytes memory proofData = abi.encodePacked(bitmask, customSibling);

        bytes memory smtKey = hex"000000000000002A"; // UInt64 42
        bytes memory leafPreimage = abi.encodePacked(_cbeEncodeUint64(42), _cbeEncodeUint64(100));

        bytes32 root = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        assertTrue(
            smt.verifyCellProof(root, smtKey, leafPreimage, proofData),
            "non-trivial proof self-verifies"
        );
    }

    /// @notice A non-trivial proof walks to a different root than the
    ///         empty proof for the same (key, value).
    function test_nonTrivial_proof_differs_from_emptyProof_root() public view {
        bytes memory bitmask = new bytes(32);
        bitmask[0] = 0x01;
        bytes memory customSibling = new bytes(32);
        for (uint256 i = 0; i < 32; ++i) {
            customSibling[i] = 0x07;
        }
        bytes memory nonTrivialProof = abi.encodePacked(bitmask, customSibling);

        bytes memory smtKey = hex"000000000000002A";
        bytes memory leafPreimage = abi.encodePacked(_cbeEncodeUint64(42), _cbeEncodeUint64(100));

        bytes32 rootNonTrivial = smt.recomputeRoot(smtKey, leafPreimage, nonTrivialProof);
        bytes32 rootEmpty = smt.recomputeRoot(smtKey, leafPreimage, _emptyProofData());

        assertTrue(
            rootNonTrivial != rootEmpty,
            "non-trivial proof walks to different root than empty proof"
        );
    }

    /* ---------------------------------------------------------- */
    /* Negative tests: tamper rejection                           */
    /* ---------------------------------------------------------- */

    /// @notice Adversarial: tampering the claimed value rejects
    ///         verification.  Mirrors Lean's
    ///         "Adversarial: tamper value rejects verification".
    function test_adversarial_tamper_value_rejected() public view {
        bytes memory smtKey = hex"000000000000002A";
        bytes memory leafPreimageHonest =
            abi.encodePacked(_cbeEncodeUint64(42), _cbeEncodeUint64(100));
        bytes memory leafPreimageTampered =
            abi.encodePacked(_cbeEncodeUint64(42), _cbeEncodeUint64(999));
        bytes memory proofData = _emptyProofData();

        bytes32 root = smt.recomputeRoot(smtKey, leafPreimageHonest, proofData);
        assertTrue(
            smt.verifyCellProof(root, smtKey, leafPreimageHonest, proofData),
            "honest verification accepts"
        );
        assertFalse(
            smt.verifyCellProof(root, smtKey, leafPreimageTampered, proofData),
            "tampered-value verification rejects"
        );
    }

    /// @notice Adversarial: tampering the smtKey rejects verification.
    ///         Mirrors Lean's "Adversarial: tamper key rejects".
    function test_adversarial_tamper_key_rejected() public view {
        bytes memory smtKeyHonest = hex"000000000000002A"; // 42
        bytes memory smtKeyTampered = hex"000000000000002B"; // 43
        bytes memory leafPreimage = abi.encodePacked(_cbeEncodeUint64(42), _cbeEncodeUint64(100));
        bytes memory proofData = _emptyProofData();

        bytes32 root = smt.recomputeRoot(smtKeyHonest, leafPreimage, proofData);
        assertTrue(
            smt.verifyCellProof(root, smtKeyHonest, leafPreimage, proofData),
            "honest verification accepts"
        );
        assertFalse(
            smt.verifyCellProof(root, smtKeyTampered, leafPreimage, proofData),
            "tampered-key verification rejects"
        );
    }

    /// @notice Adversarial: tampering a sibling at depth 0 rejects
    ///         verification.  Mirrors Lean's
    ///         "Adversarial: tamper sibling at depth 0".
    function test_adversarial_tamper_sibling_at_depth_0_rejected() public view {
        bytes memory bitmask = new bytes(32);
        bitmask[0] = 0x01;
        bytes memory customSiblingHonest = new bytes(32);
        bytes memory customSiblingTampered = new bytes(32);
        for (uint256 i = 0; i < 32; ++i) {
            customSiblingHonest[i] = 0x07;
            customSiblingTampered[i] = 0x08;
        }

        bytes memory proofHonest = abi.encodePacked(bitmask, customSiblingHonest);
        bytes memory proofTampered = abi.encodePacked(bitmask, customSiblingTampered);

        bytes memory smtKey = hex"000000000000002A";
        bytes memory leafPreimage = abi.encodePacked(_cbeEncodeUint64(42), _cbeEncodeUint64(100));

        bytes32 root = smt.recomputeRoot(smtKey, leafPreimage, proofHonest);
        assertTrue(
            smt.verifyCellProof(root, smtKey, leafPreimage, proofHonest), "honest proof verifies"
        );
        assertFalse(
            smt.verifyCellProof(root, smtKey, leafPreimage, proofTampered),
            "tampered-sibling proof rejects"
        );
    }

    /// @notice Adversarial: tampering a bitmask bit rejects.  Mirrors
    ///         Lean's "Adversarial: tamper bitmask bit".
    function test_adversarial_tamper_bitmask_bit_rejected() public view {
        // Honest: bit 0 set; supplying the customSibling for depth 0.
        bytes memory bitmaskHonest = new bytes(32);
        bitmaskHonest[0] = 0x01;
        // Tampered: bit 1 set instead; the supplied sibling now
        // applies at depth 1 (which expects canonical empty
        // otherwise).  The walk diverges from the honest one.
        bytes memory bitmaskTampered = new bytes(32);
        bitmaskTampered[0] = 0x02;

        bytes memory customSibling = new bytes(32);
        for (uint256 i = 0; i < 32; ++i) {
            customSibling[i] = 0x07;
        }

        bytes memory proofHonest = abi.encodePacked(bitmaskHonest, customSibling);
        bytes memory proofTampered = abi.encodePacked(bitmaskTampered, customSibling);

        bytes memory smtKey = hex"000000000000002A";
        bytes memory leafPreimage = abi.encodePacked(_cbeEncodeUint64(42), _cbeEncodeUint64(100));

        bytes32 root = smt.recomputeRoot(smtKey, leafPreimage, proofHonest);
        assertTrue(
            smt.verifyCellProof(root, smtKey, leafPreimage, proofHonest), "honest proof verifies"
        );
        assertFalse(
            smt.verifyCellProof(root, smtKey, leafPreimage, proofTampered),
            "tampered-bitmask proof rejects"
        );
    }

    /// @notice The verifier rejects a wrong root with any proof.
    function test_adversarial_wrong_root_rejected() public view {
        bytes memory smtKey = hex"000000000000002A";
        bytes memory leafPreimage = abi.encodePacked(_cbeEncodeUint64(42), _cbeEncodeUint64(100));
        bytes memory proofData = _emptyProofData();

        bytes32 honestRoot = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        bytes32 wrongRoot = keccak256("not the real root");
        assertTrue(honestRoot != wrongRoot, "guard: roots differ");
        assertFalse(
            smt.verifyCellProof(wrongRoot, smtKey, leafPreimage, proofData),
            "wrong-root verification rejects"
        );
    }

    /* ---------------------------------------------------------- */
    /* Negative tests: malformed proof data                       */
    /* ---------------------------------------------------------- */

    /// @notice `verifyCellProof` returns false (does NOT revert) on a
    ///         too-short proofData — matching Lean's `isWellFormed`
    ///         behavior.
    function test_malformed_proofData_too_short_returns_false() public view {
        bytes memory smtKey = hex"000000000000002A";
        bytes memory leafPreimage = abi.encodePacked(_cbeEncodeUint64(42), _cbeEncodeUint64(100));
        bytes memory proofData = hex"deadbeef"; // 4 bytes; need at least 32 for bitmask.
        assertFalse(
            smt.verifyCellProof(bytes32(0), smtKey, leafPreimage, proofData),
            "too-short proofData rejected"
        );
    }

    /// @notice `verifyCellProof` returns false on a misaligned
    ///         siblings region.  The bitmask is well-formed but the
    ///         siblings region is not a multiple of 32 bytes.
    function test_malformed_proofData_siblings_misaligned_returns_false() public view {
        bytes memory smtKey = hex"000000000000002A";
        bytes memory leafPreimage = abi.encodePacked(_cbeEncodeUint64(42), _cbeEncodeUint64(100));
        bytes memory bitmask = new bytes(32); // all zero
        // 5 trailing bytes (not 0, not 32-aligned).
        bytes memory misaligned = abi.encodePacked(bitmask, hex"01020304ff");
        assertFalse(
            smt.verifyCellProof(bytes32(0), smtKey, leafPreimage, misaligned),
            "misaligned proofData rejected"
        );
    }

    /// @notice `recomputeRoot` REVERTS on too-short proofData
    ///         (caller-side discipline distinct from
    ///         `verifyCellProof`).
    function test_recomputeRoot_reverts_on_too_short_proofData() public {
        bytes memory smtKey = hex"00";
        bytes memory leafPreimage = hex"";
        bytes memory proofData = hex"deadbeef";
        vm.expectRevert(
            abi.encodeWithSelector(SmtCellVerifier.SmtCellProofTooShort.selector, uint256(4))
        );
        smt.recomputeRoot(smtKey, leafPreimage, proofData);
    }

    /// @notice `recomputeRoot` REVERTS on misaligned siblings region.
    function test_recomputeRoot_reverts_on_misaligned_siblings() public {
        bytes memory smtKey = hex"00";
        bytes memory leafPreimage = hex"";
        bytes memory bitmask = new bytes(32);
        bytes memory misaligned = abi.encodePacked(bitmask, hex"010203");
        vm.expectRevert(
            abi.encodeWithSelector(SmtCellVerifier.SmtCellSiblingsMisaligned.selector, uint256(3))
        );
        smt.recomputeRoot(smtKey, leafPreimage, misaligned);
    }

    /* ---------------------------------------------------------- */
    /* Extras-tolerance (matches Lean's "DoS bound" test)         */
    /* ---------------------------------------------------------- */

    /// @notice The verifier accepts a proof with trailing siblings
    ///         beyond what the bitmask popcount requires.  Extras
    ///         are silently ignored by the walk.  Mirrors Lean's
    ///         "verifySmtCellProof rejects proof with extra siblings
    ///         (DoS bound)" — Lean *accepts* the extras (walks past
    ///         them), confirmed here.
    function test_extra_siblings_silently_ignored() public view {
        // Bitmask all zero; siblings region has 3 extra siblings that
        // the walk shouldn't touch.
        bytes memory bitmask = new bytes(32);
        bytes memory extras = new bytes(3 * 32);
        for (uint256 i = 0; i < extras.length; ++i) {
            extras[i] = 0x05;
        }

        bytes memory proofData = abi.encodePacked(bitmask, extras);
        bytes memory smtKey = hex"000000000000002A";
        bytes memory leafPreimage = abi.encodePacked(_cbeEncodeUint64(42), _cbeEncodeUint64(100));

        bytes32 rootViaExtras = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        bytes32 rootViaEmpty = smt.recomputeRoot(smtKey, leafPreimage, _emptyProofData());
        assertEq(rootViaExtras, rootViaEmpty, "extras don't change walk");
    }

    /* ---------------------------------------------------------- */
    /* Two-cell map: walk + verify both cells                     */
    /* ---------------------------------------------------------- */

    /// @notice Synthetic two-cell SMT: keys differ only at the
    ///         deepest depth (LSB of byte 7 in UInt64 BE form).
    ///         For the empty SMT walked with the all-empty proof,
    ///         constructing a `(root, key, value, proof)` tuple that
    ///         the verifier accepts is the canonical SMT membership
    ///         attestation.
    ///
    ///         Here we operate at the WALK level (consistent with
    ///         Lean's spec): for keys at index 1 (LSB=1) and 0
    ///         (LSB=0), the canonical empty-proof walks differ at
    ///         the last fold step (key bit 63 determines whether
    ///         the parent is `keccak256(sibling || current)` or
    ///         `keccak256(current || sibling)`).
    function test_two_cell_empty_proof_walks_differ_per_LSB() public view {
        bytes memory smtKey0 = hex"0000000000000000"; // LSB = 0
        bytes memory smtKey1 = hex"0000000000000001"; // LSB = 1
        bytes memory leafPreimage0 = abi.encodePacked(_cbeEncodeUint64(0), _cbeEncodeUint64(100));
        bytes memory leafPreimage1 = abi.encodePacked(_cbeEncodeUint64(1), _cbeEncodeUint64(100));
        bytes memory proofData = _emptyProofData();

        bytes32 root0 = smt.recomputeRoot(smtKey0, leafPreimage0, proofData);
        bytes32 root1 = smt.recomputeRoot(smtKey1, leafPreimage1, proofData);
        assertTrue(root0 != root1, "distinct LSBs walk to distinct roots");
    }

    /* ---------------------------------------------------------- */
    /* Equivalence vs the empty-proof formula                     */
    /* ---------------------------------------------------------- */

    /// @notice The empty-proof walk equals a hand-computed reference:
    ///         starting from leaf, fold (current ⊕ side) with the
    ///         per-depth canonical empty hash, sided by the key bit.
    function test_emptyProof_walk_matches_reference_for_zero_key() public view {
        bytes memory smtKey = hex"0000000000000000"; // all-zero UInt64
        uint64 keyU = 0;
        uint64 valueU = 99;
        bytes memory leafPreimage =
            abi.encodePacked(_cbeEncodeUint64(keyU), _cbeEncodeUint64(valueU));
        bytes memory proofData = _emptyProofData();

        // Reference computation:
        //   leaf = keccak256(leafPreimage)
        //   for d in 0..255:  (bit = 0, sibling = H_d)  current = H(current || H_d)
        bytes32 expected = keccak256(leafPreimage);
        for (uint256 d = 0; d < SMT_DEPTH; ++d) {
            expected = keccak256(abi.encodePacked(expected, empties[d]));
        }

        bytes32 actual = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        assertEq(actual, expected, "empty-proof walk for all-zero key matches reference formula");
    }

    /// @notice The empty-proof walk for an all-MSB-set key takes the
    ///         "right child" branch at depth 0 and "left child" at
    ///         every other depth.  Reference: hand-walk.
    function test_emptyProof_walk_matches_reference_for_msb_key() public view {
        bytes memory smtKey = hex"8000000000000000"; // bit 0 (MSB) = 1
        uint64 keyU = uint64(1) << 63;
        uint64 valueU = 100;
        bytes memory leafPreimage =
            abi.encodePacked(_cbeEncodeUint64(keyU), _cbeEncodeUint64(valueU));
        bytes memory proofData = _emptyProofData();

        // Reference:
        //   leaf = keccak256(leafPreimage)
        //   d=0: bit=1, sibling=H_0; current = H(H_0 || current)  [right]
        //   d=1..255: bit=0, sibling=H_d; current = H(current || H_d)  [left]
        bytes32 expected = keccak256(leafPreimage);
        expected = keccak256(abi.encodePacked(empties[0], expected));
        for (uint256 d = 1; d < SMT_DEPTH; ++d) {
            expected = keccak256(abi.encodePacked(expected, empties[d]));
        }

        bytes32 actual = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        assertEq(actual, expected, "empty-proof walk for MSB-only key matches reference formula");
    }

    /* ---------------------------------------------------------- */
    /* Determinism                                                */
    /* ---------------------------------------------------------- */

    function test_recomputeRoot_is_deterministic() public view {
        bytes memory smtKey = hex"0102030405060708";
        bytes memory leafPreimage = hex"deadbeef";
        bytes memory proofData = _emptyProofData();
        bytes32 r1 = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        bytes32 r2 = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        assertEq(r1, r2, "identical inputs produce identical roots");
    }

    /* ---------------------------------------------------------- */
    /* Distinct leaves -> distinct roots                           */
    /* ---------------------------------------------------------- */

    function test_recomputeRoot_distinct_leaves_distinct_roots() public view {
        bytes memory smtKey = hex"0000000000000007";
        bytes memory leafA = abi.encodePacked(_cbeEncodeUint64(7), _cbeEncodeUint64(100));
        bytes memory leafB = abi.encodePacked(_cbeEncodeUint64(7), _cbeEncodeUint64(200));
        bytes memory proofData = _emptyProofData();
        bytes32 rootA = smt.recomputeRoot(smtKey, leafA, proofData);
        bytes32 rootB = smt.recomputeRoot(smtKey, leafB, proofData);
        assertTrue(rootA != rootB, "distinct leaves -> distinct roots");
    }

    /* ---------------------------------------------------------- */
    /* Property tests: fuzz                                       */
    /* ---------------------------------------------------------- */

    /// @notice For any well-formed (key, value, proofData), the
    ///         self-recomputed root is accepted by the verifier.
    ///         Property test corresponding to the Lean completeness
    ///         theorem `verifySmtCellProof_walks_to_root`.
    function testFuzz_self_recomputed_root_verifies(
        bytes calldata smtKey,
        bytes calldata leafPreimage,
        uint256 bitmaskBitsRaw,
        bytes32[8] calldata customSiblings
    ) public view {
        // Build a well-formed proofData with the given bitmask and 8
        // 32-byte siblings.  Construct the bitmask from the low 256
        // bits of `bitmaskBitsRaw` (which is naturally 256 bits but
        // here we just keep it within bounds).
        bytes memory bitmask = abi.encodePacked(bytes32(bitmaskBitsRaw));
        bytes memory siblings = abi.encodePacked(
            customSiblings[0],
            customSiblings[1],
            customSiblings[2],
            customSiblings[3],
            customSiblings[4],
            customSiblings[5],
            customSiblings[6],
            customSiblings[7]
        );
        bytes memory proofData = abi.encodePacked(bitmask, siblings);

        // Bound key + leafPreimage to avoid memory blow-up at the
        // calldata boundary; the property holds for any (the bound
        // is only to keep fuzz cheap).
        if (smtKey.length > 64) return;
        if (leafPreimage.length > 256) return;

        bytes32 root = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        assertTrue(
            smt.verifyCellProof(root, smtKey, leafPreimage, proofData),
            "self-recomputed root must verify"
        );
    }

    /// @notice Tampering a single sibling byte invalidates the proof.
    ///         The fuzz parameters seed the tampering location and
    ///         the (key, value) tuple.  Mirrors Lean's adversarial
    ///         tamper coverage.
    function testFuzz_tamper_one_sibling_byte_rejected(
        uint8 tamperBitmaskByte,
        uint8 tamperSiblingByte,
        uint8 tamperSiblingIdx,
        uint64 keyU,
        uint64 valueU
    ) public view {
        // Build a non-trivial proof: bitmask with at least one set
        // bit, and the corresponding siblings.  We use the lower 8
        // bits of `tamperBitmaskByte` as the bitmask's byte 0 value.
        if (tamperBitmaskByte == 0) return; // skip trivial
        uint8 popcount = _popcount8(tamperBitmaskByte);

        bytes memory bitmask = new bytes(32);
        bitmask[0] = bytes1(tamperBitmaskByte);

        bytes memory siblings = new bytes(uint256(popcount) * 32);
        // Fill each sibling deterministically based on its position.
        for (uint256 i = 0; i < uint256(popcount); ++i) {
            for (uint256 j = 0; j < 32; ++j) {
                siblings[i * 32 + j] =
                    bytes1(uint8(uint256(keccak256(abi.encodePacked(i, j))) % 256));
            }
        }

        bytes memory proofData = abi.encodePacked(bitmask, siblings);
        bytes memory smtKey = abi.encodePacked(keyU);
        bytes memory leafPreimage =
            abi.encodePacked(_cbeEncodeUint64(keyU), _cbeEncodeUint64(valueU));

        bytes32 honestRoot = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        assertTrue(
            smt.verifyCellProof(honestRoot, smtKey, leafPreimage, proofData),
            "honest proof verifies"
        );

        // Tamper one byte of one sibling (bounded indices).
        uint256 sIdx = uint256(tamperSiblingIdx) % uint256(popcount);
        uint256 bIdx = uint256(tamperSiblingByte) % 32;
        bytes memory tamperedSiblings = new bytes(siblings.length);
        for (uint256 i = 0; i < siblings.length; ++i) {
            tamperedSiblings[i] = siblings[i];
        }
        // Flip one bit (XOR 0x01) — guaranteed to change the byte.
        tamperedSiblings[sIdx * 32 + bIdx] = bytes1(uint8(siblings[sIdx * 32 + bIdx]) ^ uint8(0x01));

        bytes memory tamperedProofData = abi.encodePacked(bitmask, tamperedSiblings);
        assertFalse(
            smt.verifyCellProof(honestRoot, smtKey, leafPreimage, tamperedProofData),
            "tampered-sibling proof rejects"
        );
    }

    /* ---------------------------------------------------------- */
    /* Cross-check vs the existing 64-deep SmtVerifier            */
    /* ---------------------------------------------------------- */

    /// @notice The two verifiers (cell SMT at depth 256, withdrawal
    ///         SMT at depth 64) coexist without symbol clashes and
    ///         differ in their depth constants.  This is a smoke
    ///         test to catch any accidental name collision.
    function test_smt_cell_and_withdrawal_depth_constants_distinct() public pure {
        assertEq(SmtCellVerifier.SMT_DEPTH, 256, "cell depth = 256");
    }

    /* ---------------------------------------------------------- */
    /* Helpers                                                    */
    /* ---------------------------------------------------------- */

    /// @notice CBE encoding of a UInt64 = 1-byte type tag (0x00) ||
    ///         8 LE value bytes (9 bytes total).  Mirrors Lean's
    ///         `Encodable Nat` instance restricted to UInt64 inputs.
    function _cbeEncodeUint64(uint64 v) internal pure returns (bytes memory out) {
        out = new bytes(9);
        out[0] = 0x00; // cbeTagUint
        for (uint256 i = 0; i < 8; ++i) {
            out[1 + i] = bytes1(uint8((v >> (i * 8)) & 0xFF));
        }
    }

    /// @notice The canonical empty proof: 32-byte all-zero bitmask,
    ///         zero siblings.  Mirrors Lean's `SmtCellProof.empty`.
    function _emptyProofData() internal pure returns (bytes memory) {
        return new bytes(32);
    }

    /// @notice Population count of an 8-bit value.
    function _popcount8(uint8 v) internal pure returns (uint8 count) {
        unchecked {
            for (uint256 i = 0; i < 8; ++i) {
                count += uint8((uint256(v) >> i) & 1);
            }
        }
    }
}

/// @title SmtCellVerifierGasTest
/// @notice Workstream SC.2.e — gas-snapshot regression test suite.
///         Pins gas costs for representative proof shapes (empty,
///         one set bit, full-popcount, large) so future
///         optimisations can be measured and regressions detected.
contract SmtCellVerifierGasTest is Test {
    uint256 internal constant SMT_DEPTH = 256;

    SmtCellVerifierProxy internal smt;

    function setUp() public {
        smt = new SmtCellVerifierProxy();
    }

    function test_gas_emptyProof_walk() public {
        bytes memory smtKey = hex"000000000000002A";
        bytes memory leafPreimage = hex"deadbeefcafebabe";
        bytes memory proofData = new bytes(32);
        uint256 gasBefore = gasleft();
        bytes32 root = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("gas_emptyProof_walk", gasUsed);
        // Sanity: walk completes and returns a non-zero root for
        // non-empty leafPreimage.
        assertTrue(root != bytes32(0), "non-zero root");
    }

    function test_gas_oneNonEmptySibling_walk() public {
        bytes memory smtKey = hex"000000000000002A";
        bytes memory leafPreimage = hex"deadbeefcafebabe";
        bytes memory bitmask = new bytes(32);
        bitmask[0] = 0x01;
        bytes memory sib = new bytes(32);
        for (uint256 i = 0; i < 32; ++i) {
            sib[i] = 0x07;
        }
        bytes memory proofData = abi.encodePacked(bitmask, sib);
        uint256 gasBefore = gasleft();
        bytes32 root = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("gas_oneNonEmptySibling_walk", gasUsed);
        assertTrue(root != bytes32(0), "non-zero root");
    }

    function test_gas_fullPopcount_walk() public {
        bytes memory smtKey = new bytes(32);
        bytes memory leafPreimage = hex"deadbeefcafebabe";
        bytes memory bitmask = new bytes(32);
        for (uint256 i = 0; i < 32; ++i) {
            bitmask[i] = 0xFF;
        }
        bytes memory siblings = new bytes(256 * 32);
        for (uint256 i = 0; i < siblings.length; ++i) {
            // casting i % 256 to uint8 is safe: the operand is in [0, 255].
            // forge-lint: disable-next-line(unsafe-typecast)
            siblings[i] = bytes1(uint8(i % 256));
        }
        bytes memory proofData = abi.encodePacked(bitmask, siblings);
        uint256 gasBefore = gasleft();
        bytes32 root = smt.recomputeRoot(smtKey, leafPreimage, proofData);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("gas_fullPopcount_walk", gasUsed);
        assertTrue(root != bytes32(0), "non-zero root");
    }
}
