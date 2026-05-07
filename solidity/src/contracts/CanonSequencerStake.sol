// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ICanonSequencerStake} from "src/interfaces/ICanonSequencerStake.sol";
import {ICanonBridge} from "src/interfaces/ICanonBridge.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title CanonSequencerStake
/// @notice The sequencer's stake escrow.  On `DisputeUpheld`, the
///         stake is slashed: a `slashRatioBps` portion is paid to
///         the challenger as the reward documented in Phase-6's
///         incentive amendment (`DisputeRewardPolicy`); the
///         residual is sent to the canonical burn address.
///
/// @dev    Per workstream E.4 of the integration plan, this
///         contract is deployed immutably: no proxy, no admin
///         role, no upgrade hook.  All addresses (`sequencer`,
///         `disputeVerifier`, `bridge`) plus `slashRatioBps`,
///         `disputeWindowBlocks`, `burnAddress` are `immutable`.
///         Rotating any of them requires a new deployment plus a
///         `CanonMigration` handoff (§9.5).
contract CanonSequencerStake is ICanonSequencerStake, ReentrancyGuard {
    // ------------------------------------------------------------------
    // Custom errors
    // ------------------------------------------------------------------

    error NotSequencer();
    error NotDisputeVerifier();
    error InsufficientStake();
    error WithdrawDuringOpenDispute();
    error AlreadySlashed(uint64 disputeId);
    error SlashRatioOutOfRange();
    error ZeroAddress();
    error EthSendFailed();

    // ------------------------------------------------------------------
    // Immutable parameters
    // ------------------------------------------------------------------

    bytes32 public immutable canonVersionTag;
    bytes32 public immutable deploymentId;

    address public immutable sequencer;
    address public immutable disputeVerifier;
    address public immutable bridge;
    address public immutable burnAddress;

    /// @notice Slash percentage in basis points (e.g. 5000 = 50%).
    uint256 public immutable slashRatioBps;
    /// @notice Block-window length consulted for stake-withdrawal
    ///         lock-up.  Set in the constructor; immutable.
    uint64 public immutable disputeWindowBlocks;

    // ------------------------------------------------------------------
    // Mutable state
    // ------------------------------------------------------------------

    uint256 public totalStaked;
    mapping(uint64 => bool) private _slashedDispute;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    event Deposited(address indexed sequencer, uint256 amount, uint256 newTotal);
    event Withdrawn(address indexed sequencer, uint256 amount, uint256 newTotal);
    event Slashed(
        uint64 indexed disputeId,
        address indexed challenger,
        uint256 paidToChallenger,
        uint256 burned,
        uint256 newTotal
    );

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    constructor(
        bytes32 _canonVersionTag,
        address _sequencer,
        address _disputeVerifier,
        address _bridge,
        uint256 _slashRatioBps,
        uint64 _disputeWindowBlocks,
        address _burnAddress
    ) {
        if (_slashRatioBps > 10_000) revert SlashRatioOutOfRange();
        if (
            _sequencer == address(0) || _disputeVerifier == address(0)
                || _bridge == address(0) || _burnAddress == address(0)
        ) {
            revert ZeroAddress();
        }
        // Cross-contract back-reference (verifier.sequencerStake() ==
        // address(this)) is checked via the post-deploy
        // `assertConsistent()` view, not in the constructor.  Same
        // rationale as `CanonDisputeVerifier`: the back-check is
        // defensive, not load-bearing.
        canonVersionTag = _canonVersionTag;
        sequencer = _sequencer;
        disputeVerifier = _disputeVerifier;
        bridge = _bridge;
        burnAddress = _burnAddress;
        slashRatioBps = _slashRatioBps;
        disputeWindowBlocks = _disputeWindowBlocks;
        deploymentId =
            keccak256(abi.encode(block.chainid, address(this), _canonVersionTag));
    }

    // ------------------------------------------------------------------
    // External: deposit (sequencer-only, payable)
    // ------------------------------------------------------------------

    function deposit() external payable {
        if (msg.sender != sequencer) revert NotSequencer();
        // checked-arithmetic add via 0.8.20 default
        totalStaked += msg.value;
        emit Deposited(msg.sender, msg.value, totalStaked);
    }

    // ------------------------------------------------------------------
    // External: withdraw (sequencer-only, lock-up enforced)
    // ------------------------------------------------------------------

    function withdraw(uint256 amount) external nonReentrant {
        if (msg.sender != sequencer) revert NotSequencer();
        if (amount == 0 || amount > totalStaked) revert InsufficientStake();

        // Lock-up: the sequencer cannot withdraw while there is an
        // open / unfinalised state root within the dispute window.
        // The bridge's `hasOpenDisputeOlderThan` getter is the
        // authoritative oracle.
        uint64 threshold = block.number > disputeWindowBlocks
            ? uint64(block.number - disputeWindowBlocks)
            : 0;
        if (ICanonBridge(bridge).hasOpenDisputeOlderThan(threshold)) {
            revert WithdrawDuringOpenDispute();
        }

        // Effects before interaction.
        totalStaked -= amount;
        emit Withdrawn(msg.sender, amount, totalStaked);
        Address.sendValue(payable(sequencer), amount);
    }

    // ------------------------------------------------------------------
    // External: slash (dispute-verifier-only)
    // ------------------------------------------------------------------

    /// @inheritdoc ICanonSequencerStake
    function slash(uint64 disputeId, address challenger)
        external
        nonReentrant
    {
        if (msg.sender != disputeVerifier) revert NotDisputeVerifier();
        if (_slashedDispute[disputeId]) revert AlreadySlashed(disputeId);
        if (challenger == address(0)) revert ZeroAddress();

        // Compute the slashable amount based on the *current*
        // total stake.  If the stake has been entirely drained
        // (e.g. previously slashed), the amount may be zero —
        // we still mark the dispute slashed to preserve
        // idempotency.
        uint256 stakeAtTime = totalStaked;
        uint256 paid = (stakeAtTime * slashRatioBps) / 10_000;
        uint256 burned = stakeAtTime - paid;

        // Effects before interactions.
        _slashedDispute[disputeId] = true;
        totalStaked = 0;

        emit Slashed(disputeId, challenger, paid, burned, totalStaked);

        // Interactions: pay challenger, burn residual.
        if (paid > 0) Address.sendValue(payable(challenger), paid);
        if (burned > 0) Address.sendValue(payable(burnAddress), burned);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function isSlashed(uint64 disputeId) external view returns (bool) {
        return _slashedDispute[disputeId];
    }

    /// @notice Symmetric cross-contract consistency check.  Returns
    ///         `true` iff this stake's `disputeVerifier` immutable
    ///         points at a verifier whose `sequencerStake` immutable
    ///         points back at this stake contract.  Anyone may call.
    function assertConsistent() external view returns (bool) {
        return ICanonSequencerStakePeer(disputeVerifier).sequencerStake() == address(this);
    }

    // ------------------------------------------------------------------
    // ETH receive — must come via deposit()
    // ------------------------------------------------------------------

    receive() external payable {
        revert("CanonSequencerStake: bare ETH transfers not allowed; use deposit()");
    }
}

/// @notice Minimal interface used by `assertConsistent()` to read
///         the verifier's sequencerStake reference without pulling
///         in the full `ICanonDisputeVerifier` ABI.
interface ICanonSequencerStakePeer {
    function sequencerStake() external view returns (address);
}
