// SPDX-License-Identifier: MIT
// aderyn-ignore-next-line(unspecific-solidity-pragma,push-zero-opcode)
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Per-agreement bond deposit record held by the AttackRegistry / BondManager.
/// @dev Lives outside IAttackRegistry so the interface itself carries no OpenZeppelin
///      dependency and stays importable by downstream consumers without a recursive
///      submodule checkout. The `token` field keeps its IERC20 typing because consumers
///      use it directly (transfers, mapping keys).
struct BondDeposit {
    address depositor; // Who paid (agreement owner at deposit time)
    IERC20 token; // Token snapshot (survives token config changes)
    uint256 feeAmount; // Fee paid (sent to treasury, recorded for audit)
    uint256 bondAmount; // Bond held in registry
    bool bondClaimable; // True on soft reject, markCorrupted, promote->PRODUCTION
    bool claimed; // True after claimBond()
    bool slashed; // True on hard reject, instantPromote, instantCorrupt
}
