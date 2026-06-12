// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IAttackRegistry } from "src/interface/IAttackRegistry.sol";
import { IBattleChainSafeHarborRegistry } from "src/interface/IBattleChainSafeHarborRegistry.sol";
import { IAgreement } from "src/interface/IAgreement.sol";
import { IAgreementFactory } from "src/interface/IAgreementFactory.sol";
import { BondManager } from "src/BondManager.sol";
import { BATTLECHAIN_SAFE_HARBOR_VERSION } from "src/Version.sol";

/// @title AttackRegistry
/// @notice Tracks the attack/production status of deployed contracts on BattleChain.
/// @dev Agreements go through states: NOT_DEPLOYED -> ATTACK_REQUESTED -> UNDER_ATTACK -> PRODUCTION
///      All unregistered agreements report `NOT_DEPLOYED` regardless of how the underlying
///      contracts were deployed (via BattleChainDeployer or externally). The `NEW_DEPLOYMENT`
///      enum value is reserved and unreachable via public APIs — every registration path also
///      sets `attackRequested = true` (or `promoted = true`), so the conditions to return it
///      from `_getAgreementState` cannot be satisfied. It is preserved in the enum to avoid a
///      breaking ABI change for indexers.
///      The registryModerator (DAO) can approve attacks, reject requests, and instant-promote contracts.
/// @dev Designed for use with a UUPS proxy for upgradability.
/// @custom:security-contact security@battlechain.com
// aderyn-ignore-next-line(contract-locks-ether)
contract AttackRegistry is IAttackRegistry, Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, BondManager {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error AttackRegistry__Unauthorized(address caller);
    error AttackRegistry__InvalidState(ContractState current);
    error AttackRegistry__InsufficientCommitment(uint256 required, uint256 actual);
    error AttackRegistry__ZeroAddress();
    error AttackRegistry__NotAgreementOwner(address caller, address owner);
    error AttackRegistry__AgreementOwnerNotAuthorized(address contractAddress, address agreementOwner);
    error AttackRegistry__EmptyContractArray();
    error AttackRegistry__InvalidAgreement(address agreementAddress);
    error AttackRegistry__NotDeployedViaBattleChainDeployer(address contractAddress);
    error AttackRegistry__DeployedViaBattleChainDeployer(address contractAddress);
    error AttackRegistry__ContractAlreadyLinked(address contractAddress, address existingAgreement);
    error AttackRegistry__AgreementNotRegistered(address agreementAddress);
    error AttackRegistry__NoNewContracts(address agreementAddress);
    error AttackRegistry__ContractAlreadyRegistered(address contractAddress);
    error AttackRegistry__RenounceDisabled();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    string public constant VERSION = BATTLECHAIN_SAFE_HARBOR_VERSION;
    uint256 public constant PROMOTION_WINDOW = 14 days;
    uint256 public constant PROMOTION_DELAY = 3 days;
    uint256 public constant MIN_COMMITMENT = 7 days;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event AgreementStateChanged(address indexed agreementAddress, ContractState newState);
    event AttackModeratorTransferred(address indexed agreementAddress, address indexed newModerator);
    event RegistryModeratorChanged(address indexed newModerator);
    event SafeHarborRegistryChanged(address indexed newRegistry);
    event AgreementFactoryChanged(address indexed newFactory);
    event BattleChainDeployerChanged(address indexed newDeployer);
    event ContractRegistered(address indexed contractAddress, address indexed agreementAddress);
    event AgreementOwnerAuthorized(address indexed contractAddress, address indexed authorizedOwner);
    event ContractsSynced(address indexed agreementAddress, uint256 newContractCount);
    event ContractUnregistered(address indexed contractAddress, address indexed agreementAddress);
    event UnverifiedContractSynced(address indexed contractAddress, address indexed agreementAddress);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev Maps agreement address to its state info
    mapping(address agreementAddress => AgreementInfo info) private s_agreementInfo;
    /// @dev Maps contract address to its agreement address (set when requestUnderAttack is called)
    mapping(address contractAddress => address agreementAddress) private s_contractToAgreement;
    /// @dev Maps contract address to who deployed it via BattleChainDeployer
    mapping(address contractAddress => address deployer) private s_contractDeployer;
    /// @dev Maps contract address to who is authorized to request attack mode (set by deployer)
    mapping(address contractAddress => address authorizedOwner) private s_authorizedOwner;
    address private s_registryModerator;
    IBattleChainSafeHarborRegistry private s_safeHarborRegistry;
    IAgreementFactory private s_agreementFactory;
    address private s_battleChainDeployer;

    // aderyn-ignore-next-line(unused-state-variable)
    uint256[200] private __gap;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyAttackModerator(address agreementAddress) {
        _checkAttackModerator(agreementAddress);
        _;
    }

    modifier onlyRegistryModerator() {
        _checkRegistryModerator();
        _;
    }

    function _checkAttackModerator(address agreementAddress) internal view {
        if (msg.sender != s_agreementInfo[agreementAddress].attackModerator) {
            revert AttackRegistry__Unauthorized(msg.sender);
        }
    }

    function _checkRegistryModerator() internal view {
        if (msg.sender != s_registryModerator) {
            revert AttackRegistry__Unauthorized(msg.sender);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/
    function initialize(
        address _initialOwner,
        address _registryModerator,
        address _safeHarborRegistry,
        address _agreementFactory,
        address _battleChainDeployer,
        address _treasury
    )
        external
        initializer
    {
        // _initialOwner == address(0) is checked downstream in __Ownable_init
        // (reverts with OwnableInvalidOwner). _treasury == address(0) is checked
        // downstream in _setTreasury (reverts with BondManager__ZeroAddress).
        if (_registryModerator == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        if (_safeHarborRegistry == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        if (_agreementFactory == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        if (_battleChainDeployer == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        __Ownable_init(_initialOwner);
        s_registryModerator = _registryModerator;
        s_safeHarborRegistry = IBattleChainSafeHarborRegistry(_safeHarborRegistry);
        s_agreementFactory = IAgreementFactory(_agreementFactory);
        s_battleChainDeployer = _battleChainDeployer;
        _setTreasury(_treasury);
    }

    /*//////////////////////////////////////////////////////////////
                  DEPLOYER STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Called by BattleChainDeployer when a new contract is deployed
    /// @dev Records who deployed the contract. Deployer is automatically authorized to request attack mode.
    /// @param contractAddress The address of the newly deployed contract
    /// @param deployer The address that deployed this contract
    function registerDeployment(address contractAddress, address deployer) external {
        if (msg.sender != s_battleChainDeployer) {
            revert AttackRegistry__Unauthorized(msg.sender);
        }
        if (s_contractDeployer[contractAddress] != address(0)) {
            revert AttackRegistry__ContractAlreadyRegistered(contractAddress);
        }
        emit ContractRegistered(contractAddress, address(0)); // No agreement yet
        emit AgreementOwnerAuthorized(contractAddress, deployer);
        s_contractDeployer[contractAddress] = deployer;
        // Deployer is automatically authorized until they transfer authority
        s_authorizedOwner[contractAddress] = deployer;
    }

    /// @notice Authorize an address to request attack mode for a contract
    /// @dev Only the current authorized owner can transfer authority.
    /// @param contractAddress The contract to authorize for
    /// @param newOwner The address to authorize (typically the agreement owner)
    function authorizeAgreementOwner(address contractAddress, address newOwner) external {
        if (newOwner == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        address currentOwner = s_authorizedOwner[contractAddress];
        if (currentOwner == address(0)) {
            revert AttackRegistry__NotDeployedViaBattleChainDeployer(contractAddress);
        }
        if (msg.sender != currentOwner) {
            revert AttackRegistry__Unauthorized(msg.sender);
        }
        emit AgreementOwnerAuthorized(contractAddress, newOwner);
        s_authorizedOwner[contractAddress] = newOwner;
    }

    /*//////////////////////////////////////////////////////////////
              ATTACK MODERATOR STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Transfer attack moderator role to a new address for an agreement
    /// @param agreementAddress The agreement to transfer moderation for
    /// @param newModerator The new moderator address
    function transferAttackModerator(
        address agreementAddress,
        address newModerator
    )
        external
        onlyAttackModerator(agreementAddress)
    {
        if (newModerator == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        ContractState currentState = _getAgreementState(agreementAddress);
        if (currentState == ContractState.PRODUCTION || currentState == ContractState.CORRUPTED) {
            revert AttackRegistry__InvalidState(currentState);
        }
        emit AttackModeratorTransferred(agreementAddress, newModerator);
        s_agreementInfo[agreementAddress].attackModerator = newModerator;
    }

    /// @notice Request attack mode for all contracts in an agreement's BattleChain scope
    /// @dev Only for contracts deployed via BattleChainDeployer. The agreement owner must be the
    ///      authorized owner (`s_authorizedOwner`) for every contract — initially the deployer,
    ///      but the deployer can transfer authority via `authorizeAgreementOwner`.
    /// @dev If a prior unclaimed bond exists on this agreement (e.g., after a soft reject), it
    ///      is forfeited when the new bond is collected. Claim before re-registering.
    /// @param agreementAddress The safe harbor agreement
    function requestUnderAttack(address agreementAddress) external {
        (address agreementOwner, address[] memory contracts) = _validateAndPrepareAgreement(agreementAddress);

        // Validate all contracts were authorized for this agreement owner
        uint256 length = contracts.length;
        // aderyn-ignore-next-line(require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            if (s_authorizedOwner[contracts[i]] != agreementOwner) {
                revert AttackRegistry__AgreementOwnerNotAuthorized(contracts[i], agreementOwner);
            }
        }

        _registerAgreement(agreementAddress, agreementOwner, contracts);
        _collectFeeAndBond(agreementAddress, msg.sender, s_verifiedBondAmount);
    }

    /// @notice Request attack mode for unverified contracts (not deployed via BattleChainDeployer)
    /// @dev "Unverified" means ownership cannot be proven on-chain — there is no BattleChainDeployer
    ///      provenance chain (s_contractDeployer → s_authorizedOwner). DAO will perform extra due
    ///      diligence for these requests. Contracts deployed via BattleChainDeployer cannot be
    ///      claimed through this path — they must use `requestUnderAttack` with proper authorization.
    /// @dev If a prior unclaimed bond exists on this agreement (e.g., after a soft reject), it
    ///      is forfeited when the new bond is collected. Claim before re-registering.
    /// @param agreementAddress The safe harbor agreement
    function requestUnderAttackForUnverifiedContracts(address agreementAddress) public {
        (address agreementOwner, address[] memory contracts) = _validateAndPrepareAgreement(agreementAddress);

        // Prevent claiming contracts that were deployed via BattleChainDeployer
        uint256 length = contracts.length;
        // aderyn-ignore-next-line(require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            if (s_contractDeployer[contracts[i]] != address(0)) {
                revert AttackRegistry__DeployedViaBattleChainDeployer(contracts[i]);
            }
        }

        _registerAgreement(agreementAddress, agreementOwner, contracts);
        _collectFeeAndBond(agreementAddress, msg.sender, s_unverifiedBondAmount);
    }

    /// @notice Backwards-compatible alias for requestUnderAttackForUnverifiedContracts
    /// @dev Deprecated: use requestUnderAttackForUnverifiedContracts instead
    function requestUnderAttackByNonAuthorized(address agreementAddress) external {
        requestUnderAttackForUnverifiedContracts(agreementAddress);
    }

    /// @notice Skip attack mode and go directly to production
    /// @dev For protocols that don't want the attack phase. Must be deployed via BattleChainDeployer.
    ///      No fee or bond is collected — the bond exists to deter griefing during the attack phase,
    ///      which this path skips entirely. Requires verified ownership (s_authorizedOwner), so
    ///      unverified contracts cannot use this path to avoid bond costs.
    /// @param agreementAddress The safe harbor agreement
    function goToProduction(address agreementAddress) external {
        (address agreementOwner, address[] memory contracts) = _validateAndPrepareAgreement(agreementAddress);

        // Validate all contracts were authorized for this agreement owner
        uint256 length = contracts.length;
        // aderyn-ignore-next-line(require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            if (s_authorizedOwner[contracts[i]] != agreementOwner) {
                revert AttackRegistry__AgreementOwnerNotAuthorized(contracts[i], agreementOwner);
            }
        }

        // Register and immediately promote to production
        _registerAgreementAndPromote(agreementAddress, agreementOwner, contracts);
    }

    /// @notice Request promotion to production for an agreement (3-day delay)
    /// @param agreementAddress The agreement to promote
    function promote(address agreementAddress) external onlyAttackModerator(agreementAddress) {
        ContractState currentState = _getAgreementState(agreementAddress);
        if (currentState != ContractState.UNDER_ATTACK) {
            revert AttackRegistry__InvalidState(currentState);
        }
        emit AgreementStateChanged(agreementAddress, ContractState.PROMOTION_REQUESTED);
        s_agreementInfo[agreementAddress].promotionRequestedTimestamp = block.timestamp;
    }

    /// @notice Cancel a pending promotion, returning to UNDER_ATTACK state
    /// @param agreementAddress The agreement to cancel promotion for
    function cancelPromotion(address agreementAddress) external onlyAttackModerator(agreementAddress) {
        ContractState currentState = _getAgreementState(agreementAddress);
        if (currentState != ContractState.PROMOTION_REQUESTED) {
            revert AttackRegistry__InvalidState(currentState);
        }
        emit AgreementStateChanged(agreementAddress, ContractState.UNDER_ATTACK);
        s_agreementInfo[agreementAddress].promotionRequestedTimestamp = 0;
    }

    /// @notice Mark an agreement as corrupted after successful attack
    /// @param agreementAddress The agreement to mark as corrupted
    function markCorrupted(address agreementAddress) external onlyAttackModerator(agreementAddress) {
        ContractState currentState = _getAgreementState(agreementAddress);
        if (currentState != ContractState.UNDER_ATTACK && currentState != ContractState.PROMOTION_REQUESTED) {
            revert AttackRegistry__InvalidState(currentState);
        }
        emit AgreementStateChanged(agreementAddress, ContractState.CORRUPTED);
        s_agreementInfo[agreementAddress].corrupted = true;
        // Clear the timestamp now that an explicit terminal transition has occurred.
        // See `AgreementInfo.promotionRequestedTimestamp` in IAttackRegistry for the
        // (more nuanced) semantics of this field.
        s_agreementInfo[agreementAddress].promotionRequestedTimestamp = 0;
        _markBondClaimable(agreementAddress);
    }

    /*//////////////////////////////////////////////////////////////
            REGISTRY MODERATOR STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice DAO approves an agreement to enter attack mode
    /// @param agreementAddress The agreement to approve for attack mode
    function approveAttack(address agreementAddress) external onlyRegistryModerator {
        ContractState currentState = _getAgreementState(agreementAddress);
        if (currentState != ContractState.ATTACK_REQUESTED) {
            revert AttackRegistry__InvalidState(currentState);
        }
        emit AgreementStateChanged(agreementAddress, ContractState.UNDER_ATTACK);
        s_agreementInfo[agreementAddress].attackApproved = true;
    }

    /// @notice DAO rejects an attack request for an agreement
    /// @dev Clears contract mappings so they can be included in a new agreement
    /// @param agreementAddress The agreement to reject
    /// @param slashBond If true, slash bond (hard reject). If false, mark bond claimable (soft reject).
    // aderyn-ignore-next-line(reentrancy-state-change)
    function rejectAttackRequest(address agreementAddress, bool slashBond) external onlyRegistryModerator {
        ContractState currentState = _getAgreementState(agreementAddress);
        if (currentState != ContractState.ATTACK_REQUESTED) {
            revert AttackRegistry__InvalidState(currentState);
        }

        // Get contracts to clear their mappings
        // aderyn-ignore-next-line(reentrancy-state-change)
        IAgreement agreement = IAgreement(agreementAddress);
        // aderyn-ignore-next-line(reentrancy-state-change)
        address[] memory contracts = agreement.getBattleChainScopeAddresses();
        uint256 length = contracts.length;

        // Clear contract -> agreement mappings
        // aderyn-ignore-next-line(costly-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            delete s_contractToAgreement[contracts[i]];
        }

        // Clear the agreement info
        emit AgreementStateChanged(agreementAddress, ContractState.NOT_DEPLOYED);
        delete s_agreementInfo[agreementAddress];

        if (slashBond) {
            _slashBond(agreementAddress);
        } else {
            _markBondClaimable(agreementAddress);
        }
    }

    /// @notice DAO instantly promotes an agreement to production
    /// @dev Useful when copycat contracts are discovered or high TVL situations.
    ///      Bond is always slashed — this is intentional. instantPromote bypasses battle-testing,
    ///      so the slash is the cost of the DAO short-circuiting the process. If the DAO wants to
    ///      be lenient, they should use approveAttack + the normal promote path (bond returned).
    /// @param agreementAddress The agreement to instantly promote
    function instantPromote(address agreementAddress) external onlyRegistryModerator {
        ContractState currentState = _getAgreementState(agreementAddress);
        // Allow from ATTACK_REQUESTED (skip attack entirely), UNDER_ATTACK, or PROMOTION_REQUESTED
        if (
            currentState != ContractState.ATTACK_REQUESTED && currentState != ContractState.UNDER_ATTACK
                && currentState != ContractState.PROMOTION_REQUESTED
        ) {
            revert AttackRegistry__InvalidState(currentState);
        }
        emit AgreementStateChanged(agreementAddress, ContractState.PRODUCTION);
        s_agreementInfo[agreementAddress].promoted = true;
        // Clear the timestamp now that an explicit terminal transition has occurred.
        // See `AgreementInfo.promotionRequestedTimestamp` in IAttackRegistry for the
        // (more nuanced) semantics of this field.
        s_agreementInfo[agreementAddress].promotionRequestedTimestamp = 0;
        _slashBond(agreementAddress);
    }

    /// @notice DAO marks an agreement as corrupted after a successful attack
    /// @dev For when the attack moderator is unresponsive or compromised
    /// @param agreementAddress The agreement to mark as corrupted
    function instantCorrupt(address agreementAddress) external onlyRegistryModerator {
        ContractState currentState = _getAgreementState(agreementAddress);
        if (currentState != ContractState.UNDER_ATTACK && currentState != ContractState.PROMOTION_REQUESTED) {
            revert AttackRegistry__InvalidState(currentState);
        }
        emit AgreementStateChanged(agreementAddress, ContractState.CORRUPTED);
        s_agreementInfo[agreementAddress].corrupted = true;
        // Clear the timestamp now that an explicit terminal transition has occurred.
        // See `AgreementInfo.promotionRequestedTimestamp` in IAttackRegistry for the
        // (more nuanced) semantics of this field.
        s_agreementInfo[agreementAddress].promotionRequestedTimestamp = 0;
        _slashBond(agreementAddress);
    }

    /*//////////////////////////////////////////////////////////////
              AGREEMENT SYNC STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Register a contract for an existing agreement (called by Agreement on scope add)
    /// @dev msg.sender must be a valid agreement from the factory
    /// @param contractAddress The contract address to register
    // aderyn-ignore-next-line(reentrancy-state-change)
    function registerContractForExistingAgreement(address contractAddress) external {
        if (!s_agreementFactory.isAgreementContract(msg.sender)) {
            revert AttackRegistry__InvalidAgreement(msg.sender);
        }

        AgreementInfo storage info = s_agreementInfo[msg.sender];

        // During Agreement construction, _addToBattleChainScope triggers this before the agreement
        // is registered in AttackRegistry. The actual bulk registration happens later via
        // requestUnderAttack/requestUnderAttackByNonAuthorized. Silently return as a safe no-op.
        if (!info.isRegistered) return;

        // Agreement remains mutable after terminal states; sync is a no-op since contracts
        // won't be "under attack" in PRODUCTION/CORRUPTED anyway.
        ContractState state = _getAgreementState(msg.sender);
        if (state == ContractState.PRODUCTION || state == ContractState.CORRUPTED) return;

        // Idempotent: silently return if already linked to this agreement
        if (s_contractToAgreement[contractAddress] == msg.sender) return;

        // Only block if existing agreement is still in an active attack state
        _revertIfLinkedToActiveAgreement(contractAddress);

        _validateAndLinkContract(contractAddress, msg.sender, IAgreement(msg.sender).owner());
    }

    /// @notice Unregister a contract for an existing agreement (called by Agreement on scope remove)
    /// @dev msg.sender must be a valid agreement from the factory
    /// @param contractAddress The contract address to unregister
    function unregisterContractForExistingAgreement(address contractAddress) external {
        // aderyn-ignore-next-line(reentrancy-state-change)
        if (!s_agreementFactory.isAgreementContract(msg.sender)) {
            revert AttackRegistry__InvalidAgreement(msg.sender);
        }

        // Safe no-op during construction or if never registered (see registerContractForExistingAgreement)
        if (!s_agreementInfo[msg.sender].isRegistered) return;

        // Idempotent: silently return if contract not linked to this agreement
        if (s_contractToAgreement[contractAddress] != msg.sender) return;

        delete s_contractToAgreement[contractAddress];
        emit ContractUnregistered(contractAddress, msg.sender);
    }

    /// @notice Manual fallback to sync new contracts for pre-existing agreements
    /// @dev Safe for anyone to call — scope is controlled by the agreement owner, and
    ///      BattleChainDeployer contracts still require authorized owner match.
    /// @param agreementAddress The agreement to sync contracts for
    // aderyn-ignore-next-line(reentrancy-state-change)
    function syncNewContracts(address agreementAddress) external {
        // aderyn-ignore-next-line(reentrancy-state-change)
        if (!s_agreementFactory.isAgreementContract(agreementAddress)) {
            revert AttackRegistry__InvalidAgreement(agreementAddress);
        }

        if (!s_agreementInfo[agreementAddress].isRegistered) {
            revert AttackRegistry__AgreementNotRegistered(agreementAddress);
        }

        ContractState state = _getAgreementState(agreementAddress);
        if (state == ContractState.PRODUCTION || state == ContractState.CORRUPTED) {
            revert AttackRegistry__InvalidState(state);
        }

        // aderyn-ignore-next-line(reentrancy-state-change)
        IAgreement agreement = IAgreement(agreementAddress);
        // aderyn-ignore-next-line(reentrancy-state-change)
        address agreementOwner = agreement.owner();
        // aderyn-ignore-next-line(reentrancy-state-change)
        address[] memory contracts = agreement.getBattleChainScopeAddresses();
        uint256 length = contracts.length;
        // aderyn-ignore-next-line(uninitialized-local-variable)
        uint256 newCount;

        // aderyn-ignore-next-line(costly-loop,require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            address contractAddr = contracts[i];

            // Skip contracts already linked to this agreement
            if (s_contractToAgreement[contractAddr] == agreementAddress) continue;

            // Only block if existing agreement is still in an active attack state
            _revertIfLinkedToActiveAgreement(contractAddr);

            _validateAndLinkContract(contractAddr, agreementAddress, agreementOwner);
            newCount++;
        }

        if (newCount == 0) {
            revert AttackRegistry__NoNewContracts(agreementAddress);
        }

        emit ContractsSynced(agreementAddress, newCount);
    }

    /*//////////////////////////////////////////////////////////////
                    OWNER STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // aderyn-ignore-next-line(centralization-risk)
    function changeRegistryModerator(address newModerator) external onlyOwner {
        if (newModerator == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        emit RegistryModeratorChanged(newModerator);
        s_registryModerator = newModerator;
    }

    // aderyn-ignore-next-line(centralization-risk)
    function setSafeHarborRegistry(address newRegistry) external onlyOwner {
        if (newRegistry == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        emit SafeHarborRegistryChanged(newRegistry);
        s_safeHarborRegistry = IBattleChainSafeHarborRegistry(newRegistry);
    }

    /// @notice Replace the AgreementFactory pointer.
    /// @dev DESTRUCTIVE for legacy agreements. The factory check in
    ///      `registerContractForExistingAgreement`, `unregisterContractForExistingAgreement`, and
    ///      `syncNewContracts` consults `newFactory.isAgreementContract(...)`. Agreements created
    ///      by the previous factory are not in `newFactory`'s `s_isAgreement` mapping, so their
    ///      scope-sync calls (`addAccounts`, `removeAccounts`, `addOrSetChains`, `removeChains`,
    ///      `syncNewContracts`) revert with `InvalidAgreement` after the swap.
    /// @dev Prefer upgrading the existing factory via UUPS — the proxy address (and therefore
    ///      `s_isAgreement`) is preserved across implementation upgrades, avoiding this issue.
    ///      Reserve `setAgreementFactory` for the rare case where a brand-new factory address is
    ///      required (e.g., the prior factory's proxy is unrecoverable).
    // aderyn-ignore-next-line(centralization-risk)
    function setAgreementFactory(address newFactory) external onlyOwner {
        if (newFactory == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        emit AgreementFactoryChanged(newFactory);
        s_agreementFactory = IAgreementFactory(newFactory);
    }

    // aderyn-ignore-next-line(centralization-risk)
    function setBattleChainDeployer(address newDeployer) external onlyOwner {
        if (newDeployer == address(0)) {
            revert AttackRegistry__ZeroAddress();
        }
        emit BattleChainDeployerChanged(newDeployer);
        s_battleChainDeployer = newDeployer;
    }

    /*//////////////////////////////////////////////////////////////
                    BOND CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // aderyn-ignore-next-line(centralization-risk)
    function setBondToken(address token) external onlyOwner {
        _setBondToken(token);
    }

    // aderyn-ignore-next-line(centralization-risk)
    function setTreasury(address treasury) external onlyOwner {
        _setTreasury(treasury);
    }

    // aderyn-ignore-next-line(centralization-risk)
    function setFeeAmount(uint256 amount) external onlyOwner {
        _setFeeAmount(amount);
    }

    // aderyn-ignore-next-line(centralization-risk)
    function setVerifiedBondAmount(uint256 amount) external onlyOwner {
        _setVerifiedBondAmount(amount);
    }

    // aderyn-ignore-next-line(centralization-risk)
    function setUnverifiedBondAmount(uint256 amount) external onlyOwner {
        _setUnverifiedBondAmount(amount);
    }

    // aderyn-ignore-next-line(centralization-risk)
    function withdrawFunds(address token, address recipient) external onlyOwner returns (uint256) {
        return _withdrawFunds(token, recipient);
    }

    /*//////////////////////////////////////////////////////////////
                        UUPS UPGRADE AUTHORIZATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Authorizes an upgrade to a new implementation
    /// @dev Only the owner can authorize upgrades
    /// @param newImplementation The address of the new implementation
    // aderyn-ignore-next-line(empty-block,centralization-risk)
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    function renounceOwnership() public pure override {
        revert AttackRegistry__RenounceDisabled();
    }

    /*//////////////////////////////////////////////////////////////
                        USER READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Check if a top-level contract is currently under attack (attackable)
    /// @dev Looks up the contract's agreement and checks its state
    /// @param contractAddress The contract to check
    /// @return True if the contract's agreement is in UNDER_ATTACK or PROMOTION_REQUESTED state
    function isTopLevelContractUnderAttack(address contractAddress) external view returns (bool) {
        address agreementAddress = s_contractToAgreement[contractAddress];
        if (agreementAddress == address(0)) {
            return false;
        }
        ContractState state = _getAgreementState(agreementAddress);
        return state == ContractState.UNDER_ATTACK || state == ContractState.PROMOTION_REQUESTED;
    }

    /// @notice Get the granular state of an agreement
    /// @param agreementAddress The agreement to check
    /// @return The detailed ContractState enum value
    function getAgreementState(address agreementAddress) external view returns (ContractState) {
        return _getAgreementState(agreementAddress);
    }

    /// @notice Get the attack moderator for an agreement
    function getAttackModerator(address agreementAddress) external view returns (address) {
        return s_agreementInfo[agreementAddress].attackModerator;
    }

    /// @notice Get the agreement address for a contract
    function getAgreementForContract(address contractAddress) external view returns (address) {
        return s_contractToAgreement[contractAddress];
    }

    /// @notice Get the full agreement info
    function getAgreementInfo(address agreementAddress) external view returns (AgreementInfo memory) {
        return s_agreementInfo[agreementAddress];
    }

    /// @notice Get who deployed a contract via BattleChainDeployer
    function getContractDeployer(address contractAddress) external view returns (address) {
        return s_contractDeployer[contractAddress];
    }

    function getRegistryModerator() external view returns (address) {
        return s_registryModerator;
    }

    function getSafeHarborRegistry() external view returns (address) {
        return address(s_safeHarborRegistry);
    }

    function getAuthorizedOwner(address contractAddress) external view returns (address) {
        return s_authorizedOwner[contractAddress];
    }

    function getAgreementFactory() external view returns (address) {
        return address(s_agreementFactory);
    }

    function getBattleChainDeployer() external view returns (address) {
        return s_battleChainDeployer;
    }

    function version() external pure returns (string memory) {
        return VERSION;
    }

    /// @notice Persists computed PRODUCTION state to storage
    /// @dev Time-based transitions (deadline auto-promotion, promotion delay) are computed
    ///      in _getAgreementState but not stored. Call this before upgrades to ensure
    ///      state survives changes to _getAgreementState logic. Permissionless — only
    ///      materializes state that is already true.
    /// @dev Event-ordering note: re-linking via `_revertIfLinkedToActiveAgreement` consults the
    ///      computed state, so a contract can be re-linked to a new agreement *before*
    ///      `finalizeState` is called for the prior one. If `finalizeState` is then called
    ///      later, `AgreementStateChanged(agreement, PRODUCTION)` will be emitted *after*
    ///      `ContractRegistered(contract, newAgreement)`. Off-chain consumers reconstructing
    ///      "which agreement governed contract X at production time" should reconcile against
    ///      direct state reads (`getAgreementInfo`, `getAgreementState`) rather than relying on
    ///      pure event-stream ordering. Operators that care about clean event order should call
    ///      `finalizeState` for the prior agreement before allowing any re-link.
    /// @param agreementAddress The agreement to finalize
    function finalizeState(address agreementAddress) external {
        AgreementInfo storage info = s_agreementInfo[agreementAddress];
        if (!info.isRegistered) return;
        if (info.promoted || info.corrupted) return;

        ContractState state = _getAgreementState(agreementAddress);
        if (state == ContractState.PRODUCTION) {
            info.promoted = true;
            // Clear the timestamp now that an explicit terminal transition has occurred.
        // See `AgreementInfo.promotionRequestedTimestamp` in IAttackRegistry for the
        // (more nuanced) semantics of this field.
            info.promotionRequestedTimestamp = 0;
            emit AgreementStateChanged(agreementAddress, ContractState.PRODUCTION);
            _markBondClaimable(agreementAddress);
        }
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Validate agreement and prepare for registration
    /// @return agreementOwner The owner of the agreement
    /// @return contracts The contracts in the agreement's scope
    // aderyn-ignore-next-line(reentrancy-state-change)
    function _validateAndPrepareAgreement(address agreementAddress)
        internal
        view
        returns (address agreementOwner, address[] memory contracts)
    {
        // Verify agreement was created by our factory
        // aderyn-ignore-next-line(reentrancy-state-change)
        if (!s_agreementFactory.isAgreementContract(agreementAddress)) {
            revert AttackRegistry__InvalidAgreement(agreementAddress);
        }

        // Check agreement is not already registered
        if (s_agreementInfo[agreementAddress].isRegistered) {
            revert AttackRegistry__InvalidState(_getAgreementState(agreementAddress));
        }

        IAgreement agreement = IAgreement(agreementAddress);
        // aderyn-ignore-next-line(reentrancy-state-change)
        agreementOwner = agreement.owner();

        // Only the agreement owner can call this
        if (msg.sender != agreementOwner) {
            revert AttackRegistry__NotAgreementOwner(msg.sender, agreementOwner);
        }

        // Get all contracts in the agreement's BattleChain scope
        // aderyn-ignore-next-line(reentrancy-state-change)
        contracts = agreement.getBattleChainScopeAddresses();
        if (contracts.length == 0) {
            revert AttackRegistry__EmptyContractArray();
        }

        // Verify commitment window for the agreement
        // aderyn-ignore-next-line(reentrancy-state-change)
        uint256 cantChangeUntil = agreement.getCantChangeUntil();
        uint256 minRequired = block.timestamp + MIN_COMMITMENT;
        if (cantChangeUntil < minRequired) {
            revert AttackRegistry__InsufficientCommitment(minRequired, cantChangeUntil);
        }

        // Validate contracts are not linked to another active agreement
        uint256 length = contracts.length;
        // aderyn-ignore-next-line(require-revert-in-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            _revertIfLinkedToActiveAgreement(contracts[i]);
        }
    }

    /// @notice Register an agreement and link contracts
    function _registerAgreement(address agreementAddress, address agreementOwner, address[] memory contracts) internal {
        uint256 length = contracts.length;

        // Link all contracts to this agreement
        // aderyn-ignore-next-line(costly-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            s_contractToAgreement[contracts[i]] = agreementAddress;
            emit ContractRegistered(contracts[i], agreementAddress);
        }

        // Create agreement info
        s_agreementInfo[agreementAddress] = AgreementInfo({
            attackModerator: agreementOwner,
            deadlineTimestamp: block.timestamp + PROMOTION_WINDOW,
            promotionRequestedTimestamp: 0,
            attackRequested: true,
            attackApproved: false,
            promoted: false,
            corrupted: false,
            isRegistered: true
        });

        emit AgreementStateChanged(agreementAddress, ContractState.ATTACK_REQUESTED);
    }

    /// @dev Registers agreement and immediately promotes to production (skipping attack phase)
    function _registerAgreementAndPromote(
        address agreementAddress,
        address agreementOwner,
        address[] memory contracts
    )
        internal
    {
        uint256 length = contracts.length;

        // Link all contracts to this agreement
        // aderyn-ignore-next-line(costly-loop,uninitialized-local-variable)
        for (uint256 i; i < length; ++i) {
            s_contractToAgreement[contracts[i]] = agreementAddress;
            emit ContractRegistered(contracts[i], agreementAddress);
        }

        // Create agreement info - directly in PRODUCTION state
        s_agreementInfo[agreementAddress] = AgreementInfo({
            attackModerator: agreementOwner,
            deadlineTimestamp: 0,
            promotionRequestedTimestamp: 0,
            attackRequested: false,
            attackApproved: false,
            promoted: true, // Directly promoted
            corrupted: false,
            isRegistered: true
        });

        emit AgreementStateChanged(agreementAddress, ContractState.PRODUCTION);
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Get the state of an agreement
    function _getAgreementState(address agreementAddress) internal view override returns (ContractState) {
        AgreementInfo storage info = s_agreementInfo[agreementAddress];

        // Check terminal states first
        if (info.corrupted) {
            return ContractState.CORRUPTED;
        }

        if (info.promoted) {
            return ContractState.PRODUCTION;
        }

        // If not registered, it's NOT_DEPLOYED
        if (!info.isRegistered) {
            return ContractState.NOT_DEPLOYED;
        }

        // Check if promotion was requested and delay has passed
        if (info.promotionRequestedTimestamp > 0) {
            if (block.timestamp >= info.promotionRequestedTimestamp + PROMOTION_DELAY) {
                return ContractState.PRODUCTION;
            }
            return ContractState.PROMOTION_REQUESTED;
        }

        if (info.attackApproved) {
            return ContractState.UNDER_ATTACK;
        }

        // Check deadline for auto-promotion
        if (block.timestamp >= info.deadlineTimestamp) {
            return ContractState.PRODUCTION;
        }

        if (info.attackRequested) {
            return ContractState.ATTACK_REQUESTED;
        }

        // Unreachable in the current public API: every registration path sets either
        // `attackRequested = true` (requestUnderAttack / requestUnderAttackForUnverifiedContracts)
        // or `promoted = true` (goToProduction), so a registered agreement with neither flag set
        // cannot exist. NEW_DEPLOYMENT is kept in the enum to avoid an ABI break for indexers.
        return ContractState.NEW_DEPLOYMENT;
    }

    /// @notice Validates ownership and links a contract to an agreement
    /// @dev BattleChainDeployer contracts require authorized owner match.
    ///      Unverified contracts emit UnverifiedContractSynced for DAO monitoring.
    function _validateAndLinkContract(
        address contractAddress,
        address agreementAddress,
        address agreementOwner
    )
        internal
    {
        if (s_contractDeployer[contractAddress] != address(0)) {
            if (s_authorizedOwner[contractAddress] != agreementOwner) {
                revert AttackRegistry__AgreementOwnerNotAuthorized(contractAddress, agreementOwner);
            }
        } else {
            emit UnverifiedContractSynced(contractAddress, agreementAddress);
        }

        s_contractToAgreement[contractAddress] = agreementAddress;
        emit ContractRegistered(contractAddress, agreementAddress);
    }

    /// @notice Reverts if a contract is linked to an agreement in an active attack state
    /// @dev Allows re-linking from terminal states (PRODUCTION, CORRUPTED) and NOT_DEPLOYED.
    ///      PRODUCTION re-linking is intentional — it enables the DAO griefing mitigation:
    ///      instantPromote moves a griefing agreement to PRODUCTION, freeing the contracts
    ///      for the legitimate owner to re-register.
    /// @dev This consults the *computed* state via `_getAgreementState`. For time-based
    ///      transitions (deadline auto-promote, promotion delay) the underlying
    ///      `info.promoted` flag may still be `false` and no `AgreementStateChanged(... PRODUCTION)`
    ///      event has been emitted. A re-link that happens before `finalizeState` is called will
    ///      emit `ContractRegistered` ahead of the agreement's PRODUCTION event in the log
    ///      stream. See `finalizeState` for off-chain reconstruction guidance.
    function _revertIfLinkedToActiveAgreement(address contractAddress) internal view {
        address existingAgreement = s_contractToAgreement[contractAddress];
        if (existingAgreement == address(0)) return;

        ContractState existingState = _getAgreementState(existingAgreement);
        if (
            existingState == ContractState.ATTACK_REQUESTED || existingState == ContractState.UNDER_ATTACK
                || existingState == ContractState.PROMOTION_REQUESTED
        ) {
            revert AttackRegistry__ContractAlreadyLinked(contractAddress, existingAgreement);
        }
    }
}
