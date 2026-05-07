// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CanonBridge} from "src/contracts/CanonBridge.sol";
import {CanonDisputeVerifier} from "src/contracts/CanonDisputeVerifier.sol";
import {CanonSequencerStake} from "src/contracts/CanonSequencerStake.sol";
import {CanonIdentityRegistry} from "src/contracts/CanonIdentityRegistry.sol";
import {CanonMigration} from "src/contracts/CanonMigration.sol";
import {CanonEip712} from "src/lib/CanonEip712.sol";
import {CREATE3} from "src/lib/CREATE3.sol";

import {Deployer} from "test/utils/Deployer.sol";

contract CanonMigrationTest is Test {
    Deployer private deployer;
    CanonBridge private bridge; // predecessor
    CanonDisputeVerifier private verifier;

    /// @notice Local copy of `CanonMigration.MIN_GRACE_WINDOW_BLOCKS`
    ///         (Solidity 0.8.20 doesn't allow accessing public
    ///         constants via the contract type, only via an
    ///         instance).  `test_min_grace_window_constant` confirms
    ///         this matches the contract's getter.
    uint256 private constant MIN_GRACE = 216_000;

    uint256 private constant ATTESTOR_PK = 0xA77E5701;
    address private attestor;
    address private sequencer = address(0xBEEF);
    address private user = address(0xA1);

    event MigrationProposed(
        address indexed predecessor,
        address indexed successor,
        bytes32 migrationStateRoot,
        uint64 migrationStateRootLogIdx,
        uint256 graceWindowBlocks,
        uint256 proposedAtBlock
    );
    event MigrationActivated(
        address indexed predecessor, address indexed successor, uint256 atBlock
    );

    function setUp() public {
        attestor = vm.addr(ATTESTOR_PK);
        deployer = new Deployer();

        address[] memory adjudicators = new address[](2);
        adjudicators[0] = address(0xA001);
        adjudicators[1] = address(0xA002);

        uint64[] memory rids = new uint64[](0);
        address[] memory toks = new address[](0);

        Deployer.Deployment memory d = deployer.deployAll(
            attestor, sequencer, adjudicators,
            uint8(2), uint64(100), uint64(50),
            uint64(200), uint64(50),
            uint256(1000 ether), uint256(5000),
            rids, toks
        );
        bridge = d.bridge;
        verifier = d.verifier;
    }

    // ------------------------------------------------------------------
    // Constructor sanity tests
    // ------------------------------------------------------------------

    function test_min_grace_window_constant() public {
        // We can only read the constant via an instance.  Deploy a
        // throwaway migration with a valid attestation and check
        // it surfaces 216_000 (≈ 30 days at 12s blocks).
        address predictedMig = predictedMigrationAddress();
        CanonBridge successor = _deploySuccessor(predictedMig);
        bytes memory sig = _signMigration(
            address(bridge),
            address(successor),
            216_000,
            bytes32(0),
            uint64(0),
            predictedMig,
            ATTESTOR_PK
        );
        CanonMigration mig = _create3DeployMigration(
            address(bridge), address(successor), 216_000, bytes32(0), uint64(0), sig
        );
        assertEq(mig.MIN_GRACE_WINDOW_BLOCKS(), 216_000);
    }

    function test_constructor_reverts_on_zero_predecessor() public {
        bytes memory dummySig = new bytes(65);
        vm.expectRevert(CanonMigration.ZeroAddress.selector);
        new CanonMigration(
            address(0),
            address(bridge),
            MIN_GRACE,
            bytes32(0),
            uint64(0),
            dummySig
        );
    }

    function test_constructor_reverts_on_zero_successor() public {
        bytes memory dummySig = new bytes(65);
        vm.expectRevert(CanonMigration.ZeroAddress.selector);
        new CanonMigration(
            address(bridge),
            address(0),
            MIN_GRACE,
            bytes32(0),
            uint64(0),
            dummySig
        );
    }

    function test_constructor_reverts_on_self_migration() public {
        bytes memory dummySig = new bytes(65);
        vm.expectRevert(CanonMigration.SelfMigration.selector);
        new CanonMigration(
            address(bridge),
            address(bridge),
            MIN_GRACE,
            bytes32(0),
            uint64(0),
            dummySig
        );
    }

    function test_constructor_reverts_on_grace_too_short() public {
        // Need a successor bridge with proper migration immutable.
        CanonBridge successor = _deploySuccessor(predictedMigrationAddress());
        bytes memory dummySig = new bytes(65);

        vm.expectRevert(CanonMigration.GraceTooShort.selector);
        new CanonMigration(
            address(bridge),
            address(successor),
            MIN_GRACE - 1,
            bytes32(0),
            uint64(0),
            dummySig
        );
    }

    function test_constructor_reverts_on_successor_does_not_reference_this() public {
        // Deploy a successor whose `migration` immutable is set to a
        // *wrong* address (different from where we'll deploy this
        // migration).
        CanonBridge wrongRefSuccessor =
            _deploySuccessorAt(address(0xDEADBEEF), keccak256("wrong-ref-successor"));

        bytes memory dummySig = new bytes(65);
        vm.expectRevert(CanonMigration.SuccessorDoesNotReferenceThisMigration.selector);
        new CanonMigration(
            address(bridge),
            address(wrongRefSuccessor),
            MIN_GRACE,
            bytes32(0),
            uint64(0),
            dummySig
        );
    }

    function test_constructor_reverts_on_invalid_attestation() public {
        address predictedMig = predictedMigrationAddress();
        CanonBridge successor = _deploySuccessor(predictedMig);

        // Sign with the WRONG key (a non-attestor).
        uint256 evilPk = 0xEEEEEE;
        bytes memory wrongSig = _signMigration(
            address(bridge),
            address(successor),
            MIN_GRACE,
            bytes32(0),
            uint64(0),
            predictedMig,
            evilPk
        );

        vm.expectRevert(CanonMigration.AttestationInvalid.selector);
        _create3DeployMigration(
            address(bridge),
            address(successor),
            MIN_GRACE,
            bytes32(0),
            uint64(0),
            wrongSig
        );
    }

    function test_constructor_reverts_on_invalid_signature_length() public {
        address predictedMig = predictedMigrationAddress();
        CanonBridge successor = _deploySuccessor(predictedMig);
        bytes memory shortSig = hex"deadbeef"; // 4 bytes
        vm.expectRevert(CanonMigration.InvalidSignatureLength.selector);
        _create3DeployMigration(
            address(bridge),
            address(successor),
            MIN_GRACE,
            bytes32(0),
            uint64(0),
            shortSig
        );
    }

    // ------------------------------------------------------------------
    // Happy-path: full migration lifecycle
    // ------------------------------------------------------------------

    function test_full_migration_lifecycle() public {
        bytes32 stateRoot = keccak256("frozen-state-root");
        uint64 stateRootLogIdx = 42;

        // For the lifecycle test we need a *predecessor that
        // knows about the migration* so the predecessor's
        // `MigrationActivated` breaker can fire.  The Deployer-
        // built bridge (`bridge`) has `migration = address(0)` and
        // is inert.  We deploy a dedicated predecessor + successor
        // pair here, both pointing at the migration we are about
        // to deploy.
        //
        // Nonce timeline:
        //   nonce N   : deploy predecessor (bumps to N+1)
        //   nonce N+1 : deploy successor   (bumps to N+2)
        //   nonce N+2 : deploy migration   (bumps to N+3)
        // Predicted migration address: computeCreateAddress(this, N+2).
        uint64 nonce0 = vm.getNonce(address(this));
        address predictedMig =
            vm.computeCreateAddress(address(this), uint256(nonce0) + 2);

        CanonBridge predecessor =
            _deployBridgeWithMigration(predictedMig, "predecessor-v1");
        CanonBridge successor =
            _deployBridgeWithMigration(predictedMig, "successor-v1");

        bytes memory sig = _signMigration(
            address(predecessor),
            address(successor),
            MIN_GRACE,
            stateRoot,
            stateRootLogIdx,
            predictedMig,
            ATTESTOR_PK
        );

        vm.expectEmit(true, true, false, true);
        emit MigrationProposed(
            address(predecessor),
            address(successor),
            stateRoot,
            stateRootLogIdx,
            MIN_GRACE,
            block.number
        );
        CanonMigration mig = new CanonMigration(
            address(predecessor),
            address(successor),
            MIN_GRACE,
            stateRoot,
            stateRootLogIdx,
            sig
        );

        assertEq(address(mig), predictedMig);
        assertFalse(mig.activated());
        assertEq(mig.predecessor(), address(predecessor));
        assertEq(mig.successor(), address(successor));
        assertEq(mig.migrationStateRoot(), stateRoot);
        assertEq(mig.migrationStateRootLogIdx(), stateRootLogIdx);

        // Activate prematurely → reverts.
        vm.expectRevert(CanonMigration.GraceNotElapsed.selector);
        mig.activate();

        // Roll past grace window; activate.
        vm.roll(block.number + MIN_GRACE);
        vm.expectEmit(true, true, false, true);
        emit MigrationActivated(address(predecessor), address(successor), block.number);
        mig.activate();

        assertTrue(mig.activated());

        // Re-activate reverts.
        vm.expectRevert(CanonMigration.AlreadyActivated.selector);
        mig.activate();

        // Predecessor's MigrationActivated breaker now trips on
        // state-shaping calls.  Withdrawals (withdrawalOpen) still
        // work — the user-exit guarantee.
        vm.deal(user, 10 ether);
        vm.expectRevert(CanonBridge.MigrationActivated.selector);
        vm.prank(user);
        predecessor.depositETH{value: 1 ether}();
    }

    /// @notice Deploy a fresh bridge with a specific `migration`
    ///         immutable.  Used by the lifecycle test to build a
    ///         predecessor + successor pair that both know about
    ///         the migration we are about to deploy.
    function _deployBridgeWithMigration(address migrationAddr, bytes memory tag)
        internal
        returns (CanonBridge)
    {
        uint64[] memory rids = new uint64[](0);
        address[] memory toks = new address[](0);
        return new CanonBridge(
            CanonBridge.ConstructorArgs({
                canonVersionTag: keccak256(tag),
                attestor: attestor,
                disputeVerifier: address(verifier),
                sequencerStake: address(0x9999),
                migration: migrationAddr,
                disputeWindowBlocks: uint64(100),
                maxRedemptionWindowBlocks: uint64(50),
                maxAttestationStaleBlocks: uint64(200),
                cooldownBlocks: uint64(50),
                tvlCap: uint256(1000 ether),
                erc20ResourceIds: rids,
                erc20TokenAddrs: toks
            })
        );
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /// @notice Predict the address of the next `new CanonMigration(...)`
    ///         deployment from this test contract, accounting for
    ///         the successor's CREATE2 deploy that happens between
    ///         the prediction and the actual migration `new`.
    ///         CREATE2 increments the deployer's nonce per the
    ///         EVM spec, so the migration lands at `currentNonce
    ///         + 1` (the +1 covers the upcoming successor deploy).
    function predictedMigrationAddress() internal view returns (address) {
        return vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
    }

    function _create3DeployMigration(
        address predecessor_,
        address successor_,
        uint256 grace,
        bytes32 stateRoot,
        uint64 stateRootLogIdx,
        bytes memory sig
    ) internal returns (CanonMigration) {
        return new CanonMigration(
            predecessor_, successor_, grace, stateRoot, stateRootLogIdx, sig
        );
    }

    /// @notice Deploy a fresh successor bridge that records
    ///         `migrationAddr` as its `migration` immutable.
    function _deploySuccessor(address migrationAddr) internal returns (CanonBridge) {
        return _deploySuccessorAt(migrationAddr, keccak256("successor-bridge-salt"));
    }

    function _deploySuccessorAt(address migrationAddr, bytes32 salt)
        internal
        returns (CanonBridge)
    {
        uint64[] memory rids = new uint64[](0);
        address[] memory toks = new address[](0);
        bytes memory init = abi.encodePacked(
            type(CanonBridge).creationCode,
            abi.encode(
                CanonBridge.ConstructorArgs({
                    canonVersionTag: keccak256("canon-test-v2-successor"),
                    attestor: attestor,
                    disputeVerifier: address(verifier), // re-use; just for sanity
                    sequencerStake: address(0x9999),
                    migration: migrationAddr,
                    disputeWindowBlocks: uint64(100),
                    maxRedemptionWindowBlocks: uint64(50),
                    maxAttestationStaleBlocks: uint64(200),
                    cooldownBlocks: uint64(50),
                    tvlCap: uint256(1000 ether),
                    erc20ResourceIds: rids,
                    erc20TokenAddrs: toks
                })
            )
        );
        // Use plain CREATE2 — successor address can be anything;
        // it doesn't need a stable derivation here.
        address addr;
        assembly {
            addr := create2(0, add(init, 0x20), mload(init), salt)
        }
        require(addr != address(0), "successor deploy failed");
        return CanonBridge(payable(addr));
    }

    function _signMigration(
        address predecessor_,
        address successor_,
        uint256 grace,
        bytes32 stateRoot,
        uint64 stateRootLogIdx,
        address migAddr,
        uint256 pk
    ) internal view returns (bytes memory) {
        bytes32 ds = CanonEip712.domainSeparator(
            "Canon", "1", block.chainid, uint256(0), migAddr
        );
        bytes32 sh = CanonEip712.migrationStructHash(
            CanonBridge(payable(predecessor_)).deploymentId(),
            CanonBridge(payable(successor_)).deploymentId(),
            stateRoot,
            stateRootLogIdx,
            grace
        );
        bytes32 digest = CanonEip712.digest(ds, sh);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
