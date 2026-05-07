// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/// @title ICanonDisputeVerifier
/// @notice External-facing surface of `CanonDisputeVerifier.sol`.  Exposes
///         the immutable getters used by sibling contracts (notably
///         `CanonSequencerStake` for the slashing wiring and
///         `CanonBridge` for the construction-time cross-check).
interface ICanonDisputeVerifier {
    /// @notice The deployment-id mirror, identical-shape to
    ///         `ICanonBridge.deploymentId`.
    function deploymentId() external view returns (bytes32);

    /// @notice The `CanonBridge` this verifier is paired with.
    ///         Immutable.
    function bridge() external view returns (address);

    /// @notice The `CanonSequencerStake` this verifier slashes.
    ///         Immutable.
    function sequencerStake() external view returns (address);

    /// @notice The `CanonIdentityRegistry` consulted for verifying
    ///         signer registration.  Immutable.
    function identityRegistry() external view returns (address);

    /// @notice The `CanonMigration` address (may be `address(0)`).
    ///         Immutable.
    function migration() external view returns (address);

    /// @notice Quorum threshold for verdict finalisation; immutable.
    function quorumThreshold() external view returns (uint8);

    /// @notice Whether `addr` is in the snapshotted approved-adjudicator
    ///         set.  Set in the constructor; immutable thereafter.
    function isApprovedAdjudicator(address addr) external view returns (bool);

    /// @notice Whether the dispute with id `disputeId` is in the
    ///         `.open` state (filed, not yet decided).  Used by
    ///         `CanonSequencerStake.withdraw` lock-up.
    function isDisputeOpen(uint64 disputeId) external view returns (bool);
}
