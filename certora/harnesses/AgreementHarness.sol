// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Agreement } from "src/Agreement.sol";
import {
    AgreementDetails,
    BountyTerms
} from "src/types/AgreementTypes.sol";

/// @title AgreementHarness
/// @notice Exposes Agreement internals for Certora verification
contract AgreementHarness is Agreement {
    constructor(
        address registry,
        address owner,
        string memory battleChainCaip2ChainId,
        AgreementDetails memory details
    )
        Agreement(registry, owner, battleChainCaip2ChainId, details)
    {}

    function getBountyPercentage() external view returns (uint256) {
        return this.getBountyTerms().bountyPercentage;
    }

    function getBountyCapUsd() external view returns (uint256) {
        return this.getBountyTerms().bountyCapUsd;
    }

    function getAggregateBountyCapUsd() external view returns (uint256) {
        return this.getBountyTerms().aggregateBountyCapUsd;
    }

    function getRetainable() external view returns (bool) {
        return this.getBountyTerms().retainable;
    }

    function getIdentity() external view returns (uint8) {
        return uint8(this.getBountyTerms().identity);
    }

    function getChainCount() external view returns (uint256) {
        return this.getChainIds().length;
    }
}
