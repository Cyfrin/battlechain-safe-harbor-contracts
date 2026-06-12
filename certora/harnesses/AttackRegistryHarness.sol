// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { AttackRegistry } from "src/AttackRegistry.sol";

/// @title AttackRegistryHarness
/// @notice Minimal harness for Certora verification of AttackRegistry
contract AttackRegistryHarness is AttackRegistry {
    // Empty — we use public getters (getAgreementState, getAgreementInfo, etc.)
    // and ghost variables with storage hooks for private state tracking.
}
