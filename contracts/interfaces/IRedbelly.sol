// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Redbelly's on-chain contract name registry.
/// @dev Deployed at 0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5 on both chain 151 and
///      chain 153. We look up "permission" here instead of hardcoding the Permission
///      address, because Permission is an ERC-1967 proxy and the registry entry is the
///      pointer Redbelly maintains.
interface IBootstrapContractsRegistry {
    function getContractAddress(string calldata contractName) external view returns (address);
}

/// @notice The part of Redbelly's PermissionUpgradeable that this project uses.
/// @dev `isAllowed` is the only per-address query the contract offers. There is no
///      function that returns an identity or lists the addresses that belong to one, so
///      a single yes/no bit per address is all a contract on Redbelly can learn.
interface IRedbellyPermission {
    function isAllowed(address _address) external view returns (bool);
    function getPermissionExtenders() external view returns (address[] memory);
    function isPermissionedAccessEnabled() external view returns (bool);
}

/// @notice Permission extenders mark business (KYB) users rather than individuals (KYC).
/// @dev An address allowed by Permission and by an extender is a business. Allowed by
///      Permission alone means an individual. Redbelly's own permission validation
///      service uses the same rule.
interface IPermissionExtender {
    function isAllowed(address _address) external view returns (bool);
}
