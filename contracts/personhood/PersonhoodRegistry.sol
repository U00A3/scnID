// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPersonhoodAdapter} from "../interfaces/IPersonhoodAdapter.sol";
import {RedbellyEligibility} from "../gate/RedbellyEligibility.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title PersonhoodRegistry
/// @notice One registration per person. SCNID adds multi-wallet link (Lab UX) on top of
///         the SCN registry pattern (adapter-gated person keys, rebind, corroborators).
///
/// @dev Adapted from Njaybby/scn-governance PersonhoodRegistry (MIT).
contract PersonhoodRegistry is Ownable2Step {
    struct Registration {
        address voter; // primary wallet
        uint64 registeredAt;
        uint64 expiresAt; // 0 = never
        uint16 assurance;
        bytes32 adapterId;
        bool revoked;
    }

    RedbellyEligibility public immutable eligibility;

    mapping(bytes32 => Registration) private _byPerson;
    mapping(address => bytes32) public personOf;
    mapping(bytes32 => address[]) private _wallets;

    IPersonhoodAdapter public primaryAdapter;
    mapping(address => bool) public isCorroborator;

    uint64 public registrationTtl;
    uint64 public rebindDelay = 3 days;
    mapping(bytes32 => uint64) public rebindReadyAt;
    mapping(bytes32 => address) public pendingVoter;

    /// @notice Primary offered `wallet` a link under their person (two-step link).
    mapping(bytes32 => address) public linkOffer;

    uint64 public unlinkCooldown = 1 days;
    mapping(address => uint64) public unlinkReadyAt;

    uint256 public activeRegistrations;

    event PrimaryAdapterSet(address indexed adapter, bytes32 adapterId, uint32 maxKeysPerHuman);
    event CorroboratorSet(address indexed adapter, bool enabled);
    event Registered(bytes32 indexed person, address indexed voter, bytes32 adapterId, uint16 assurance);
    event LinkOffered(bytes32 indexed person, address indexed wallet);
    event WalletLinked(bytes32 indexed person, address indexed wallet);
    event WalletUnlinked(bytes32 indexed person, address indexed wallet);
    event RebindRequested(bytes32 indexed person, address indexed newVoter, uint64 readyAt);
    event Rebound(bytes32 indexed person, address indexed oldVoter, address indexed newVoter);
    event Revoked(bytes32 indexed person, string reason);
    event AssuranceRaised(bytes32 indexed person, uint16 from, uint16 to, bytes32 byAdapter);
    event RegistrationTtlSet(uint64 ttl);
    event RebindDelaySet(uint64 delaySeconds);
    event UnlinkCooldownSet(uint64 delaySeconds);

    error NoPrimaryAdapter();
    error NotEligible(address account);
    error AlreadyRegistered(bytes32 person);
    error AddressAlreadyBound(address voter);
    error NotRegistered(bytes32 person);
    error RegistrationInactive(bytes32 person);
    error NotCorroborator(address adapter);
    error NothingPending(bytes32 person);
    error RebindNotReady(uint64 readyAt);
    error AssuranceNotHigher();
    error ZeroKey();
    error NotPrimary();
    error BadLinkOffer(address want);
    error CannotUnlinkPrimary();
    error UnlinkNotReady(uint64 readyAt);
    error NotBoundToPerson();

    constructor(address eligibility_, address owner_) Ownable(owner_) {
        eligibility = RedbellyEligibility(eligibility_);
    }

    function setPrimaryAdapter(address adapter) external onlyOwner {
        primaryAdapter = IPersonhoodAdapter(adapter);
        emit PrimaryAdapterSet(
            adapter, IPersonhoodAdapter(adapter).adapterId(), IPersonhoodAdapter(adapter).maxKeysPerHuman()
        );
    }

    function setCorroborator(address adapter, bool enabled) external onlyOwner {
        isCorroborator[adapter] = enabled;
        emit CorroboratorSet(adapter, enabled);
    }

    function setRegistrationTtl(uint64 ttl) external onlyOwner {
        registrationTtl = ttl;
        emit RegistrationTtlSet(ttl);
    }

    function setRebindDelay(uint64 delaySeconds) external onlyOwner {
        rebindDelay = delaySeconds;
        emit RebindDelaySet(delaySeconds);
    }

    function setUnlinkCooldown(uint64 delaySeconds) external onlyOwner {
        unlinkCooldown = delaySeconds;
        emit UnlinkCooldownSet(delaySeconds);
    }

    function revoke(bytes32 person, string calldata reason) external onlyOwner {
        Registration storage r = _byPerson[person];
        if (r.voter == address(0)) revert NotRegistered(person);
        if (_isActive(r)) {
            unchecked {
                activeRegistrations -= 1;
            }
        }
        r.revoked = true;
        address[] storage ws = _wallets[person];
        for (uint256 i = 0; i < ws.length; ++i) {
            personOf[ws[i]] = bytes32(0);
        }
        delete _wallets[person];
        delete linkOffer[person];
        emit Revoked(person, reason);
    }

    /// @notice Join: register caller as a person via the primary adapter.
    function register(bytes calldata evidence) external returns (bytes32 person) {
        IPersonhoodAdapter adapter = primaryAdapter;
        if (address(adapter) == address(0)) revert NoPrimaryAdapter();
        if (!eligibility.isVerifiedIndividual(msg.sender)) revert NotEligible(msg.sender);
        if (personOf[msg.sender] != bytes32(0)) revert AddressAlreadyBound(msg.sender);

        bytes32 raw = adapter.verify(msg.sender, evidence);
        if (raw == bytes32(0)) revert ZeroKey();
        person = keccak256(abi.encode(adapter.adapterId(), raw));

        Registration storage r = _byPerson[person];
        if (r.voter != address(0) && !r.revoked) revert AlreadyRegistered(person);

        uint64 expires = registrationTtl == 0 ? 0 : uint64(block.timestamp) + registrationTtl;
        _byPerson[person] = Registration({
            voter: msg.sender,
            registeredAt: uint64(block.timestamp),
            expiresAt: expires,
            assurance: adapter.assurance(),
            adapterId: adapter.adapterId(),
            revoked: false
        });
        _addWallet(person, msg.sender);
        unchecked {
            activeRegistrations += 1;
        }

        emit Registered(person, msg.sender, adapter.adapterId(), adapter.assurance());
    }

    function corroborate(bytes32 person, address subject, bytes calldata evidence) external {
        if (!isCorroborator[msg.sender]) revert NotCorroborator(msg.sender);
        Registration storage r = _byPerson[person];
        if (r.voter == address(0)) revert NotRegistered(person);
        if (!_isActive(r)) revert RegistrationInactive(person);

        IPersonhoodAdapter adapter = IPersonhoodAdapter(msg.sender);
        bytes32 raw = adapter.verify(subject, evidence);
        if (raw == bytes32(0)) revert ZeroKey();

        uint16 newAssurance = adapter.assurance();
        if (newAssurance <= r.assurance) revert AssuranceNotHigher();
        uint16 old = r.assurance;
        r.assurance = newAssurance;
        emit AssuranceRaised(person, old, newAssurance, adapter.adapterId());
    }

    // ---- link (Identity-like UX) ----

    /// @notice Primary offers to attach `wallet` under this person. `wallet` must accept.
    function offerLink(address wallet) external {
        bytes32 person = personOf[msg.sender];
        if (person == bytes32(0)) revert NotRegistered(person);
        Registration storage r = _byPerson[person];
        if (!_isActive(r)) revert RegistrationInactive(person);
        if (msg.sender != r.voter) revert NotPrimary();
        if (!eligibility.isVerifiedIndividual(wallet)) revert NotEligible(wallet);
        if (personOf[wallet] != bytes32(0)) revert AddressAlreadyBound(wallet);

        linkOffer[person] = wallet;
        emit LinkOffered(person, wallet);
    }

    /// @notice Offered wallet accepts link from a known primary.
    function acceptLinkFrom(address primary) external {
        bytes32 person = personOf[primary];
        if (person == bytes32(0)) revert NotRegistered(person);
        Registration storage r = _byPerson[person];
        if (!_isActive(r)) revert RegistrationInactive(person);
        if (primary != r.voter) revert NotPrimary();
        if (linkOffer[person] != msg.sender) revert BadLinkOffer(linkOffer[person]);
        if (!eligibility.isVerifiedIndividual(msg.sender)) revert NotEligible(msg.sender);
        if (personOf[msg.sender] != bytes32(0)) revert AddressAlreadyBound(msg.sender);

        delete linkOffer[person];
        _addWallet(person, msg.sender);
        emit WalletLinked(person, msg.sender);
    }

    /// @notice Primary or the linked wallet itself unlinks a secondary address.
    function unlinkWallet(address wallet) external {
        bytes32 person = personOf[wallet];
        if (person == bytes32(0)) revert NotBoundToPerson();
        Registration storage r = _byPerson[person];
        if (!_isActive(r)) revert RegistrationInactive(person);
        if (wallet == r.voter) revert CannotUnlinkPrimary();
        if (msg.sender != r.voter && msg.sender != wallet) revert NotPrimary();

        uint64 ready = unlinkReadyAt[wallet];
        if (ready != 0 && block.timestamp < ready) revert UnlinkNotReady(ready);

        _removeWallet(person, wallet);
        unlinkReadyAt[wallet] = uint64(block.timestamp) + unlinkCooldown;
        emit WalletUnlinked(person, wallet);
    }

    // ---- rebind primary ----

    function requestRebind(address newVoter) external {
        bytes32 person = personOf[msg.sender];
        if (person == bytes32(0)) revert NotRegistered(person);
        Registration storage r = _byPerson[person];
        if (!_isActive(r)) revert RegistrationInactive(person);
        if (msg.sender != r.voter) revert NotPrimary();
        if (!eligibility.isVerifiedIndividual(newVoter)) revert NotEligible(newVoter);
        if (personOf[newVoter] != bytes32(0) && personOf[newVoter] != person) {
            revert AddressAlreadyBound(newVoter);
        }

        pendingVoter[person] = newVoter;
        uint64 ready = uint64(block.timestamp) + rebindDelay;
        rebindReadyAt[person] = ready;
        emit RebindRequested(person, newVoter, ready);
    }

    function completeRebind() external {
        bytes32 person = personOf[msg.sender];
        if (person == bytes32(0)) revert NotRegistered(person);
        Registration storage r = _byPerson[person];
        if (msg.sender != r.voter) revert NotPrimary();
        address newVoter = pendingVoter[person];
        if (newVoter == address(0)) revert NothingPending(person);
        uint64 ready = rebindReadyAt[person];
        if (block.timestamp < ready) revert RebindNotReady(ready);

        address old = r.voter;
        if (personOf[newVoter] == bytes32(0)) {
            _addWallet(person, newVoter);
        }
        r.voter = newVoter;
        // Keep old as linked secondary so history is not wiped; primary role moves.
        delete pendingVoter[person];
        delete rebindReadyAt[person];
        emit Rebound(person, old, newVoter);
    }

    // ---- views ----

    function _isActive(Registration storage r) internal view returns (bool) {
        if (r.voter == address(0) || r.revoked) return false;
        if (r.expiresAt != 0 && block.timestamp >= r.expiresAt) return false;
        return true;
    }

    function _addWallet(bytes32 person, address w) internal {
        personOf[w] = person;
        _wallets[person].push(w);
    }

    function _removeWallet(bytes32 person, address w) internal {
        personOf[w] = bytes32(0);
        address[] storage ws = _wallets[person];
        for (uint256 i = 0; i < ws.length; ++i) {
            if (ws[i] == w) {
                ws[i] = ws[ws.length - 1];
                ws.pop();
                break;
            }
        }
    }

    function registrationOf(bytes32 person) external view returns (Registration memory) {
        return _byPerson[person];
    }

    function walletsOf(bytes32 person) external view returns (address[] memory) {
        return _wallets[person];
    }

    /// @notice Any linked wallet of an active person may cast, if still permissioned.
    function isActiveVoter(address account) public view returns (bool) {
        bytes32 person = personOf[account];
        if (person == bytes32(0)) return false;
        Registration storage r = _byPerson[person];
        if (!_isActive(r)) return false;
        return eligibility.isPermissioned(account);
    }

    function personWeightOf(address account) external view returns (uint256) {
        return isActiveVoter(account) ? 1 : 0;
    }

    function sybilBound() external view returns (uint32) {
        IPersonhoodAdapter a = primaryAdapter;
        if (address(a) == address(0)) return type(uint32).max;
        return a.maxKeysPerHuman();
    }
}
