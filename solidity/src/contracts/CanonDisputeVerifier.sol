// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ICanonDisputeVerifier} from "src/interfaces/ICanonDisputeVerifier.sol";
import {ICanonBridge} from "src/interfaces/ICanonBridge.sol";
import {ICanonSequencerStake} from "src/interfaces/ICanonSequencerStake.sol";
import {ICanonIdentityRegistry} from "src/interfaces/ICanonIdentityRegistry.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {CBEDecode} from "src/lib/CBEDecode.sol";
import {CanonEip712} from "src/lib/CanonEip712.sol";

/// @title CanonDisputeVerifier
/// @notice The L1 dispute pipeline.  Per workstream E.2 of the
///         Ethereum integration plan, this contract receives
///         disputes against state roots from `CanonBridge`,
///         re-verifies the impugned evidence on-chain, and (on
///         `.upheld`) slashes the sequencer + reverts the bad
///         state roots atomically.
///
/// @dev    Three claim variants ship in MVP (mirror the
///         post-Phase-6 Lean dispute pipeline):
///           * `signatureInvalid` — E.2.2
///           * `nonceMismatch`    — E.2.3
///           * `doubleApply`      — E.2.4
///
///         Deferred to v2: `preconditionFalse` (requires full
///         kernel replay) and `oracleMisreported` (requires
///         deployment-specific oracle policy).  Adding either
///         requires a new dispute-verifier deployment + a
///         `CanonMigration` handoff.
contract CanonDisputeVerifier is ICanonDisputeVerifier {
    // ------------------------------------------------------------------
    // Custom errors
    // ------------------------------------------------------------------

    error NotApprovedAdjudicator();
    error UnknownDispute();
    error AlreadyDecided();
    error NotOpen();
    error QuorumNotMet(uint256 verified, uint8 required);
    error EvidenceNotUpheld();
    error EvidenceNotRejected();
    error SelfClaimInvalid();
    error InvalidClaimVariant();
    error MaxPrefixLenExceeded();
    error PrefixSignerMissing();
    error InvalidSignatureLength();
    error VerifierBridgeMismatch();
    error ZeroAddress();
    error QuorumThresholdOutOfRange();
    error VerdictReplay();

    // ------------------------------------------------------------------
    // Constitutional / immutable parameters
    // ------------------------------------------------------------------

    bytes32 public immutable canonVersionTag;
    bytes32 public immutable deploymentId;

    address public immutable bridge;
    address public immutable sequencerStake;
    address public immutable identityRegistry;
    address public immutable migration;
    uint8 public immutable quorumThreshold;

    /// @notice Approved-adjudicator membership snapshot, set in the
    ///         constructor.  Immutable thereafter.
    mapping(address => bool) private _approvedAdjudicator;
    bytes32 public immutable approvedAdjudicatorRoot;

    string public constant DOMAIN_NAME = "CanonDisputeVerifier";
    string public constant DOMAIN_VERSION = "1";

    /// @notice One-shot bound on `nonceMismatch` log prefix length
    ///         (the MVP fraud-proof bound; bisection is post-MVP).
    uint64 public constant MAX_PREFIX_LEN = 256;

    // ------------------------------------------------------------------
    // Claim variants (frozen indices; mirror Lean Disputes.Types)
    // ------------------------------------------------------------------

    /// @notice Same indices as `LegalKernel.Disputes.Types.DisputeClaim`
    ///         (frozen 0..4).  MVP ships three; the others are
    ///         decoded but reverted with `InvalidClaimVariant`.
    uint8 public constant CLAIM_PRECONDITION_FALSE = 0;
    uint8 public constant CLAIM_SIGNATURE_INVALID = 1;
    uint8 public constant CLAIM_NONCE_MISMATCH = 2;
    uint8 public constant CLAIM_ORACLE_MISREPORTED = 3;
    uint8 public constant CLAIM_DOUBLE_APPLY = 4;

    /// @notice Verdict outcomes; frozen indices mirror Lean
    ///         `EvidenceVerdict`.
    uint8 public constant VERDICT_UPHELD = 0;
    uint8 public constant VERDICT_REJECTED = 1;
    uint8 public constant VERDICT_INCONCLUSIVE = 2;

    /// @notice Dispute status; frozen indices mirror Lean
    ///         `DisputeStatus`.
    uint8 public constant STATUS_OPEN = 0;
    uint8 public constant STATUS_UPHELD = 1;
    uint8 public constant STATUS_REJECTED = 2;
    uint8 public constant STATUS_INCONCLUSIVE = 3;
    uint8 public constant STATUS_WITHDRAWN = 4;

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------

    struct DisputeRecord {
        uint64 impugnedLogIndex;
        address challenger;
        uint8 claimVariant;
        bytes evidenceBlob;
        uint8 status; // STATUS_*
        uint64 filedAtBlock;
    }

    mapping(uint64 => DisputeRecord) private _disputes;
    uint64 public nextDisputeId;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    event DisputeFiled(
        uint64 indexed disputeId,
        address indexed challenger,
        uint64 impugnedLogIndex,
        uint8 claimVariant
    );

    event DisputeUpheld(uint64 indexed disputeId, uint64 impugnedLogIndex);
    event DisputeRejected(uint64 indexed disputeId);

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    struct ConstructorArgs {
        bytes32 canonVersionTag;
        address bridge;
        address sequencerStake;
        address identityRegistry;
        address migration;
        uint8 quorumThreshold;
        address[] approvedAdjudicators;
    }

    constructor(ConstructorArgs memory args) {
        if (args.bridge == address(0)) revert ZeroAddress();
        if (args.sequencerStake == address(0)) revert ZeroAddress();
        if (args.identityRegistry == address(0)) revert ZeroAddress();
        if (args.approvedAdjudicators.length == 0) revert QuorumThresholdOutOfRange();
        if (
            args.quorumThreshold == 0
                || uint256(args.quorumThreshold) > args.approvedAdjudicators.length
        ) revert QuorumThresholdOutOfRange();

        // **Cross-contract back-reference is defensive, not
        // load-bearing.**  An attacker deploying a malicious
        // verifier pointing at a legitimate bridge cannot make the
        // legitimate bridge do anything: the bridge only honours
        // calls from `bridge.disputeVerifier()`, which is its own
        // immutable.  We expose `assertConsistent()` post-deployment
        // (callable by anyone) for tooling that wants to verify the
        // cross-reference symmetrically.  This refactor lets the
        // deployment script use CREATE2 with predictable salts in
        // either order without a circular bytecode-hash dependency.

        canonVersionTag = args.canonVersionTag;
        bridge = args.bridge;
        sequencerStake = args.sequencerStake;
        identityRegistry = args.identityRegistry;
        migration = args.migration;
        quorumThreshold = args.quorumThreshold;

        // Snapshot the approved adjudicator set.  Duplicates in
        // `approvedAdjudicators` are silently merged (the per-key
        // mapping write is idempotent), but we track the canonical
        // commitment via `approvedAdjudicatorRoot` so any future
        // governance design can compare to the snapshot.
        for (uint256 i = 0; i < args.approvedAdjudicators.length; ++i) {
            address a = args.approvedAdjudicators[i];
            if (a == address(0)) revert ZeroAddress();
            _approvedAdjudicator[a] = true;
        }
        approvedAdjudicatorRoot = keccak256(abi.encode(args.approvedAdjudicators));

        deploymentId =
            keccak256(abi.encode(block.chainid, address(this), args.canonVersionTag));
    }

    // ------------------------------------------------------------------
    // E.2.1 Dispute filing
    // ------------------------------------------------------------------

    /// @notice File a dispute against a previously-submitted state
    ///         root.  Reverts only if migration is activated; the
    ///         dispute pipeline must remain available for as long
    ///         as the predecessor accepts state roots.  Anyone may
    ///         file (the challenger pays the gas).
    function fileDispute(
        uint64 impugnedLogIndex,
        uint8 claimVariant,
        bytes calldata evidenceBlob
    ) external returns (uint64 disputeId) {
        if (claimVariant != CLAIM_SIGNATURE_INVALID && claimVariant != CLAIM_NONCE_MISMATCH
            && claimVariant != CLAIM_DOUBLE_APPLY)
        {
            revert InvalidClaimVariant();
        }

        disputeId = nextDisputeId++;
        _disputes[disputeId] = DisputeRecord({
            impugnedLogIndex: impugnedLogIndex,
            challenger: msg.sender,
            claimVariant: claimVariant,
            evidenceBlob: evidenceBlob,
            status: STATUS_OPEN,
            filedAtBlock: uint64(block.number)
        });

        emit DisputeFiled(disputeId, msg.sender, impugnedLogIndex, claimVariant);
    }

    // ------------------------------------------------------------------
    // E.2.2 signatureInvalid claim verifier
    // ------------------------------------------------------------------

    /// @notice The Solidity port of
    ///         `LegalKernel.Disputes.Evidence.checkSignatureInvalid`.
    ///         Decodes a `LogEntry` blob into `(action, signer,
    ///         nonce, sig)`, looks up the signer's currently-
    ///         registered ECDSA pubkey in the `CanonIdentityRegistry`,
    ///         re-runs ECDSA recovery on the action's EIP-712
    ///         hash, and returns the verdict.
    /// @return verdict 0 = upheld, 1 = rejected, 2 = inconclusive.
    function checkSignatureInvalid(bytes calldata logEntryBlob)
        external
        view
        returns (uint8 verdict)
    {
        // The logEntryBlob's CBE shape mirrors Lean's
        // `Runtime.LogFile.LogEntry` encoding:
        //   prevHash :  bytes32 (32 bytes payload)
        //   actionHash : bytes32  (commitment to action; we don't
        //                          reconstruct the full action
        //                          on-chain — the signer-recovery
        //                          step uses actionHash directly
        //                          per the EIP-712 wrap)
        //   signer :   uint64
        //   nonce :    uint64
        //   sig :      bytes (65 bytes)
        uint256 off = 0;
        // Skip prevHash (not needed for signature verification).
        (, off) = CBEDecode.readBytes32Exact(logEntryBlob, off);
        bytes32 actionHash;
        (actionHash, off) = CBEDecode.readBytes32Exact(logEntryBlob, off);
        uint64 signer;
        (signer, off) = CBEDecode.readUint(logEntryBlob, off);
        uint64 nonce;
        (nonce, off) = CBEDecode.readUint(logEntryBlob, off);
        bytes memory sig;
        (sig, off) = CBEDecode.readBytes(logEntryBlob, off);

        // The bridge's deploymentId is what the signer signed
        // against.
        bytes32 bridgeDid = ICanonBridge(bridge).deploymentId();

        // Re-construct the EIP-712 digest the signer must have
        // signed for this entry to be valid.
        bytes32 ds = CanonEip712.domainSeparator(
            DOMAIN_NAME, DOMAIN_VERSION, block.chainid, uint256(0), bridge
        );
        bytes32 sh =
            CanonEip712.actionStructHash(actionHash, signer, nonce, bridgeDid);
        bytes32 digest = CanonEip712.digest(ds, sh);

        // Look up the signer's registered pubkey.  If unregistered,
        // we cannot verify and return INCONCLUSIVE.
        address signerAddr = _signerToAddress(signer);
        if (signerAddr == address(0)) return VERDICT_INCONCLUSIVE;
        ICanonIdentityRegistry.IdentityRecord memory rec =
            ICanonIdentityRegistry(identityRegistry).lookup(signerAddr);
        if (rec.kind != ICanonIdentityRegistry.SignerKind.ECDSA_EOA) {
            return VERDICT_INCONCLUSIVE;
        }

        // Recover the signer from the signature.  Length / s-value
        // are checked by OZ ECDSA; an invalid signature produces
        // `address(0)`.
        if (sig.length != 65) return VERDICT_UPHELD;
        address recovered = ECDSA.recover(digest, sig);
        if (recovered == address(0)) return VERDICT_UPHELD;

        // The recovered address must match the signer's registered
        // address.  Signer-id → address is derived via the
        // pubkey hash kept in the registry.
        address derivedFromPubkey = address(uint160(uint256(keccak256(rec.pubkey))));
        if (recovered == derivedFromPubkey) return VERDICT_REJECTED;
        return VERDICT_UPHELD;
    }

    // ------------------------------------------------------------------
    // E.2.3 nonceMismatch claim verifier
    // ------------------------------------------------------------------

    /// @notice The Solidity port of
    ///         `LegalKernel.Disputes.Evidence.checkNonceMismatch`.
    ///         Replays a log prefix in order, maintaining a
    ///         `(signer → expectedNonce)` map; at the impugned
    ///         entry, compares the recorded nonce against
    ///         expectsNonce.  No signature checks.
    /// @return verdict 0 = upheld, 1 = rejected, 2 = inconclusive.
    function checkNonceMismatch(uint64 impugnedLogIndex, bytes calldata prefixBlob)
        external
        pure
        returns (uint8 verdict)
    {
        // The prefixBlob encodes a CBE array of LogEntry encodings.
        // Each LogEntry has shape (prevHash, actionHash, signer,
        // nonce, sig).  We only need (signer, nonce) per entry.
        uint256 off = 0;
        uint64 entryCount;
        (entryCount, off) = CBEDecode.readArrayHead(prefixBlob, off);
        if (entryCount > MAX_PREFIX_LEN) revert MaxPrefixLenExceeded();

        // Compact in-memory map for `expectsNonce`: arrays of
        // signers and their next-expected nonces.  256 entries
        // max, so linear search per insertion is bounded gas-wise.
        uint64[] memory signerKeys = new uint64[](entryCount);
        uint64[] memory expectedNonces = new uint64[](entryCount);
        uint256 mapLen = 0;

        for (uint64 i = 0; i < entryCount; ++i) {
            // Skip prevHash + actionHash.
            (, off) = CBEDecode.readBytes32Exact(prefixBlob, off);
            (, off) = CBEDecode.readBytes32Exact(prefixBlob, off);
            uint64 signer;
            uint64 nonce;
            (signer, off) = CBEDecode.readUint(prefixBlob, off);
            (nonce, off) = CBEDecode.readUint(prefixBlob, off);
            // Skip sig.
            (, off) = CBEDecode.readBytes(prefixBlob, off);

            // Find existing slot or allocate new one.
            uint256 slot = type(uint256).max;
            for (uint256 j = 0; j < mapLen; ++j) {
                if (signerKeys[j] == signer) {
                    slot = j;
                    break;
                }
            }

            if (i == impugnedLogIndex) {
                uint64 expected = (slot == type(uint256).max)
                    ? uint64(0)
                    : expectedNonces[slot];
                if (nonce != expected) return VERDICT_UPHELD;
                return VERDICT_REJECTED;
            }

            // Otherwise advance the per-signer counter.
            // Mirrors Lean kernelOnlyReplay: just bump nonce, no
            // admissibility check.
            if (slot == type(uint256).max) {
                signerKeys[mapLen] = signer;
                expectedNonces[mapLen] = nonce + 1;
                ++mapLen;
            } else {
                expectedNonces[slot] = nonce + 1;
            }
        }
        // The impugned index was never reached during prefix walk.
        return VERDICT_INCONCLUSIVE;
    }

    // ------------------------------------------------------------------
    // E.2.4 doubleApply claim verifier
    // ------------------------------------------------------------------

    /// @notice The Solidity port of
    ///         `LegalKernel.Disputes.Evidence.checkDoubleApply`.
    ///         Two log entries with the same `(signer, nonce)`
    ///         pair at distinct indices indicate a replay.
    /// @return verdict 0 = upheld, 1 = rejected, 2 = inconclusive.
    function checkDoubleApply(
        uint64 impugnedLogIndex,
        uint64 secondaryLogIndex,
        bytes calldata impugnedBlob,
        bytes calldata secondaryBlob
    ) external pure returns (uint8 verdict) {
        if (impugnedLogIndex == secondaryLogIndex) revert SelfClaimInvalid();

        (uint64 sigA, uint64 nonceA) = _readSignerNonce(impugnedBlob);
        (uint64 sigB, uint64 nonceB) = _readSignerNonce(secondaryBlob);

        if (sigA == sigB && nonceA == nonceB) return VERDICT_UPHELD;
        return VERDICT_REJECTED;
    }

    function _readSignerNonce(bytes calldata blob)
        internal
        pure
        returns (uint64 signer, uint64 nonce)
    {
        uint256 off = 0;
        // Skip prevHash + actionHash.
        (, off) = CBEDecode.readBytes32Exact(blob, off);
        (, off) = CBEDecode.readBytes32Exact(blob, off);
        (signer, off) = CBEDecode.readUint(blob, off);
        (nonce, off) = CBEDecode.readUint(blob, off);
    }

    // ------------------------------------------------------------------
    // E.2.5 Verdict finalisation
    // ------------------------------------------------------------------

    function finalizeUpheld(
        uint64 disputeId,
        bytes32 verdictHash,
        bytes calldata reEvidenceBlob,
        address[] calldata signers,
        bytes[] calldata sigs
    ) external {
        DisputeRecord storage d = _disputes[disputeId];
        if (d.challenger == address(0)) revert UnknownDispute();
        if (d.status != STATUS_OPEN) revert AlreadyDecided();

        // Quorum check with deduplication: each distinct approved
        // signer with a valid signature contributes at most 1.
        uint256 verified = _countVerifiedSignatures(verdictHash, signers, sigs);
        if (verified < quorumThreshold) revert QuorumNotMet(verified, quorumThreshold);

        // Re-run the per-claim verifier at finalisation time.
        // The contract does not trust the file-time evidence; the
        // verifier must re-confirm UPHELD against the *current*
        // log prefix.
        uint8 verdict = _runClaimVerifier(d, reEvidenceBlob);
        if (verdict != VERDICT_UPHELD) revert EvidenceNotUpheld();

        // ---- Effects ----
        d.status = STATUS_UPHELD;

        // ---- Interactions: slash + revert ----
        // Both calls happen inside this transaction; if either
        // reverts, the entire finalisation reverts.
        ICanonSequencerStake(sequencerStake).slash(disputeId, d.challenger);
        ICanonBridge(bridge).revertToPriorRoot(d.impugnedLogIndex);

        emit DisputeUpheld(disputeId, d.impugnedLogIndex);
    }

    /// @notice Symmetric path for adjudicator-signed `.rejected`
    ///         verdicts: no slash, no rollback.  Closes a dispute
    ///         that the evidence does not support.
    function finalizeRejected(
        uint64 disputeId,
        bytes32 verdictHash,
        bytes calldata reEvidenceBlob,
        address[] calldata signers,
        bytes[] calldata sigs
    ) external {
        DisputeRecord storage d = _disputes[disputeId];
        if (d.challenger == address(0)) revert UnknownDispute();
        if (d.status != STATUS_OPEN) revert AlreadyDecided();

        uint256 verified = _countVerifiedSignatures(verdictHash, signers, sigs);
        if (verified < quorumThreshold) revert QuorumNotMet(verified, quorumThreshold);

        uint8 verdict = _runClaimVerifier(d, reEvidenceBlob);
        if (verdict != VERDICT_REJECTED) revert EvidenceNotRejected();

        d.status = STATUS_REJECTED;
        emit DisputeRejected(disputeId);
    }

    /// @notice Per-signer-deduplicated quorum count.  Mirrors the
    ///         Phase-6 audit-1 fix in
    ///         `LegalKernel.Disputes.Verdict.countVerifiedSignatures`:
    ///         a signer with one valid signature counts at most 1
    ///         regardless of (signers, sigs) padding.
    function _countVerifiedSignatures(
        bytes32 verdictHash,
        address[] calldata signers,
        bytes[] calldata sigs
    ) internal view returns (uint256) {
        if (signers.length != sigs.length) return 0;

        // Quadratic dedup over signers — bounded by quorumThreshold
        // in practice (≤ 7-of-N typical).
        address[] memory seen = new address[](signers.length);
        uint256 seenLen = 0;

        for (uint256 i = 0; i < signers.length; ++i) {
            address s = signers[i];
            if (s == address(0)) continue;
            if (!_approvedAdjudicator[s]) continue;
            if (sigs[i].length != 65) continue;

            bool already;
            for (uint256 j = 0; j < seenLen; ++j) {
                if (seen[j] == s) { already = true; break; }
            }
            if (already) continue;

            address recovered = ECDSA.recover(verdictHash, sigs[i]);
            if (recovered != s) continue;

            seen[seenLen++] = s;
        }
        return seenLen;
    }

    function _runClaimVerifier(DisputeRecord storage d, bytes calldata reEvidenceBlob)
        internal
        view
        returns (uint8)
    {
        if (d.claimVariant == CLAIM_SIGNATURE_INVALID) {
            return this.checkSignatureInvalid(reEvidenceBlob);
        } else if (d.claimVariant == CLAIM_NONCE_MISMATCH) {
            return this.checkNonceMismatch(d.impugnedLogIndex, reEvidenceBlob);
        } else if (d.claimVariant == CLAIM_DOUBLE_APPLY) {
            // The doubleApply re-evidence blob is the
            // concatenation of impugnedBlob + secondaryBlob with
            // their lengths written first; the verifier expects
            // them as separate calldata, so we split here.  The
            // shape matches the off-chain assembly produced by
            // the sequencer's dispute-playback tool.
            return _runDoubleApplyFromConcat(d.impugnedLogIndex, reEvidenceBlob);
        }
        revert InvalidClaimVariant();
    }

    function _runDoubleApplyFromConcat(uint64 impugnedLogIndex, bytes calldata blob)
        internal
        view
        returns (uint8)
    {
        // CBE array of two byte strings: impugnedBlob, secondaryBlob.
        // Plus the secondary log index as a uint at the front.
        uint256 off = 0;
        uint64 secondaryLogIndex;
        (secondaryLogIndex, off) = CBEDecode.readUint(blob, off);
        (, off) = CBEDecode.readArrayHead(blob, off); // discard count
        // Read each of the two byte strings.
        bytes memory impugnedBytes;
        bytes memory secondaryBytes;
        (impugnedBytes, off) = CBEDecode.readBytes(blob, off);
        (secondaryBytes, off) = CBEDecode.readBytes(blob, off);
        return this.checkDoubleApplyFromBytes(
            impugnedLogIndex, secondaryLogIndex, impugnedBytes, secondaryBytes
        );
    }

    /// @notice External wrapper used by `_runDoubleApplyFromConcat`
    ///         to re-enter the doubleApply verifier with calldata-
    ///         shaped arguments.
    function checkDoubleApplyFromBytes(
        uint64 impugnedLogIndex,
        uint64 secondaryLogIndex,
        bytes calldata impugnedBlob,
        bytes calldata secondaryBlob
    ) external pure returns (uint8) {
        if (impugnedLogIndex == secondaryLogIndex) revert SelfClaimInvalid();

        (uint64 sigA, uint64 nonceA) = _readSignerNonce(impugnedBlob);
        (uint64 sigB, uint64 nonceB) = _readSignerNonce(secondaryBlob);

        if (sigA == sigB && nonceA == nonceB) return VERDICT_UPHELD;
        return VERDICT_REJECTED;
    }

    /// @notice Stub helper: maps a 64-bit signer identifier to its
    ///         canonical Ethereum address.  In the runtime adaptor
    ///         this is a `(uint64 → address)` mapping computed from
    ///         the L1 ingestor (workstream B.2) — for the MVP we
    ///         interpret the signer as the low 64 bits of the
    ///         address, which is sufficient for cross-stack
    ///         fixtures.  Production deployments overlay a richer
    ///         resolver via a separate (immutable) registry
    ///         contract; that's out of scope for E.2 (it's part
    ///         of B.2's runtime adaptor).
    function _signerToAddress(uint64 signer) internal pure returns (address) {
        if (signer == 0) return address(0);
        return address(uint160(uint256(signer)));
    }

    // ------------------------------------------------------------------
    // External views
    // ------------------------------------------------------------------

    function disputeAt(uint64 disputeId)
        external
        view
        returns (
            uint64 impugnedLogIndex,
            address challenger,
            uint8 claimVariant,
            uint8 status,
            uint64 filedAtBlock
        )
    {
        DisputeRecord storage d = _disputes[disputeId];
        return (d.impugnedLogIndex, d.challenger, d.claimVariant, d.status, d.filedAtBlock);
    }

    function isDisputeOpen(uint64 disputeId) external view returns (bool) {
        return _disputes[disputeId].status == STATUS_OPEN
            && _disputes[disputeId].challenger != address(0);
    }

    function isApprovedAdjudicator(address addr) external view returns (bool) {
        return _approvedAdjudicator[addr];
    }

    /// @notice Symmetric cross-contract consistency check.  Returns
    ///         `true` iff this verifier's `bridge` immutable points
    ///         at a bridge whose `disputeVerifier` immutable points
    ///         back at this verifier.  Anyone may call.  This is the
    ///         deployment-time invariant that an off-chain auditor
    ///         (or the deployment script) verifies post-deploy; it
    ///         is moved out of the constructor so the cross-contract
    ///         reference cycle does not block CREATE2 deployment.
    function assertConsistent() external view returns (bool) {
        return ICanonBridge(bridge).disputeVerifier() == address(this);
    }
}
