// SPDX-License-Identifier: MIT
// aderyn-ignore-next-line(unspecific-solidity-pragma,push-zero-opcode)
pragma solidity ^0.8.23;

/// @title IAttackRegistry
/// @notice Interface for the BattleChain AttackRegistry contract
interface IAttackRegistry {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    /// @dev `NEW_DEPLOYMENT` is reserved and unreachable via public APIs — every registration
    ///      path sets `attackRequested = true` or `promoted = true`, so `_getAgreementState`
    ///      cannot return it. The slot is preserved to avoid an ABI break for indexers that
    ///      decode the enum by index.
    enum ContractState {
        NOT_DEPLOYED,
        NEW_DEPLOYMENT,
        ATTACK_REQUESTED,
        UNDER_ATTACK,
        PROMOTION_REQUESTED,
        PRODUCTION,
        CORRUPTED
    }

    struct AgreementInfo {
        address attackModerator; // Who can manage this agreement's attack status
        uint256 deadlineTimestamp; // When current timer expires
        // Block timestamp at which `promote()` was called, or 0 if no unresolved promote exists.
        // Cleared by every explicit terminal transition: cancelPromotion, markCorrupted,
        // instantCorrupt, instantPromote, and finalizeState. A non-zero value does NOT strictly
        // mean "promotion still pending" — it can also persist between when PROMOTION_DELAY
        // elapses (state computes to PRODUCTION) and when finalizeState materializes that
        // transition. It only means "promote() was called and no explicit terminal transition
        // has cleared it yet".
        uint256 promotionRequestedTimestamp;
        bool attackRequested; // Has attack mode been requested?
        bool attackApproved; // Has the request been approved?
        bool promoted; // Terminal flag - promoted to production
        bool corrupted; // Terminal flag - attack succeeded
        bool isRegistered; // Whether the agreement has been registered
    }

    /*//////////////////////////////////////////////////////////////
              DEPLOYER STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Called by BattleChainDeployer when a new contract is deployed
    /// @dev Records who deployed the contract. Deployer is automatically authorized.
    function registerDeployment(address contractAddress, address deployer) external;

    /// @notice Authorize an address to request attack mode for a contract
    /// @dev Only the current authorized owner can transfer authority.
    function authorizeAgreementOwner(address contractAddress, address newOwner) external;

    /*//////////////////////////////////////////////////////////////
              ATTACK MODERATOR STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Transfer attack moderator role to a new address for an agreement
    function transferAttackModerator(address agreementAddress, address newModerator) external;

    /// @notice Request attack mode for all contracts in an agreement's BattleChain scope
    /// @dev Only for contracts deployed via BattleChainDeployer (must have an authorized owner
    ///      set via `registerDeployment` / `authorizeAgreementOwner`).
    function requestUnderAttack(address agreementAddress) external;

    /// @notice Request attack mode for unverified contracts (not deployed via BattleChainDeployer)
    /// @dev "Unverified" means ownership cannot be proven on-chain. DAO performs extra due diligence.
    function requestUnderAttackForUnverifiedContracts(address agreementAddress) external;

    /// @notice Backwards-compatible alias for requestUnderAttackForUnverifiedContracts
    /// @dev Deprecated: use requestUnderAttackForUnverifiedContracts instead
    function requestUnderAttackByNonAuthorized(address agreementAddress) external;

    /// @notice Skip attack mode and go directly to production
    /// @dev For protocols that don't want the attack phase. Must be deployed via BattleChainDeployer.
    function goToProduction(address agreementAddress) external;

    /// @notice Request promotion to production for all contracts in agreement (3-day delay)
    function promote(address agreementAddress) external;

    /// @notice Cancel a pending promotion for all contracts in agreement, returning to UNDER_ATTACK state
    function cancelPromotion(address agreementAddress) external;

    /// @notice Mark all contracts in agreement as corrupted after successful attack
    function markCorrupted(address agreementAddress) external;

    /*//////////////////////////////////////////////////////////////
            REGISTRY MODERATOR STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice DAO approves all contracts in agreement to enter attack mode
    function approveAttack(address agreementAddress) external;

    /// @notice DAO rejects attack request for all contracts in agreement
    /// @param agreementAddress The agreement to reject
    /// @param slashBond If true, slash both fee and bond (hard reject). If false, make both claimable (soft reject).
    function rejectAttackRequest(address agreementAddress, bool slashBond) external;

    /// @notice DAO instantly promotes all contracts in agreement to production
    function instantPromote(address agreementAddress) external;

    /// @notice DAO marks an agreement as corrupted after a successful attack
    function instantCorrupt(address agreementAddress) external;

    /*//////////////////////////////////////////////////////////////
                    OWNER STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Change the registry moderator address
    function changeRegistryModerator(address newModerator) external;

    /// @notice Change the safe harbor registry address
    function setSafeHarborRegistry(address newRegistry) external;

    /*//////////////////////////////////////////////////////////////
              AGREEMENT SYNC STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Register a contract for an existing agreement (called by Agreement on scope add)
    function registerContractForExistingAgreement(address contractAddress) external;

    /// @notice Unregister a contract for an existing agreement (called by Agreement on scope remove)
    function unregisterContractForExistingAgreement(address contractAddress) external;

    /// @notice Manual fallback to sync new contracts for pre-existing agreements
    function syncNewContracts(address agreementAddress) external;

    /*//////////////////////////////////////////////////////////////
                        USER READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Check if a top-level contract is currently under attack (attackable)
    /// @dev Looks up the contract's agreement and checks its state
    /// @return True if the contract's agreement is in UNDER_ATTACK or PROMOTION_REQUESTED state
    function isTopLevelContractUnderAttack(address contractAddress) external view returns (bool);

    /// @notice Get the granular state of an agreement
    function getAgreementState(address agreementAddress) external view returns (ContractState);

    /// @notice Get the attack moderator for an agreement
    function getAttackModerator(address agreementAddress) external view returns (address);

    /// @notice Get the agreement address for a contract
    function getAgreementForContract(address contractAddress) external view returns (address);

    /// @notice Get the full agreement info
    function getAgreementInfo(address agreementAddress) external view returns (AgreementInfo memory);

    /// @notice Get the registry moderator address
    function getRegistryModerator() external view returns (address);

    /// @notice Get the safe harbor registry address
    function getSafeHarborRegistry() external view returns (address);

    /// @notice Get the authorized owner for a contract
    function getAuthorizedOwner(address contractAddress) external view returns (address);

}
