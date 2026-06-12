// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { CreateX } from "src/CreateX.sol";

/// @title DeployCreateX
/// @notice Deploys the CreateX factory contract to chains where it is not already available
/// @dev After deployment, update HelperConfig with the deployed CreateX address
contract DeployCreateX is Script {
    function run() external returns (address createx) {
        console.log("Deploying CreateX...");
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast();
        createx = address(new CreateX());
        vm.stopBroadcast();

        console.log("CreateX deployed at:", createx);
        console.log("Update HelperConfig with this address");
    }
}
