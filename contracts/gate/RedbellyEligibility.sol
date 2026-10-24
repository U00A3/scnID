// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IBootstrapContractsRegistry, IRedbellyPermission, IPermissionExtender} from "../interfaces/IRedbelly.sol";

/// @title RedbellyEligibility
/// @notice Wrapper over Redbelly's Permission contract.
///
/// @dev This tells you that an address belongs to some KYC-verified person or business.
///      It cannot tell you which one. Two addresses that both pass may belong to the same
///      person and nothing on chain can show it.
///
///      So this is an eligibility check and should never be used as a uniqueness check.
///      One person can hold several permissioned addresses (Redbelly reports the limit as
///      10 per identity). Anything that needs one vote per person has to go through
///      PersonhoodRegistry.
contract RedbellyEligibility {
    /// @notice Redbelly's bootstrap registry. Same address on chain 151 and 153.
    IBootstrapContractsRegistry public immutable registry;

    /// @notice Whether a PermissionExtender listing means "this is a business".
    ///
    /// @dev True on mainnet. On testnet the extender is used as a general admin grant,
    ///      so most testnet senders we sampled were permissioned through it (8 of 11 on
    ///      2026-09-03, and the testnet Permission contract had no `request()` calls at
    ///      all). Treating those as businesses would shut them out of the person chamber
    ///      and nobody could test it on testnet.
    ///
    ///      Immutable and public so anyone can see which policy a deployment uses. Only
    ///      set it to false on testnet. On mainnet that would let a KYB business register
    ///      as a person, and companies are cheap to set up.
    bool public immutable treatExtenderAsBusiness;

    /// @notice Registry key under which the Permission contract is published.
    string internal constant PERMISSION_KEY = "permission";

    /// @notice Limit on extenders checked in one call, so a long extender list cannot
    ///         make eligibility checks run out of gas.
    uint256 public constant MAX_EXTENDERS = 32;

    error RegistryLookupFailed();

    event EligibilityPolicy(address registry, bool treatExtenderAsBusiness);

    constructor(address registry_, bool treatExtenderAsBusiness_) {
        if (registry_ == address(0)) revert RegistryLookupFailed();
        registry = IBootstrapContractsRegistry(registry_);
        treatExtenderAsBusiness = treatExtenderAsBusiness_;
        emit EligibilityPolicy(registry_, treatExtenderAsBusiness_);
    }

    /// @notice The current Permission contract, looked up in the registry on every call.
    /// @dev Not cached, since Redbelly can point the registry entry somewhere new.
    function permission() public view returns (IRedbellyPermission) {
        address p = registry.getContractAddress(PERMISSION_KEY);
        if (p == address(0)) revert RegistryLookupFailed();
        return IRedbellyPermission(p);
    }

    /// @notice True if `account` is permissioned on Redbelly at all (KYC or KYB).
    function isPermissioned(address account) public view returns (bool) {
        return permission().isAllowed(account);
    }

    /// @notice True if `account` is permissioned through a PermissionExtender (a business).
    function isBusiness(address account) public view returns (bool) {
        address[] memory extenders = permission().getPermissionExtenders();
        uint256 n = extenders.length;
        if (n > MAX_EXTENDERS) n = MAX_EXTENDERS;
        for (uint256 i = 0; i < n; ++i) {
            // If an extender reverts or has no code we count it as "not allowed" so one
            // bad extender can't break the whole check.
            (bool ok, bytes memory ret) =
                extenders[i].staticcall(abi.encodeCall(IPermissionExtender.isAllowed, (account)));
            if (ok && ret.length >= 32 && abi.decode(ret, (bool))) return true;
        }
        return false;
    }

    /// @notice True if `account` is a verified individual: permissioned and not a business.
    /// @dev This is the population the person chamber is built on. Businesses are left
    ///      out. When `treatExtenderAsBusiness` is false (testnet) the business check is
    ///      skipped and this is the same as `isPermissioned`.
    function isVerifiedIndividual(address account) external view returns (bool) {
        if (!isPermissioned(account)) return false;
        if (!treatExtenderAsBusiness) return true;
        return !isBusiness(account);
    }
}
