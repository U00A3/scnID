// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPersonhoodAdapter} from "../../interfaces/IPersonhoodAdapter.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @notice Minimal Groth16 verifier interface, same shape as the iden3 on-chain verifier.
interface IGroth16Verifier {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[] calldata pubSignals
    ) external view returns (bool);
}

/// @title ReceptorNullifierAdapter
/// @notice Uniqueness from the nullifier in an iden3 V3 proof. No attestors are needed,
///         only trust in the credential issuer.
///
/// @dev Not usable on Redbelly yet. Receptor ships only V2 circuits
///      (credentialAtomicQuerySigV2, credentialAtomicQueryMTPV2 and their OnChain
///      versions), and V2 has no nullifier. As of 2026-09-03 the Redbelly docs make no
///      mention of credentialAtomicQueryV3. We deploy this disabled so that moving to it
///      later is a configuration change.
///
///      In iden3/circuits, lib/utils/nullify.circom computes
///
///        nullifier = Poseidon(5)([genesisID, claimSubjectProfileNonce,
///                                 claimSchema, verifierID, nullifierSessionID])
///
///      and returns 0 if claimSubjectProfileNonce, verifierID or nullifierSessionID is 0.
///
///      `genesisID` is the holder's root identity and is a private input, so we never see
///      it. `verifierID` and `nullifierSessionID` are public inputs that we choose. If
///      both are pinned to constants, the nullifier is a stable pseudonym for the person
///      across all of their wallets.
///
///      One gap remains. `claimSubjectProfileNonce` is fixed when the credential is
///      issued, to whichever profile the holder chose. Someone who gets two credentials
///      of the same schema on two profiles of the same genesisID gets two nullifiers, and
///      the issuer only sees profile DIDs so it can't tell. Uniqueness here still depends
///      on the issuer allowing one credential of the schema per person. For that reason
///      `maxKeysPerHuman` is a setting and not fixed at 1. The DAO should set it to
///      whatever Redbelly will commit to in writing.
contract ReceptorNullifierAdapter is IPersonhoodAdapter, Ownable2Step {
    IGroth16Verifier public verifier;

    /// @notice Pinned public inputs. Both must be non-zero, otherwise the circuit outputs
    ///         a zero nullifier.
    uint256 public verifierId;
    uint256 public nullifierSessionId;

    /// @notice Position of `nullifier` in the circuit's public signals.
    uint256 public nullifierIndex;
    /// @notice Positions of `verifierID` and `nullifierSessionID`, so they can be pinned.
    uint256 public verifierIdIndex;
    uint256 public sessionIdIndex;
    /// @notice Expected `issuerID` public signal and its position. Pins the issuer.
    uint256 public expectedIssuerId;
    uint256 public issuerIdIndex;

    uint32 private _maxKeysPerHuman = type(uint32).max; // no guarantee until the DAO sets one
    uint16 private _assurance;
    bool public enabled;

    event Configured(address verifier, uint256 verifierId, uint256 sessionId, uint256 issuerId);
    event EnabledSet(bool enabled);
    event BoundsSet(uint32 maxKeysPerHuman, uint16 assurance);

    error NotEnabled();
    error BadProof();
    error ZeroNullifier();
    error PinnedInputMismatch(uint256 index, uint256 got, uint256 want);
    error SignalsTooShort(uint256 len);

    constructor(address owner_) Ownable(owner_) {}

    function configure(
        address verifier_,
        uint256 verifierId_,
        uint256 nullifierSessionId_,
        uint256 expectedIssuerId_,
        uint256 nullifierIndex_,
        uint256 verifierIdIndex_,
        uint256 sessionIdIndex_,
        uint256 issuerIdIndex_
    ) external onlyOwner {
        verifier = IGroth16Verifier(verifier_);
        verifierId = verifierId_;
        nullifierSessionId = nullifierSessionId_;
        expectedIssuerId = expectedIssuerId_;
        nullifierIndex = nullifierIndex_;
        verifierIdIndex = verifierIdIndex_;
        sessionIdIndex = sessionIdIndex_;
        issuerIdIndex = issuerIdIndex_;
        emit Configured(verifier_, verifierId_, nullifierSessionId_, expectedIssuerId_);
    }

    /// @dev Only set this to a number Redbelly has committed to in writing. Left at
    ///      type(uint32).max, the registry reports that there is no uniqueness guarantee.
    function setBounds(uint32 maxKeysPerHuman_, uint16 assurance_) external onlyOwner {
        _maxKeysPerHuman = maxKeysPerHuman_;
        _assurance = assurance_;
        emit BoundsSet(maxKeysPerHuman_, assurance_);
    }

    function setEnabled(bool enabled_) external onlyOwner {
        enabled = enabled_;
        emit EnabledSet(enabled_);
    }

    function adapterId() external pure returns (bytes32) {
        return keccak256("adapter.receptor.nullifier.v3");
    }

    function maxKeysPerHuman() external view returns (uint32) {
        return enabled ? _maxKeysPerHuman : type(uint32).max;
    }

    function assurance() external view returns (uint16) {
        return enabled ? _assurance : 0;
    }

    /// @param evidence abi.encode(uint256[2] a, uint256[2][2] b, uint256[2] c, uint256[] pubSignals)
    /// @dev `subject` is unused on purpose. The nullifier comes from the person's genesis
    ///      identity, so they get the same key from any of their wallets.
    function verify(address, bytes calldata evidence) external view returns (bytes32) {
        if (!enabled) revert NotEnabled();

        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[] memory pub) =
            abi.decode(evidence, (uint256[2], uint256[2][2], uint256[2], uint256[]));

        uint256 maxIndex = _max4(nullifierIndex, verifierIdIndex, sessionIdIndex, issuerIdIndex);
        if (pub.length <= maxIndex) revert SignalsTooShort(pub.length);

        // Check the pinned inputs before the proof, so a valid proof made for another
        // session or another issuer can't be replayed here.
        if (pub[verifierIdIndex] != verifierId) {
            revert PinnedInputMismatch(verifierIdIndex, pub[verifierIdIndex], verifierId);
        }
        if (pub[sessionIdIndex] != nullifierSessionId) {
            revert PinnedInputMismatch(sessionIdIndex, pub[sessionIdIndex], nullifierSessionId);
        }
        if (pub[issuerIdIndex] != expectedIssuerId) {
            revert PinnedInputMismatch(issuerIdIndex, pub[issuerIdIndex], expectedIssuerId);
        }

        if (!verifier.verifyProof(a, b, c, pub)) revert BadProof();

        uint256 nullifier = pub[nullifierIndex];
        if (nullifier == 0) revert ZeroNullifier(); // the circuit outputs 0 when inputs are unset
        return bytes32(nullifier);
    }

    function _max4(uint256 w, uint256 x, uint256 y, uint256 z) private pure returns (uint256 m) {
        m = w;
        if (x > m) m = x;
        if (y > m) m = y;
        if (z > m) m = z;
    }
}
