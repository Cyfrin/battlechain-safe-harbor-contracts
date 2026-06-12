// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { AttackRegistry } from "src/AttackRegistry.sol";

/// @title ChangeRegistryModerator
/// @notice Changes the registry moderator on an AttackRegistry proxy
contract ChangeRegistryModerator is Script {
    function run(address attackRegistryProxy, address newModerator) external {
        AttackRegistry registry = AttackRegistry(attackRegistryProxy);

        console.log("AttackRegistry Proxy:", attackRegistryProxy);
        console.log("Current Moderator:", registry.getRegistryModerator());
        console.log("New Moderator:", newModerator);

        vm.startBroadcast();
        registry.changeRegistryModerator(newModerator);
        vm.stopBroadcast();

        console.log("Registry moderator updated successfully");
    }
}
