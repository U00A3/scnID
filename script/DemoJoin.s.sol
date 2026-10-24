// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {PersonhoodRegistry} from "../contracts/personhood/PersonhoodRegistry.sol";
import {PersonGovernor} from "../contracts/governance/PersonGovernor.sol";

contract DemoJoin is Script {
    function run() external {
        string memory json = vm.readFile("broadcast/local-addresses.json");
        PersonhoodRegistry registry = PersonhoodRegistry(vm.parseJsonAddress(json, ".registry"));
        PersonGovernor governor = PersonGovernor(vm.parseJsonAddress(json, ".governor"));

        uint256 pk0 = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        uint256 pk1 = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        uint256 pk2 = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
        uint256 pk3 = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
        address a0 = vm.addr(pk0);
        address a1 = vm.addr(pk1);
        address a2 = vm.addr(pk2);
        address a3 = vm.addr(pk3);

        vm.startBroadcast(pk0);
        governor.setGovernanceParams(0, 1 days, 500, 5001);
        if (registry.personOf(a0) == bytes32(0)) registry.register("");
        if (registry.personOf(a1) == bytes32(0)) registry.offerLink(a1);
        vm.stopBroadcast();

        if (registry.personOf(a1) == bytes32(0)) {
            vm.startBroadcast(pk1);
            registry.acceptLinkFrom(a0);
            vm.stopBroadcast();
        }

        vm.startBroadcast(pk0);
        if (registry.personOf(a2) == bytes32(0)) registry.offerLink(a2);
        vm.stopBroadcast();

        if (registry.personOf(a2) == bytes32(0)) {
            vm.startBroadcast(pk2);
            registry.acceptLinkFrom(a0);
            vm.stopBroadcast();
        }

        if (registry.personOf(a3) == bytes32(0)) {
            vm.startBroadcast(pk3);
            registry.register("");
            vm.stopBroadcast();
        }

        console2.log("wallets", registry.walletsOf(registry.personOf(a0)).length);
    }
}
