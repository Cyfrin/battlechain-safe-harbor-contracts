// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { MockRegistryModerator } from "test/mock/MockRegistryModerator.sol";

/// @title DeployMockRegistryModerator
/// @notice Deploys a permissionless MockRegistryModerator for testnet use
contract DeployMockRegistryModerator is Script {
    function run(address attackRegistry) external returns (address) {
        console.log("Deploying MockRegistryModerator...");
        console.log("AttackRegistry:", attackRegistry);

        vm.startBroadcast();
        MockRegistryModerator moderator = new MockRegistryModerator(attackRegistry);
        vm.stopBroadcast();

        console.log("MockRegistryModerator deployed at:", address(moderator));
        return address(moderator);
    }
}
