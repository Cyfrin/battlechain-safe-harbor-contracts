// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @dev Single source of truth for the BattleChain Safe Harbor version.
///      Imported by all contracts and deploy scripts.
string constant BATTLECHAIN_SAFE_HARBOR_VERSION = "5.0.0";
string constant BATTLECHAIN_SAFE_HARBOR_VERSION_TAG = string.concat("v", BATTLECHAIN_SAFE_HARBOR_VERSION);
