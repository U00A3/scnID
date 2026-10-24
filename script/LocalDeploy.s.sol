// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {MockPermission, MockBootstrapRegistry} from "../contracts/mocks/MockRedbelly.sol";
import {RedbellyEligibility} from "../contracts/gate/RedbellyEligibility.sol";
import {PersonhoodRegistry} from "../contracts/personhood/PersonhoodRegistry.sol";
import {MockPersonhoodAdapter} from "../contracts/personhood/adapters/MockPersonhoodAdapter.sol";
import {AttestedPersonhoodAdapter} from "../contracts/personhood/adapters/AttestedPersonhoodAdapter.sol";
import {ReceptorNullifierAdapter} from "../contracts/personhood/adapters/ReceptorNullifierAdapter.sol";
import {PersonGovernor} from "../contracts/governance/PersonGovernor.sol";
import {StakeVault} from "../contracts/weight/StakeVault.sol";

/// @notice Deploys SCNID stack to Anvil. Writes `broadcast/local-addresses.json` for the UI.
contract LocalDeploy is Script {
    function run() external {
        uint256 pk = vm.envOr(
            "PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        MockPermission permission = new MockPermission();
        MockBootstrapRegistry bootstrap = new MockBootstrapRegistry();
        bootstrap.register("permission", address(permission));

        RedbellyEligibility eligibility = new RedbellyEligibility(address(bootstrap), false);
        PersonhoodRegistry registry = new PersonhoodRegistry(address(eligibility), deployer);
        MockPersonhoodAdapter mock = new MockPersonhoodAdapter();
        registry.setPrimaryAdapter(address(mock));
        registry.setUnlinkCooldown(0);
        registry.setRebindDelay(1 hours);

        PersonGovernor governor = new PersonGovernor(address(eligibility), address(registry), deployer);
        governor.setGovernanceParams(30, 1 days, 500, 5001);

        AttestedPersonhoodAdapter attested = new AttestedPersonhoodAdapter(deployer, 1, 2500);
        attested.setAttestor(deployer, true);
        ReceptorNullifierAdapter nullifier = new ReceptorNullifierAdapter(deployer);
        StakeVault vault = new StakeVault(address(eligibility), 3 days);

        // Anvil accounts 0..4
        permission.setAllowed(deployer, true);
        permission.setAllowed(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, true);
        permission.setAllowed(0x70997970C51812dc3A010C7d01b50e0d17dc79C8, true);
        permission.setAllowed(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC, true);
        permission.setAllowed(0x90F79bf6EB2c4f870365E785982E1f101E93b906, true);
        permission.setAllowed(0x15D34aAF54267db7D7C265903312BCe024D64b19, true);


        vm.stopBroadcast();

        string memory json = string.concat(
            "{\n",
            '  "permission": "',
            vm.toString(address(permission)),
            '",\n',
            '  "bootstrap": "',
            vm.toString(address(bootstrap)),
            '",\n',
            '  "eligibility": "',
            vm.toString(address(eligibility)),
            '",\n',
            '  "registry": "',
            vm.toString(address(registry)),
            '",\n',
            '  "mockAdapter": "',
            vm.toString(address(mock)),
            '",\n',
            '  "attestedAdapter": "',
            vm.toString(address(attested)),
            '",\n',
            '  "nullifierAdapter": "',
            vm.toString(address(nullifier)),
            '",\n',
            '  "governor": "',
            vm.toString(address(governor)),
            '",\n',
            '  "vault": "',
            vm.toString(address(vault)),
            '",\n',
            '  "chainId": ',
            vm.toString(block.chainid),
            "\n}\n"
        );
        vm.writeFile("broadcast/local-addresses.json", json);

        console2.log("eligibility", address(eligibility));
        console2.log("registry", address(registry));
        console2.log("governor", address(governor));
        console2.log("Wrote broadcast/local-addresses.json");
    }
}
