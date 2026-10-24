// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockPermission, MockBootstrapRegistry} from "../contracts/mocks/MockRedbelly.sol";
import {RedbellyEligibility} from "../contracts/gate/RedbellyEligibility.sol";
import {PersonhoodRegistry} from "../contracts/personhood/PersonhoodRegistry.sol";
import {MockPersonhoodAdapter} from "../contracts/personhood/adapters/MockPersonhoodAdapter.sol";
import {AttestedPersonhoodAdapter} from "../contracts/personhood/adapters/AttestedPersonhoodAdapter.sol";
import {ReceptorNullifierAdapter} from "../contracts/personhood/adapters/ReceptorNullifierAdapter.sol";
import {PersonGovernor} from "../contracts/governance/PersonGovernor.sol";
import {StakeVault} from "../contracts/weight/StakeVault.sol";
import {BicameralGovernor} from "../contracts/governance/BicameralGovernor.sol";

contract ScnidTest is Test {
    MockPermission permission;
    MockBootstrapRegistry bootstrap;
    RedbellyEligibility eligibility;
    PersonhoodRegistry registry;
    MockPersonhoodAdapter mockAdapter;
    PersonGovernor governor;

    address owner = address(this);
    address alice = makeAddr("alice");
    address alice2 = makeAddr("alice2");
    address alice3 = makeAddr("alice3");
    address bob = makeAddr("bob");

    function setUp() public {
        permission = new MockPermission();
        bootstrap = new MockBootstrapRegistry();
        bootstrap.register("permission", address(permission));
        eligibility = new RedbellyEligibility(address(bootstrap), false);
        registry = new PersonhoodRegistry(address(eligibility), owner);
        mockAdapter = new MockPersonhoodAdapter();
        registry.setPrimaryAdapter(address(mockAdapter));
        governor = new PersonGovernor(address(eligibility), address(registry), owner);

        governor.setGovernanceParams(1, 1 hours, 1000, 5001);
        registry.setUnlinkCooldown(0);

        permission.setAllowed(alice, true);
        permission.setAllowed(alice2, true);
        permission.setAllowed(alice3, true);
        permission.setAllowed(bob, true);
        permission.setAllowed(owner, true);
    }

    function _join(address who) internal returns (bytes32 person) {
        vm.prank(who);
        person = registry.register("");
    }

    function test_join_and_link_one_person_one_vote() public {
        bytes32 personA = _join(alice);
        vm.prank(alice);
        registry.offerLink(alice2);
        vm.prank(alice2);
        registry.acceptLinkFrom(alice);

        vm.prank(alice);
        registry.offerLink(alice3);
        vm.prank(alice3);
        registry.acceptLinkFrom(alice);

        assertEq(registry.personOf(alice), personA);
        assertEq(registry.personOf(alice2), personA);
        assertEq(registry.personOf(alice3), personA);
        assertEq(registry.walletsOf(personA).length, 3);

        bytes32 personB = _join(bob);
        assertTrue(personA != personB);

        vm.warp(block.timestamp + 2);
        uint256 id = governor.propose("Ship SCNID POV?");
        vm.warp(block.timestamp + 2);

        vm.prank(alice2);
        governor.castPersonVote(id, PersonGovernor.Support.For);

        vm.prank(alice3);
        vm.expectRevert(PersonGovernor.AlreadyVoted.selector);
        governor.castPersonVote(id, PersonGovernor.Support.Against);

        vm.prank(bob);
        governor.castPersonVote(id, PersonGovernor.Support.For);

        PersonGovernor.Proposal memory p = governor.proposals(id);
        assertEq(p.person.forVotes, 2);
    }

    function test_registered_too_late() public {
        _join(alice);
        uint256 id = governor.propose("late join?");
        _join(bob);
        vm.warp(block.timestamp + 2);
        vm.prank(bob);
        vm.expectRevert(PersonGovernor.RegisteredTooLate.selector);
        governor.castPersonVote(id, PersonGovernor.Support.For);
    }

    function test_attestation_adapter_compiles_and_sets() public {
        AttestedPersonhoodAdapter attested = new AttestedPersonhoodAdapter(owner, 1, 3000);
        attested.setAttestor(owner, true);
        registry.setPrimaryAdapter(address(attested));
        assertEq(registry.sybilBound(), 1);
    }

    function test_nullifier_stub_disabled() public {
        ReceptorNullifierAdapter nullifier = new ReceptorNullifierAdapter(owner);
        assertFalse(nullifier.enabled());
        registry.setPrimaryAdapter(address(nullifier));
        assertEq(nullifier.maxKeysPerHuman(), type(uint32).max);
    }
}

contract BicameralScaffoldTest is Test {
    function test_stake_vault_and_bicameral_construct() public {
        MockPermission permission = new MockPermission();
        MockBootstrapRegistry bootstrap = new MockBootstrapRegistry();
        bootstrap.register("permission", address(permission));
        RedbellyEligibility eligibility = new RedbellyEligibility(address(bootstrap), false);
        PersonhoodRegistry registry = new PersonhoodRegistry(address(eligibility), address(this));
        MockPersonhoodAdapter mock = new MockPersonhoodAdapter();
        registry.setPrimaryAdapter(address(mock));
        StakeVault vault = new StakeVault(address(eligibility), 1 days);
        BicameralGovernor.Thresholds memory t = BicameralGovernor.Thresholds({
            stakeQuorumBps: 1000,
            stakeApprovalBps: 5001,
            personQuorumBps: 1000,
            personApprovalBps: 5001
        });
        BicameralGovernor gov =
            new BicameralGovernor(address(eligibility), address(registry), address(vault), address(this), t);
        assertEq(address(gov.vault()), address(vault));
        assertEq(vault.unbondingPeriod(), 1 days);
    }
}
