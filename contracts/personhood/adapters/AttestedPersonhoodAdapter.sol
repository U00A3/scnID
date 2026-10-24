// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPersonhoodAdapter} from "../../interfaces/IPersonhoodAdapter.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title AttestedPersonhoodAdapter
/// @notice k-of-n named attestors sign that `humanRef` is a distinct person and that
///         `subject` is their wallet.
///
/// @dev Redbelly does not currently give contracts a per-person identifier. The
///      on-chain credential only carries a wallet address, and Receptor only ships V2
///      circuits, which have no nullifier. Until that changes, "one person, one vote"
///      on Redbelly depends on people vouching for it. This adapter puts that vouching
///      on chain, signed by a quorum, where it can be seen and revoked.
///
///      This is a trusted component. The DAO sets `assurance` and it should stay well
///      below 10000. `maxKeysPerHuman` is 1 only if the attestors are honest and
///      consistent. If k attestors collude they can create as many identities as they
///      like and the code can't prevent it. What the code does give you:
///        - every attestation is on chain and tied to named signers
///        - one captured attestor is not enough, a quorum has to sign
///        - the registry rejects a second registration under the same `humanRef`
///
///      The last point only works if `humanRef` is derived the same way every time for
///      the same person, for example from the DAO member roster id or a salted hash of
///      a stable account id. If attestors make up a new ref for each wallet the adapter
///      protects nothing. The derivation rule has to be written down and published by
///      the DAO before this is used.
contract AttestedPersonhoodAdapter is IPersonhoodAdapter, EIP712, Ownable2Step {
    bytes32 public constant ATTESTATION_TYPEHASH =
        keccak256("Personhood(bytes32 humanRef,address subject,uint64 deadline)");

    mapping(address => bool) public isAttestor;
    uint256 public attestorCount;
    uint256 public threshold;
    uint16 private _assurance;

    event AttestorSet(address indexed attestor, bool enabled);
    event ThresholdSet(uint256 threshold);
    event AssuranceSet(uint16 assurance);

    error Expired(uint64 deadline);
    error NotEnoughAttestations(uint256 got, uint256 need);
    error SignaturesNotSorted();
    error NotAnAttestor(address signer);
    error ThresholdTooHigh(uint256 threshold, uint256 attestors);
    error ZeroHumanRef();

    constructor(address owner_, uint256 threshold_, uint16 assurance_)
        EIP712("RedbellyDAO-AttestedPersonhood", "1")
        Ownable(owner_)
    {
        threshold = threshold_;
        _assurance = assurance_;
    }

    // admin

    function setAttestor(address attestor, bool enabled) external onlyOwner {
        if (isAttestor[attestor] == enabled) return;
        isAttestor[attestor] = enabled;
        if (enabled) attestorCount += 1;
        else attestorCount -= 1;
        emit AttestorSet(attestor, enabled);
    }

    function setThreshold(uint256 threshold_) external onlyOwner {
        if (threshold_ == 0 || threshold_ > attestorCount) revert ThresholdTooHigh(threshold_, attestorCount);
        threshold = threshold_;
        emit ThresholdSet(threshold_);
    }

    function setAssurance(uint16 assurance_) external onlyOwner {
        _assurance = assurance_;
        emit AssuranceSet(assurance_);
    }

    // adapter

    function adapterId() external pure returns (bytes32) {
        return keccak256("adapter.attested.v1");
    }

    /// @dev 1, assuming the attestors are honest and derive humanRef the same way each
    ///      time. The registry reports this as the sybil bound.
    function maxKeysPerHuman() external pure returns (uint32) {
        return 1;
    }

    function assurance() external view returns (uint16) {
        return _assurance;
    }

    /// @param evidence abi.encode(bytes32 humanRef, uint64 deadline, bytes[] signatures)
    /// @dev Signatures must be sorted by recovered signer address, ascending. A repeated
    ///      signer would break the ordering, so k signatures always means k different
    ///      attestors.
    function verify(address subject, bytes calldata evidence) external view returns (bytes32) {
        (bytes32 humanRef, uint64 deadline, bytes[] memory signatures) =
            abi.decode(evidence, (bytes32, uint64, bytes[]));

        if (humanRef == bytes32(0)) revert ZeroHumanRef();
        if (block.timestamp > deadline) revert Expired(deadline);

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(ATTESTATION_TYPEHASH, humanRef, subject, deadline))
        );

        uint256 valid;
        address last;
        for (uint256 i = 0; i < signatures.length; ++i) {
            address signer = ECDSA.recover(digest, signatures[i]);
            if (signer <= last) revert SignaturesNotSorted();
            if (!isAttestor[signer]) revert NotAnAttestor(signer);
            last = signer;
            unchecked { ++valid; }
        }

        uint256 need = threshold;
        if (valid < need) revert NotEnoughAttestations(valid, need);

        return humanRef;
    }
}
