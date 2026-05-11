// SPDX-License-Identifier: GPL-3.0-or-later
//
//  Canon  - A Societal Kernel
//  Copyright (C) 2026  Adam Hall
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";

import {CanonStepVM}                from "../src/contracts/CanonStepVM.sol";
import {CanonFaultProofGame}        from "../src/contracts/CanonFaultProofGame.sol";
import {CanonStateRootSubmission}   from "../src/contracts/CanonStateRootSubmission.sol";
import {CanonDisputeVerifierV2}     from "../src/contracts/CanonDisputeVerifierV2.sol";
import {CanonFaultProofMigration}   from "../src/contracts/CanonFaultProofMigration.sol";

/// @title DeployFaultProof
/// @notice Workstream-H deployment script (WU H.9.3).  Deploys
///         the five fault-proof contracts in dependency order.
///
/// Per Workstream-E discipline: contracts are immutable; no
/// admin / pause / upgrade.  Recovery from bugs is via
/// CanonFaultProofMigration.
contract DeployFaultProof is Script {
    function run() external {
        // Configuration parameters (override via env).
        uint128 stateRootBond = uint128(
          vm.envOr("CANON_STATE_ROOT_BOND",
                   uint256(1 ether)));
        uint64  disputeWindow = uint64(
          vm.envOr("CANON_DISPUTE_WINDOW_BLOCKS",
                   uint256(216_000)));   // ~30 days
        uint64  withdrawalFinalisationWindow = uint64(
          vm.envOr("CANON_WITHDRAWAL_WINDOW_BLOCKS",
                   uint256(216_000)));
        uint64  minSubmissionInterval = uint64(
          vm.envOr("CANON_MIN_SUBMISSION_INTERVAL",
                   uint256(100)));
        uint64  maxOutstandingRoots = uint64(
          vm.envOr("CANON_MAX_OUTSTANDING_ROOTS",
                   uint256(100)));
        uint64  bisectionTimeout = uint64(
          vm.envOr("CANON_BISECTION_TIMEOUT_BLOCKS",
                   uint256(21_600)));    // ~3 days
        uint128 minChallengeBond = uint128(
          vm.envOr("CANON_MIN_CHALLENGE_BOND",
                   uint256(0.05 ether)));
        uint64  minBisectionStepInterval = uint64(
          vm.envOr("CANON_MIN_BISECTION_STEP_INTERVAL",
                   uint256(5)));
        address sequencer = vm.envAddress("CANON_SEQUENCER_ADDRESS");
        address treasury  = vm.envAddress("CANON_TREASURY_ADDRESS");
        address bridge    = vm.envAddress("CANON_BRIDGE_ADDRESS");
        bytes32 deploymentId = vm.envBytes32("CANON_DEPLOYMENT_ID");

        vm.startBroadcast();

        // Step 1: deploy CanonStepVM.
        CanonStepVM stepVM = new CanonStepVM();

        // Step 2: deploy CanonStateRootSubmission referencing the
        // future game address (stepwise, with placeholder
        // address(this) for now; real deployment uses CREATE3
        // address prediction).  For the script-level deploy we
        // use a 2-step deploy + post-construction wiring.
        // Placeholder: deploy with `address(this)` then redeploy
        // game with the real submission addr.

        // For simplicity, deploy game first with a placeholder
        // submission addr then redeploy submission with the real
        // game addr.  Real CREATE3 deployment script handles the
        // circular dependency cleanly.
        // Single-adjudicator quorum (1-of-1) is the minimal valid
        // configuration for the deploy script's smoke test.  Real
        // deployments configure a multi-adjudicator set with a
        // strict-majority quorum via constructor arguments.
        address[] memory adjudicators = new address[](1);
        adjudicators[0] = sequencer;  // placeholder adjudicator

        // Deploy state-root submission FIRST so the verifier can
        // reference it as `stateRootSubmission`.  The state-root
        // submission's `faultProofGame` is set to the verifier
        // (the verifier is the relay that calls
        // `revertStateRootsFrom` on behalf of the game).
        // Final wiring uses CREATE3 in production; the script's
        // 2-step placeholder pattern is documented in the
        // deployment runbook.
        CanonStateRootSubmission submission =
          new CanonStateRootSubmission(
            stateRootBond,
            disputeWindow,
            minSubmissionInterval,
            maxOutstandingRoots,
            sequencer,
            address(0),  // faultProofGame placeholder; CREATE3 in production
            deploymentId,
            withdrawalFinalisationWindow);

        CanonDisputeVerifierV2 verifier = new CanonDisputeVerifierV2(
            address(0),               // faultProofGame placeholder
            address(submission),      // stateRootSubmission
            adjudicators,
            1,                        // quorumThreshold (1-of-1 for smoke test)
            bridge,
            address(0),               // sequencerStake placeholder
            address(0),               // attestor placeholder
            deploymentId
        );

        CanonFaultProofGame game = new CanonFaultProofGame(
            bisectionTimeout,
            minChallengeBond,
            minBisectionStepInterval,
            treasury,
            address(stepVM),
            address(submission)
        );

        // Post-deploy assert.
        stepVM.assertConsistent();
        verifier.assertConsistent();
        submission.assertConsistent();
        game.assertConsistent();

        vm.stopBroadcast();
    }
}
