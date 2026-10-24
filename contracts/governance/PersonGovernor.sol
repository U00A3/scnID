// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PersonhoodRegistry} from "../personhood/PersonhoodRegistry.sol";
import {RedbellyEligibility} from "../gate/RedbellyEligibility.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title PersonGovernor
/// @notice SCNID v0: person-chamber-only governance. Officer/owner proposes; registered
///         persons vote on-chain (1 person = 1 ballot). Stake chamber arrives in Phase 3.
/// @dev Tallies are always public on-chain. UI may hide them until voteEnd (soft Hidden).
///      True sealed voting needs commit-reveal - see docs/SEALED-VOTING.md.
contract PersonGovernor is Ownable2Step {
    enum Support {
        Against,
        For,
        Abstain
    }

    enum State {
        Pending,
        Active,
        Defeated,
        Succeeded,
        Canceled
    }

    struct Tally {
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
    }

    struct Proposal {
        address proposer;
        uint64 createdAt;
        uint64 voteStart;
        uint64 voteEnd;
        uint256 registrationsAtSnapshot;
        uint16 quorumBps;
        uint16 approvalBps;
        Tally person;
        bool canceled;
        string description;
    }

    RedbellyEligibility public immutable eligibility;
    PersonhoodRegistry public immutable registry;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) private _proposals;
    mapping(uint256 => mapping(bytes32 => bool)) public hasVotedPerson;

    uint64 public votingDelay = 1 minutes;
    uint64 public votingPeriod = 1 hours;
    uint16 public defaultQuorumBps = 1000; // 10% of registrations
    uint16 public defaultApprovalBps = 5001; // >50%

    event ProposalCreated(
        uint256 indexed id, address indexed proposer, uint64 voteStart, uint64 voteEnd, string description
    );
    event PersonVoteCast(uint256 indexed id, bytes32 indexed person, address indexed voter, Support support);
    event ProposalCanceled(uint256 indexed id);
    event GovernanceParamsSet(uint64 votingDelay, uint64 votingPeriod, uint16 quorumBps, uint16 approvalBps);

    error NotEligible(address account);
    error NotRegisteredPerson(address account);
    error ProposalNotActive(uint256 id, State state);
    error AlreadyVoted();
    error RegisteredTooLate();
    error WrongState(uint256 id, State have, State want);
    error BadThresholds();
    error EmptyDescription();

    constructor(address eligibility_, address registry_, address owner_) Ownable(owner_) {
        eligibility = RedbellyEligibility(eligibility_);
        registry = PersonhoodRegistry(registry_);
    }

    function setGovernanceParams(uint64 votingDelay_, uint64 votingPeriod_, uint16 quorumBps_, uint16 approvalBps_)
        external
        onlyOwner
    {
        if (quorumBps_ > 10000 || approvalBps_ > 10000 || approvalBps_ <= 5000) revert BadThresholds();
        votingDelay = votingDelay_;
        votingPeriod = votingPeriod_;
        defaultQuorumBps = quorumBps_;
        defaultApprovalBps = approvalBps_;
        emit GovernanceParamsSet(votingDelay_, votingPeriod_, quorumBps_, approvalBps_);
    }

    /// @notice Owner/officer creates a signalling proposal (no on-chain execution payload in v0).
    function propose(string calldata description) external returns (uint256 id) {
        if (bytes(description).length == 0) revert EmptyDescription();
        if (!eligibility.isVerifiedIndividual(msg.sender)) revert NotEligible(msg.sender);
        // Officer path: owner may propose without being a registered person; others must be.
        if (msg.sender != owner() && !registry.isActiveVoter(msg.sender)) {
            revert NotRegisteredPerson(msg.sender);
        }

        id = ++proposalCount;
        uint64 start = uint64(block.timestamp) + votingDelay;
        Proposal storage p = _proposals[id];
        p.proposer = msg.sender;
        p.createdAt = uint64(block.timestamp);
        p.voteStart = start;
        p.voteEnd = start + votingPeriod;
        p.registrationsAtSnapshot = registry.activeRegistrations();
        p.quorumBps = defaultQuorumBps;
        p.approvalBps = defaultApprovalBps;
        p.description = description;

        emit ProposalCreated(id, msg.sender, start, p.voteEnd, description);
    }

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
        if (support == Support.For) p.person.forVotes += 1;
        else if (support == Support.Against) p.person.againstVotes += 1;
        else p.person.abstainVotes += 1;

        emit PersonVoteCast(id, person, msg.sender, support);
    }

    /// @notice Proposer or owner ends a Pending/Active vote.
    /// @dev Same class of escape hatch as OZ Governor / Compound guardian cancel - see docs/VISION.md.
    function cancel(uint256 id) external {
        Proposal storage p = _proposals[id];
        if (msg.sender != p.proposer && msg.sender != owner()) revert NotEligible(msg.sender);
        State s = state(id);
        if (s == State.Succeeded || s == State.Defeated || s == State.Canceled) {
            revert WrongState(id, s, State.Pending);
        }
        p.canceled = true;
        emit ProposalCanceled(id);
    }

    function personChamberPasses(uint256 id) public view returns (bool) {
        Proposal storage p = _proposals[id];
        uint256 turnout = p.person.forVotes + p.person.againstVotes + p.person.abstainVotes;
        uint256 denom = p.registrationsAtSnapshot;
        if (denom == 0) return false;
        if (turnout * 10000 < denom * p.quorumBps) return false;
        uint256 decisive = p.person.forVotes + p.person.againstVotes;
        if (decisive == 0) return false;
        return p.person.forVotes * 10000 >= decisive * p.approvalBps;
    }

    function state(uint256 id) public view returns (State) {
        Proposal storage p = _proposals[id];
        if (p.proposer == address(0)) revert WrongState(id, State.Pending, State.Pending);
        if (p.canceled) return State.Canceled;
        if (block.timestamp < p.voteStart) return State.Pending;
        if (block.timestamp <= p.voteEnd) return State.Active;
        return personChamberPasses(id) ? State.Succeeded : State.Defeated;
    }

    function proposals(uint256 id) external view returns (Proposal memory) {
        return _proposals[id];
    }
}
