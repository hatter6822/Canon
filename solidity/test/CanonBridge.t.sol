// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CanonBridge} from "src/contracts/CanonBridge.sol";
import {CanonDisputeVerifier} from "src/contracts/CanonDisputeVerifier.sol";
import {CanonSequencerStake} from "src/contracts/CanonSequencerStake.sol";
import {CanonIdentityRegistry} from "src/contracts/CanonIdentityRegistry.sol";
import {CanonEip712} from "src/lib/CanonEip712.sol";
import {SmtVerifier} from "src/lib/SmtVerifier.sol";
import {CBEDecode} from "src/lib/CBEDecode.sol";

import {Deployer} from "test/utils/Deployer.sol";
import {MockERC20} from "test/utils/MockERC20.sol";

/// @title CanonBridgeTest
/// @notice Comprehensive tests for `CanonBridge.sol` — covers all
///         five sub-WUs (E.1.1 deposit, E.1.2 state-root submission,
///         E.1.3 withdrawal, E.1.4 circuit breakers, E.1.5 rollback).
contract CanonBridgeTest is Test {
    CanonBridge private bridge;
    CanonDisputeVerifier private verifier;
    CanonSequencerStake private stake;
    CanonIdentityRegistry private registry;

    Deployer private deployer;
    MockERC20 private token;

    uint256 private constant ATTESTOR_PK = 0xA77E5701;
    address private attestor;
    address private sequencer = address(0xBEEF);
    address private alice = address(0xA1);
    address private bob = address(0xB0B);

    uint64 private constant DISPUTE_WINDOW = 100; // blocks
    uint64 private constant MAX_REDEMPTION_WINDOW = 50;
    uint64 private constant MAX_ATTESTATION_STALE = 200;
    uint64 private constant COOLDOWN_BLOCKS = 50;
    uint256 private constant TVL_CAP = 1000 ether;
    uint64 private constant ERC20_RESOURCE_ID = 1;

    /// @dev Local copies of the contract events for vm.expectEmit.
    event DepositInitiated(
        address indexed depositor,
        uint64 indexed resourceId,
        address token,
        uint256 amount,
        uint64 depositorNonce,
        bytes32 receiptHash
    );
    event StateRootSubmitted(
        bytes32 indexed root,
        uint64 indexed logIndexHigh,
        address indexed signer,
        uint64 submittedAtBlock
    );
    event StateRootReverted_(uint64 indexed disputedLogIndexHigh, bytes32 indexed revertedRoot);

    function setUp() public {
        attestor = vm.addr(ATTESTOR_PK);
        deployer = new Deployer();
        token = new MockERC20("Test Token", "TT");

        address[] memory adjudicators = new address[](2);
        adjudicators[0] = address(0xA001);
        adjudicators[1] = address(0xA002);

        uint64[] memory rids = new uint64[](1);
        rids[0] = ERC20_RESOURCE_ID;
        address[] memory toks = new address[](1);
        toks[0] = address(token);

        Deployer.Deployment memory d = deployer.deployAll(
            attestor, sequencer, adjudicators,
            uint8(2), DISPUTE_WINDOW, MAX_REDEMPTION_WINDOW,
            MAX_ATTESTATION_STALE, COOLDOWN_BLOCKS,
            TVL_CAP, uint256(5000),
            rids, toks
        );
        bridge = d.bridge;
        verifier = d.verifier;
        stake = d.stake;
        registry = d.registry;

        // Fund users so they can deposit.
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        token.mint(alice, 1000 ether);
    }

    // ------------------------------------------------------------------
    // Deployment / immutability sanity
    // ------------------------------------------------------------------

    function test_constructor_pins_immutables() public view {
        assertEq(bridge.attestor(), attestor);
        assertEq(bridge.disputeVerifier(), address(verifier));
        assertEq(bridge.sequencerStake(), address(stake));
        assertEq(bridge.disputeWindowBlocks(), DISPUTE_WINDOW);
        assertEq(bridge.tvlCap(), TVL_CAP);
        assertEq(bridge.deploymentId(),
            keccak256(abi.encode(block.chainid, address(bridge), keccak256("canon-test-v1")))
        );
    }

    function test_no_admin_surface() public {
        bytes4[] memory forbidden = new bytes4[](7);
        forbidden[0] = bytes4(keccak256("pause()"));
        forbidden[1] = bytes4(keccak256("unpause()"));
        forbidden[2] = bytes4(keccak256("transferOwnership(address)"));
        forbidden[3] = bytes4(keccak256("renounceOwnership()"));
        forbidden[4] = bytes4(keccak256("grantRole(bytes32,address)"));
        forbidden[5] = bytes4(keccak256("upgradeTo(address)"));
        forbidden[6] = bytes4(keccak256("proposeUpgrade(address)"));

        for (uint256 i = 0; i < forbidden.length; ++i) {
            (bool ok,) = address(bridge).call(abi.encodePacked(forbidden[i]));
            assertFalse(ok, "admin function unexpectedly callable");
        }
    }

    function test_constructor_reverts_on_dispute_window_smaller_than_redemption() public {
        Deployer d = new Deployer();
        address[] memory ad = new address[](1);
        ad[0] = address(0xA001);
        uint64[] memory rids = new uint64[](0);
        address[] memory toks = new address[](0);
        // dispute window (50) < redemption window (100) -> revert
        vm.expectRevert();
        d.deployAll(
            attestor, sequencer, ad, uint8(1),
            uint64(50), uint64(100), uint64(200), uint64(50),
            uint256(1 ether), uint256(5000),
            rids, toks
        );
    }

    // ------------------------------------------------------------------
    // E.1.1 Deposit entry points
    // ------------------------------------------------------------------

    function test_depositETH_happy_path() public {
        bytes32 expectedReceipt = keccak256(
            abi.encode(
                bridge.deploymentId(), alice, uint64(0), address(0), uint256(1 ether), uint64(0)
            )
        );
        vm.expectEmit(true, true, false, true);
        emit DepositInitiated(alice, uint64(0), address(0), 1 ether, 0, expectedReceipt);

        vm.prank(alice);
        bridge.depositETH{value: 1 ether}();

        assertEq(bridge.totalLockedValue(), 1 ether);
        assertEq(bridge.depositNonce(alice), 1);
        assertEq(address(bridge).balance, 1 ether);
    }

    function test_depositETH_increments_nonce() public {
        vm.startPrank(alice);
        bridge.depositETH{value: 1 ether}();
        bridge.depositETH{value: 1 ether}();
        bridge.depositETH{value: 1 ether}();
        assertEq(bridge.depositNonce(alice), 3);
        assertEq(bridge.totalLockedValue(), 3 ether);
        vm.stopPrank();
    }

    function test_depositETH_reverts_on_tvl_cap() public {
        // Deposit up to the cap.
        vm.deal(alice, TVL_CAP + 1);
        vm.startPrank(alice);
        bridge.depositETH{value: TVL_CAP}();
        vm.expectRevert(CanonBridge.TvlCapReached.selector);
        bridge.depositETH{value: 1}();
        vm.stopPrank();
    }

    function test_depositERC20_happy_path() public {
        vm.startPrank(alice);
        token.approve(address(bridge), 100 ether);
        bridge.depositERC20(ERC20_RESOURCE_ID, token, 100 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(address(bridge)), 100 ether);
        assertEq(bridge.totalLockedValue(), 100 ether);
        assertEq(bridge.depositNonce(alice), 1);
    }

    function test_depositERC20_reverts_on_unknown_resource_id() public {
        vm.startPrank(alice);
        token.approve(address(bridge), 100 ether);
        vm.expectRevert(CanonBridge.UnsupportedResource.selector);
        bridge.depositERC20(uint64(999), token, 100 ether);
        vm.stopPrank();
    }

    function test_depositERC20_reverts_on_token_mismatch() public {
        MockERC20 other = new MockERC20("Other", "OT");
        other.mint(alice, 10 ether);
        vm.startPrank(alice);
        other.approve(address(bridge), 10 ether);
        vm.expectRevert(CanonBridge.UnsupportedResource.selector);
        bridge.depositERC20(ERC20_RESOURCE_ID, other, 10 ether);
        vm.stopPrank();
    }

    function test_depositETH_via_native_resource_id_fails() public {
        // Calling depositERC20 with resource id 0 must fail (id 0 is
        // the reserved native-ETH slot, only addressable via depositETH).
        vm.startPrank(alice);
        token.approve(address(bridge), 1 ether);
        vm.expectRevert(CanonBridge.UnsupportedResource.selector);
        bridge.depositERC20(uint64(0), token, 1 ether);
        vm.stopPrank();
    }

    function test_bare_eth_transfer_reverts() public {
        vm.prank(alice);
        (bool ok,) = address(bridge).call{value: 1 ether}("");
        assertFalse(ok, "bare ETH should be rejected");
    }

    // ------------------------------------------------------------------
    // E.1.2 State-root submission
    // ------------------------------------------------------------------

    function test_submitStateRoot_happy_path() public {
        bytes32 root = keccak256("state-root-1");
        uint64 idx = 100;

        bytes memory sig = _signStateRoot(root, idx);

        vm.expectEmit(true, true, true, false);
        emit StateRootSubmitted(root, idx, attestor, uint64(block.number));
        bridge.submitStateRoot(root, idx, sig);

        assertEq(bridge.latestSubmittedLogIndexHigh(), idx);
        (bytes32 r, uint64 b, bool reverted) = bridge.stateRootAt(idx);
        assertEq(r, root);
        assertEq(b, uint64(block.number));
        assertFalse(reverted);
    }

    function test_submitStateRoot_reverts_on_wrong_signer() public {
        // Forge a signature using a non-attestor key.
        uint256 evilPk = 0xEE;
        address evilAddr = vm.addr(evilPk);
        assertTrue(evilAddr != attestor);

        bytes32 root = keccak256("evil-root");
        uint64 idx = 1;
        bytes32 digest = _stateRootDigest(root, idx);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(evilPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(CanonBridge.NotAttestor.selector);
        bridge.submitStateRoot(root, idx, sig);
    }

    function test_submitStateRoot_reverts_on_non_monotonic() public {
        bytes32 root1 = keccak256("r1");
        bytes32 root2 = keccak256("r2");
        bytes memory sig1 = _signStateRoot(root1, 100);
        bytes memory sig2 = _signStateRoot(root2, 50);

        bridge.submitStateRoot(root1, 100, sig1);
        vm.expectRevert(CanonBridge.NonMonotonic.selector);
        bridge.submitStateRoot(root2, 50, sig2);
    }

    function test_submitStateRoot_reverts_on_invalid_sig_length() public {
        bytes memory shortSig = hex"deadbeef";
        vm.expectRevert(CanonBridge.InvalidSignatureLength.selector);
        bridge.submitStateRoot(keccak256("x"), 1, shortSig);
    }

    function test_isStateRootFinalised_only_after_window() public {
        bytes32 root = keccak256("r");
        uint64 idx = 1;
        bridge.submitStateRoot(root, idx, _signStateRoot(root, idx));
        uint64 atBlock = uint64(block.number);

        assertFalse(bridge.isStateRootFinalised(idx));
        vm.roll(atBlock + DISPUTE_WINDOW - 1);
        assertFalse(bridge.isStateRootFinalised(idx));
        vm.roll(atBlock + DISPUTE_WINDOW);
        assertTrue(bridge.isStateRootFinalised(idx));
    }

    // ------------------------------------------------------------------
    // E.1.4 Automatic circuit breakers
    // ------------------------------------------------------------------

    function test_breaker_AttestationStale_blocks_deposit() public {
        // Submit a state root, then advance well past the staleness window.
        bridge.submitStateRoot(keccak256("r"), 1, _signStateRoot(keccak256("r"), 1));
        uint64 startBlock = uint64(block.number);
        vm.roll(startBlock + MAX_ATTESTATION_STALE + 1);

        vm.expectRevert(CanonBridge.AttestationStale.selector);
        vm.prank(alice);
        bridge.depositETH{value: 1 ether}();
    }

    function test_breaker_AttestationStale_does_not_fire_on_initial_state() public {
        // No state root submitted yet; the stale-breaker must be inert.
        vm.roll(uint64(block.number) + MAX_ATTESTATION_STALE * 10);
        vm.prank(alice);
        bridge.depositETH{value: 1 ether}();
        assertEq(bridge.totalLockedValue(), 1 ether);
    }

    function test_breaker_DisputeCooldown_blocks_deposit() public {
        // Trigger a rollback (sets `lastUpheldDisputeBlock`).
        vm.prank(address(verifier));
        bridge.revertToPriorRoot(0);

        uint64 markBlock = uint64(block.number);
        vm.roll(markBlock + COOLDOWN_BLOCKS - 1);

        vm.prank(alice);
        vm.expectRevert(CanonBridge.DisputeCooldown.selector);
        bridge.depositETH{value: 1 ether}();

        // After cooldown elapses, deposit succeeds.
        vm.roll(markBlock + COOLDOWN_BLOCKS);
        vm.prank(alice);
        bridge.depositETH{value: 1 ether}();
        assertEq(bridge.totalLockedValue(), 1 ether);
    }

    // ------------------------------------------------------------------
    // E.1.5 Rollback hook
    // ------------------------------------------------------------------

    function test_revertToPriorRoot_only_disputeVerifier() public {
        vm.expectRevert(CanonBridge.NotDisputeVerifier.selector);
        bridge.revertToPriorRoot(0);
    }

    function test_revertToPriorRoot_marks_records_reverted() public {
        bridge.submitStateRoot(keccak256("r1"), 1, _signStateRoot(keccak256("r1"), 1));
        bridge.submitStateRoot(keccak256("r2"), 2, _signStateRoot(keccak256("r2"), 2));
        bridge.submitStateRoot(keccak256("r3"), 3, _signStateRoot(keccak256("r3"), 3));

        vm.prank(address(verifier));
        bridge.revertToPriorRoot(2);

        (,, bool reverted1) = bridge.stateRootAt(1);
        (,, bool reverted2) = bridge.stateRootAt(2);
        (,, bool reverted3) = bridge.stateRootAt(3);
        assertFalse(reverted1, "root 1 (before threshold) must remain");
        assertTrue(reverted2, "root 2 (at threshold) reverted");
        assertTrue(reverted3, "root 3 (after threshold) reverted");
    }

    function test_revertToPriorRoot_idempotent() public {
        bridge.submitStateRoot(keccak256("r"), 1, _signStateRoot(keccak256("r"), 1));
        vm.startPrank(address(verifier));
        bridge.revertToPriorRoot(1);
        bridge.revertToPriorRoot(1);
        bridge.revertToPriorRoot(1);
        vm.stopPrank();

        (,, bool reverted) = bridge.stateRootAt(1);
        assertTrue(reverted);
    }

    function test_revertToPriorRoot_trips_cooldown() public {
        vm.prank(address(verifier));
        bridge.revertToPriorRoot(0);
        // Immediate next deposit reverts.
        vm.prank(alice);
        vm.expectRevert(CanonBridge.DisputeCooldown.selector);
        bridge.depositETH{value: 1 ether}();
    }

    // ------------------------------------------------------------------
    // hasOpenDisputeOlderThan
    // ------------------------------------------------------------------

    function test_hasOpenDisputeOlderThan_initial() public view {
        assertFalse(bridge.hasOpenDisputeOlderThan(0));
    }

    function test_hasOpenDisputeOlderThan_after_root_within_window() public {
        bridge.submitStateRoot(keccak256("r"), 1, _signStateRoot(keccak256("r"), 1));
        // Within dispute window
        assertTrue(bridge.hasOpenDisputeOlderThan(0));
    }

    function test_hasOpenDisputeOlderThan_after_window() public {
        bridge.submitStateRoot(keccak256("r"), 1, _signStateRoot(keccak256("r"), 1));
        vm.roll(block.number + DISPUTE_WINDOW);
        assertFalse(bridge.hasOpenDisputeOlderThan(0));
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _stateRootDigest(bytes32 root, uint64 idx) internal view returns (bytes32) {
        bytes32 ds = CanonEip712.domainSeparator(
            "CanonBridge", "1", block.chainid, uint256(0), address(bridge)
        );
        bytes32 sh = keccak256(
            abi.encode(
                keccak256("StateRoot(bytes32 root,uint64 logIndexHigh,bytes32 deploymentId)"),
                root,
                uint256(idx),
                bridge.deploymentId()
            )
        );
        return CanonEip712.digest(ds, sh);
    }

    function _signStateRoot(bytes32 root, uint64 idx) internal view returns (bytes memory) {
        bytes32 digest = _stateRootDigest(root, idx);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTOR_PK, digest);
        return abi.encodePacked(r, s, v);
    }
}
