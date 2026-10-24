// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Stand-in for Redbelly's Permission contract.
/// @dev Like the real contract it has no way to ask which addresses share an owner.
///      If the mock had one, tests could pass using something the live chain doesn't
///      offer.
contract MockPermission {
    mapping(address => bool) public allowed;
    address[] private _extenders;
    bool public enabled = true;

    function setAllowed(address a, bool v) external {
        allowed[a] = v;
    }

    function setExtenders(address[] calldata e) external {
        delete _extenders;
        for (uint256 i = 0; i < e.length; ++i) _extenders.push(e[i]);
    }

    function isAllowed(address a) external view returns (bool) {
        return allowed[a];
    }

    function getPermissionExtenders() external view returns (address[] memory) {
        return _extenders;
    }

    function isPermissionedAccessEnabled() external view returns (bool) {
        return enabled;
    }
}

contract MockExtender {
    mapping(address => bool) public allowed;

    function setAllowed(address a, bool v) external {
        allowed[a] = v;
    }

    function isAllowed(address a) external view returns (bool) {
        return allowed[a];
    }
}

contract MockBootstrapRegistry {
    mapping(string => address) private _reg;

    function register(string calldata name, address c) external {
        _reg[name] = c;
    }

    function getContractAddress(string calldata name) external view returns (address) {
        return _reg[name];
    }
}

/// @notice An extender that always reverts, used to check eligibility still works.
contract RevertingExtender {
    function isAllowed(address) external pure returns (bool) {
        revert("nope");
    }
}

contract Receiver {
    uint256 public pokes;

    function poke() external {
        pokes += 1;
    }

    receive() external payable {}
}
