// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPersonhoodAdapter} from "../../interfaces/IPersonhoodAdapter.sol";

/// @title MockPersonhoodAdapter
/// @notice POV Join without attestors. Person key = keccak256(subject) on empty evidence,
///         or an explicit bytes32 embedded in evidence for scripted demos.
///
/// @dev Sybil bound is unbounded: one Join per wallet yields one person. Use only for
///      local/testnet POV. Swap to Attested or Nullifier for stronger uniqueness.
contract MockPersonhoodAdapter is IPersonhoodAdapter {
    function adapterId() external pure returns (bytes32) {
        return keccak256("adapter.mock.scnid.v1");
    }

    function maxKeysPerHuman() external pure returns (uint32) {
        return type(uint32).max;
    }

    function assurance() external pure returns (uint16) {
        return 0;
    }

    /// @param evidence empty -> key from subject; or abi.encode(bytes32 customKey)
    function verify(address subject, bytes calldata evidence) external pure returns (bytes32) {
        if (evidence.length == 0) {
            return keccak256(abi.encodePacked("scnid.mock", subject));
        }
        if (evidence.length == 32) {
            return bytes32(evidence);
        }
        return abi.decode(evidence, (bytes32));
    }
}
