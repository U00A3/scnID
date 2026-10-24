// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {PersonhoodRegistry} from "../contracts/personhood/PersonhoodRegistry.sol";
import {PersonGovernor} from "../contracts/governance/PersonGovernor.sol";

contract DemoVote is Script {
    function run() external {
        string memory json = vm.readFile("broadcast/local-addresses.json");
        PersonGovernor governor = PersonGovernor(vm.parseJsonAddress(json, ".governor"));

        uint256 pk0 = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        uint256 pk1 = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        uint256 pk2 = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
        uint256 pk3 = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

        vm.startBroadcast(pk0);
        uint256 id = governor.propose("SCNID demo: ship person chamber?");
        vm.stopBroadcast();

        vm.startBroadcast(pk1);
        governor.castPersonVote(id, PersonGovernor.Support.For);
        vm.stopBroadcast();

        // Double-vote from a linked wallet is covered in forge test; skip here (broadcast + try/catch is noisy).

        vm.startBroadcast(pk3);
        governor.castPersonVote(id, PersonGovernor.Support.For);
        vm.stopBroadcast();

        PersonGovernor.Proposal memory p = governor.proposals(id);
        console2.log("forVotes", p.person.forVotes);
        require(p.person.forVotes == 2, "expected 2 for");
        console2.log("Demo OK");
    }
}
