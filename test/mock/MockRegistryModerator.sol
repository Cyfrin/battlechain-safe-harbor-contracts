// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IAttackRegistry } from "src/interface/IAttackRegistry.sol";

/// @title MockRegistryModerator
/// @notice A permissionless moderator that lets anyone approve attacks. For testnet use only.
contract MockRegistryModerator {
    IAttackRegistry private immutable i_attackRegistry;

    constructor(address attackRegistry) {
        i_attackRegistry = IAttackRegistry(attackRegistry);
    }

    function approveAttack(address agreementAddress) external {
        i_attackRegistry.approveAttack(agreementAddress);
    }
}
