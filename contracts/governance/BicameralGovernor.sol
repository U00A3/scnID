// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PersonhoodRegistry} from "../personhood/PersonhoodRegistry.sol";
import {StakeVault} from "../weight/StakeVault.sol";
import {RedbellyEligibility} from "../gate/RedbellyEligibility.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title BicameralGovernor
/// @notice A proposal passes only if it carries both chambers: linear stake and
///         registered persons.
///
/// @dev One person on Redbelly can hold up to about 10 KYC'd wallets, and nothing on
///      chain shows which wallets share an owner. That leaves two kinds of voting rule,
///      and each fails in its own way.
///
///        Linear stake. Splitting X across n wallets still gives X, so splitting gains
///        nothing. It favours large holders, though, which is why the DAO looked at
///        quadratic voting in March 2026.
///
///        One person, one vote. Equal, but anyone who splits gets about 10 votes unless
///        something off chain vouches that each voter is a different person.
///        PersonhoodRegistry does that, and it rests on trust.
///
///      Requiring both means an attacker has to win both. Extra wallets add nothing in
///      the stake chamber and money adds nothing in the person chamber, so taking over
///      the DAO needs real capital and real people together. This limits the damage from
///      either weakness. It does not remove sybil risk, and the registry's
///      `sybilBound()` shows how much trust the person chamber relies on.
contract BicameralGovernor is Ownable2Step, ReentrancyGuard {
    // types

    enum Support { Against, For, Abstain }

    enum State { Pending, Active, Defeated, Succeeded, Queued, Executed, Canceled }

    struct Thresholds {
        uint16 stakeQuorumBps; // of total staked at snapshot
        uint16 stakeApprovalBps; // of (For + Against)
        uint16 personQuorumBps; // of registrations live at snapshot
        uint16 personApprovalBps; // of (For + Against)
    }

    struct Tally {
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
    }

    struct Proposal {
        address proposer;
        uint48 snapshotBlock;
        uint64 createdAt;
        uint64 voteStart;
        uint64 voteEnd;
        uint64 eta; // timelock expiry, set when queued
        uint256 totalStakeAtSnapshot;
        uint256 registrationsAtSnapshot;
        Thresholds thresholds;
        Tally stake;
        Tally person;
        bool executed;
        bool canceled;
        bytes32 actionsHash;
    }

    // storage

    RedbellyEligibility public immutable eligibility;
    PersonhoodRegistry public immutable registry;
    StakeVault public immutable vault;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) private _proposals;

    /// @dev Stake chamber double vote guard, keyed by address. Splitting stake across
    ///      addresses does no harm here because weight adds up linearly.
    mapping(uint256 => mapping(address => bool)) public hasVotedStake;
    /// @dev Person chamber double vote guard, keyed by person and not by address, so
    ///      moving a registration to a new wallet doesn't give a second vote.
    mapping(uint256 => mapping(bytes32 => bool)) public hasVotedPerson;

    uint64 public votingDelay = 1 days;
    uint64 public votingPeriod = 5 days;
    uint64 public timelockDelay = 2 days;
    uint256 public proposalThresholdStake;
    Thresholds public defaultThresholds;

    // events

    event ProposalCreated(
        uint256 indexed id, address indexed proposer, uint48 snapshotBlock,
        uint64 voteStart, uint64 voteEnd, bytes32 actionsHash, string description
    );
    event StakeVoteCast(uint256 indexed id, address indexed voter, Support support, uint256 weight);
    event PersonVoteCast(uint256 indexed id, bytes32 indexed person, Support support);
    event ProposalQueued(uint256 indexed id, uint64 eta);
    event ProposalExecuted(uint256 indexed id);
    event ProposalCanceled(uint256 indexed id);
    event GovernanceParamsSet(uint64 votingDelay, uint64 votingPeriod, uint64 timelockDelay, uint256 proposalThresholdStake);
    event DefaultThresholdsSet(Thresholds thresholds);

    // errors

    error NotEligible(address account);
    error BelowProposalThreshold(uint256 have, uint256 need);
    error NotRegisteredPerson(address account);
    error ProposalNotActive(uint256 id, State state);
    error AlreadyVoted();
    error NoWeight();
    error RegisteredTooLate();
    error WrongState(uint256 id, State have, State want);
    error TimelockNotElapsed(uint64 eta);
    error ActionsMismatch();
    error ExecutionFailed(uint256 index);
    error BadThresholds();
    error EmptyActions();
    error LengthMismatch();

    constructor(
        address eligibility_,
        address registry_,
        address vault_,
        address owner_,
        Thresholds memory defaults_
    ) Ownable(owner_) {
        eligibility = RedbellyEligibility(eligibility_);
        registry = PersonhoodRegistry(registry_);
        vault = StakeVault(vault_);
        _validate(defaults_);
        defaultThresholds = defaults_;
    }

    // admin

    function setGovernanceParams(
        uint64 votingDelay_,
        uint64 votingPeriod_,
        uint64 timelockDelay_,
        uint256 proposalThresholdStake_
    ) external onlyOwner {
        votingDelay = votingDelay_;
        votingPeriod = votingPeriod_;
        timelockDelay = timelockDelay_;
        proposalThresholdStake = proposalThresholdStake_;
        emit GovernanceParamsSet(votingDelay_, votingPeriod_, timelockDelay_, proposalThresholdStake_);
    }

    function setDefaultThresholds(Thresholds calldata t) external onlyOwner {
        _validate(t);
        defaultThresholds = t;
        emit DefaultThresholdsSet(t);
    }

    function _validate(Thresholds memory t) internal pure {
        if (
            t.stakeQuorumBps > 10000 || t.stakeApprovalBps > 10000
                || t.personQuorumBps > 10000 || t.personApprovalBps > 10000
        ) revert BadThresholds();
        // Approval at or below half would let a minority pass proposals, so we reject it.
        if (t.stakeApprovalBps <= 5000 || t.personApprovalBps <= 5000) revert BadThresholds();
    }

    // proposing

    /// @notice Create a proposal. The caller must be a registered person and hold stake.
    /// @dev With only a stake requirement a large holder could spam proposals, and with
    ///      only registration a set of fake persons could. Needing both means spam costs
    ///      money and puts a revocable registration at risk.
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string calldata description
    ) external returns (uint256 id) {
        if (targets.length == 0) revert EmptyActions();
        if (targets.length != values.length || targets.length != calldatas.length) revert LengthMismatch();
        if (!eligibility.isVerifiedIndividual(msg.sender)) revert NotEligible(msg.sender);
        if (!registry.isActiveVoter(msg.sender)) revert NotRegisteredPerson(msg.sender);

        uint256 stake = vault.stakeOf(msg.sender);
        if (stake < proposalThresholdStake) revert BelowProposalThreshold(stake, proposalThresholdStake);

        id = ++proposalCount;
        uint48 snapshotBlock = uint48(block.number - 1); // previous block, can't be changed by this tx
        uint64 start = uint64(block.timestamp) + votingDelay;

        Proposal storage p = _proposals[id];
        p.proposer = msg.sender;
        p.snapshotBlock = snapshotBlock;
        p.createdAt = uint64(block.timestamp);
        p.voteStart = start;
        p.voteEnd = start + votingPeriod;
        p.thresholds = defaultThresholds;
        p.totalStakeAtSnapshot = vault.getPastTotalStake(snapshotBlock);
        p.registrationsAtSnapshot = registry.activeRegistrations();
        p.actionsHash = keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description))));

        emit ProposalCreated(id, msg.sender, snapshotBlock, start, p.voteEnd, p.actionsHash, description);
    }

    // voting

    /// @notice Vote in the stake chamber. Weight is escrowed RBNT at the snapshot block.
    /// @dev Ten wallets voting with a tenth each add up to the same weight as one wallet
    ///      voting with the whole amount, so this chamber doesn't need to know who anyone is.
    function castStakeVote(uint256 id, Support support) external {
        Proposal storage p = _proposals[id];
        State s = state(id);
        if (s != State.Active) revert ProposalNotActive(id, s);
        if (hasVotedStake[id][msg.sender]) revert AlreadyVoted();
        if (!eligibility.isPermissioned(msg.sender)) revert NotEligible(msg.sender);

        uint256 weight = vault.getPastStake(msg.sender, p.snapshotBlock);
        if (weight == 0) revert NoWeight();

        hasVotedStake[id][msg.sender] = true;
        _add(p.stake, support, weight);
        emit StakeVoteCast(id, msg.sender, support, weight);
    }

    /// @notice Vote in the person chamber. One vote per registered person.
    /// @dev Tracked by person key and not by address, and the registration has to be
    ///      older than the proposal. Registering after a proposal appears, or moving a
    ///      registration to a new wallet during the vote, gives no extra vote.
    function castPersonVote(uint256 id, Support support) external {
        Proposal storage p = _proposals[id];
        State s = state(id);
        if (s != State.Active) revert ProposalNotActive(id, s);
        if (!registry.isActiveVoter(msg.sender)) revert NotRegisteredPerson(msg.sender);

        bytes32 person = registry.personOf(msg.sender);
        if (hasVotedPerson[id][person]) revert AlreadyVoted();

        PersonhoodRegistry.Registration memory r = registry.registrationOf(person);
        if (r.registeredAt >= p.createdAt) revert RegisteredTooLate();

        hasVotedPerson[id][person] = true;
        _add(p.person, support, 1);
        emit PersonVoteCast(id, person, support);
    }

    function _add(Tally storage t, Support support, uint256 weight) private {
        if (support == Support.For) t.forVotes += weight;
        else if (support == Support.Against) t.againstVotes += weight;
        else t.abstainVotes += weight;
    }

    // outcome

    function _chamberPasses(Tally storage t, uint256 denominator, uint16 quorumBps, uint16 approvalBps)
        private
        view
        returns (bool)
    {
        uint256 turnout = t.forVotes + t.againstVotes + t.abstainVotes;
        // Quorum is measured against the chamber's own electorate (total stake or live
        // registrations) and never against a count of addresses.
        if (turnout * 10000 < denominator * quorumBps) return false;
        uint256 decisive = t.forVotes + t.againstVotes;
        if (decisive == 0) return false;
        return t.forVotes * 10000 >= decisive * approvalBps;
    }

    function stakeChamberPasses(uint256 id) public view returns (bool) {
        Proposal storage p = _proposals[id];
        return _chamberPasses(p.stake, p.totalStakeAtSnapshot, p.thresholds.stakeQuorumBps, p.thresholds.stakeApprovalBps);
    }

    function personChamberPasses(uint256 id) public view returns (bool) {
        Proposal storage p = _proposals[id];
        return _chamberPasses(p.person, p.registrationsAtSnapshot, p.thresholds.personQuorumBps, p.thresholds.personApprovalBps);
    }

    function state(uint256 id) public view returns (State) {
        Proposal storage p = _proposals[id];
        if (p.proposer == address(0)) revert WrongState(id, State.Pending, State.Pending);
        if (p.canceled) return State.Canceled;
        if (p.executed) return State.Executed;
        if (block.timestamp < p.voteStart) return State.Pending;
        if (block.timestamp <= p.voteEnd) return State.Active;
        // Both chambers have to pass.
        if (!(stakeChamberPasses(id) && personChamberPasses(id))) return State.Defeated;
        if (p.eta == 0) return State.Succeeded;
        return State.Queued;
    }

    function queue(uint256 id) external {
        State s = state(id);
        if (s != State.Succeeded) revert WrongState(id, s, State.Succeeded);
        Proposal storage p = _proposals[id];
        p.eta = uint64(block.timestamp) + timelockDelay;
        emit ProposalQueued(id, p.eta);
    }

    function execute(
        uint256 id,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string calldata description
    ) external payable nonReentrant {
        State s = state(id);
        if (s != State.Queued) revert WrongState(id, s, State.Queued);
        Proposal storage p = _proposals[id];
        if (block.timestamp < p.eta) revert TimelockNotElapsed(p.eta);
        if (keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))) != p.actionsHash) {
            revert ActionsMismatch();
        }

        p.executed = true; // set before the calls so a reentrant call can't execute it again
        for (uint256 i = 0; i < targets.length; ++i) {
            (bool ok,) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!ok) revert ExecutionFailed(i);
        }
        emit ProposalExecuted(id);
    }

    function cancel(uint256 id) external {
        Proposal storage p = _proposals[id];
        if (msg.sender != p.proposer && msg.sender != owner()) revert NotEligible(msg.sender);
        State s = state(id);
        if (s == State.Executed || s == State.Canceled) revert WrongState(id, s, State.Pending);
        p.canceled = true;
        emit ProposalCanceled(id);
    }

    // views

    function proposals(uint256 id) external view returns (Proposal memory) {
        return _proposals[id];
    }

    receive() external payable {}
}
