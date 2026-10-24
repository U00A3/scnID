// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IPersonhoodAdapter
/// @notice A source of evidence that an address belongs to a distinct person.
///
/// @dev An adapter turns some piece of evidence into a `personKey`. The key should be the
///      same every time the same person registers, from any wallet, and different for
///      different people. It does not say who the person is.
///
///      Each adapter publishes two numbers:
///
///        maxKeysPerHuman()  How many different keys one person can get from this
///                           adapter. 1 means one key per person. A higher number is
///                           the adapter's sybil bound and feeds straight into the
///                           governance bound.
///        assurance()        0 to 10000, how far the DAO should trust that number.
///
///      An adapter that cannot give a real bound should return `type(uint32).max`, which
///      tells the registry not to rely on it for uniqueness.
interface IPersonhoodAdapter {
    /// @notice Stable identifier for this adapter, used to namespace its keys.
    function adapterId() external view returns (bytes32);

    /// @notice Upper bound on distinct personKeys a single person can obtain here.
    /// @dev 1 means one key per person. type(uint32).max means no guarantee.
    function maxKeysPerHuman() external view returns (uint32);

    /// @notice Confidence in the maxKeysPerHuman figure, in basis points (0 to 10000).
    function assurance() external view returns (uint16);

    /// @notice Check `evidence` presented by `subject` and return their person key.
    /// @dev Must revert on invalid evidence. The key has to depend on the person and not
    ///      on `subject`, otherwise the same person could register again from a second
    ///      wallet. Not a view function because some adapters may consume one-time
    ///      evidence.
    /// @return personKey stable per person, not namespaced (the registry does that)
    function verify(address subject, bytes calldata evidence) external returns (bytes32 personKey);
}
