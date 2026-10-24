// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {RedbellyEligibility} from "../contracts/gate/RedbellyEligibility.sol";
import {PersonhoodRegistry} from "../contracts/personhood/PersonhoodRegistry.sol";
import {MockPersonhoodAdapter} from "../contracts/personhood/adapters/MockPersonhoodAdapter.sol";
import {AttestedPersonhoodAdapter} from "../contracts/personhood/adapters/AttestedPersonhoodAdapter.sol";
import {ReceptorNullifierAdapter} from "../contracts/personhood/adapters/ReceptorNullifierAdapter.sol";
import {PersonGovernor} from "../contracts/governance/PersonGovernor.sol";
import {StakeVault} from "../contracts/weight/StakeVault.sol";

/// @notice Deploys SCNID against real Redbelly testnet Permission (chain 153).
/// @dev Bootstrap registry is the same address on 151 and 153.
///      `treatExtenderAsBusiness = false` so extender-granted testnet wallets can Join.
contract TestnetDeploy is Script {
    address constant BOOTSTRAP = 0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        require(block.chainid == 153, "TestnetDeploy: expected chain 153");

        vm.startBroadcast(pk);

        RedbellyEligibility eligibility = new RedbellyEligibility(BOOTSTRAP, false);
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

        vm.stopBroadcast();

        address permission = address(eligibility.permission());

        string memory json = string.concat(
            "{\n",
            '  "permission": "',
            vm.toString(permission),
            '",\n',
            '  "bootstrap": "',
            vm.toString(BOOTSTRAP),
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
        vm.writeFile("broadcast/testnet-addresses.json", json);

        console2.log("deployer", deployer);
        console2.log("permission", permission);
        console2.log("eligibility", address(eligibility));
        console2.log("registry", address(registry));
        console2.log("governor", address(governor));
        console2.log("Wrote broadcast/testnet-addresses.json");
    }
}
