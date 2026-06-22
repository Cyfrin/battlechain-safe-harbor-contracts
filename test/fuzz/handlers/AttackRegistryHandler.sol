// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { CommonBase } from "forge-std/Base.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import {
    AgreementDetails,
    Contact,
    ChildContractScope,
    Account as BCAccount,
    Chain as BCChain,
    BountyTerms,
    IdentityRequirements
} from "src/types/AgreementTypes.sol";
import { Agreement } from "src/Agreement.sol";
import { AgreementFactory } from "src/AgreementFactory.sol";
import { AttackRegistry } from "src/AttackRegistry.sol";
import { IAttackRegistry } from "src/interface/IAttackRegistry.sol";
import { BondDeposit } from "src/types/AttackRegistryTypes.sol";
import { BattleChainSafeHarborRegistry } from "src/BattleChainSafeHarborRegistry.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Mock BattleChainDeployer that registers deployments with AttackRegistry
contract MockBattleChainDeployer {
    IAttackRegistry public immutable ATTACK_REGISTRY;

    constructor(address attackRegistry) {
        ATTACK_REGISTRY = IAttackRegistry(attackRegistry);
    }

    function deployAndRegister(address contractAddress, address deployer) external {
        ATTACK_REGISTRY.registerDeployment(contractAddress, deployer);
    }
}

/// @title AttackRegistryHandler
/// @notice Handler contract for invariant testing of AttackRegistry
/// @dev Provides bounded versions of all state-changing functions and tracks ghost state
contract AttackRegistryHandler is CommonBase, StdUtils {
    /*//////////////////////////////////////////////////////////////
                            PROTOCOL CONTRACTS
    //////////////////////////////////////////////////////////////*/
    AttackRegistry public attackRegistry;
    AgreementFactory public agreementFactory;
    BattleChainSafeHarborRegistry public safeHarborRegistry;
    MockBattleChainDeployer public mockDeployer;

    /*//////////////////////////////////////////////////////////////
                            ACTOR ADDRESSES
    //////////////////////////////////////////////////////////////*/
    address public owner;
    address public registryModerator;
    address public protocolDeployer;

    /*//////////////////////////////////////////////////////////////
                            TRACKING STATE
    //////////////////////////////////////////////////////////////*/
    /// @dev All registered agreements
    address[] public registeredAgreements;
    mapping(address => bool) public isRegisteredAgreement;

    /// @dev All deployed contracts (via BattleChainDeployer)
    address[] public deployedContracts;
    mapping(address => bool) public isDeployedContract;

    /// @dev Track highest state reached per agreement (for regression detection)
    mapping(address => IAttackRegistry.ContractState) public highestStateReached;

    /// @dev Track terminal flags that should never revert
    mapping(address => bool) public wasEverCorrupted;
    mapping(address => bool) public wasEverPromoted;

    /// @dev Track which agreement each contract belongs to
    mapping(address => address) public contractToAgreement;

    /*//////////////////////////////////////////////////////////////
                            CALL COUNTERS
    //////////////////////////////////////////////////////////////*/
    uint256 public deployCount;
    uint256 public authorizeOwnerCount;
    uint256 public createAgreementCount;
    uint256 public requestUnderAttackCount;
    uint256 public requestUnderAttackByNonAuthorizedCount;
    uint256 public approveAttackCount;
    uint256 public rejectAttackRequestCount;
    uint256 public promoteCount;
    uint256 public cancelPromotionCount;
    uint256 public markCorruptedCount;
    uint256 public instantPromoteCount;
    uint256 public goToProductionCount;
    uint256 public transferAttackModeratorCount;
    uint256 public warpTimeCount;
    uint256 public addContractToScopeCount;
    uint256 public syncNewContractsCount;
    uint256 public claimBondCount;

    /*//////////////////////////////////////////////////////////////
                        BOND GHOST VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev Total bond tokens deposited into the registry
    uint256 public ghost_totalDeposited;
    /// @dev Total bond tokens claimed back from the registry
    uint256 public ghost_totalClaimed;

    /*//////////////////////////////////////////////////////////////
                            INTERNAL STATE
    //////////////////////////////////////////////////////////////*/
    uint256 private contractCounter;
    string private battleChainCaip2;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        AttackRegistry _attackRegistry,
        AgreementFactory _agreementFactory,
        BattleChainSafeHarborRegistry _safeHarborRegistry,
        MockBattleChainDeployer _mockDeployer,
        address _owner,
        address _registryModerator,
        address _protocolDeployer,
        string memory _battleChainCaip2
    ) {
        attackRegistry = _attackRegistry;
        agreementFactory = _agreementFactory;
        safeHarborRegistry = _safeHarborRegistry;
        mockDeployer = _mockDeployer;
        owner = _owner;
        registryModerator = _registryModerator;
        protocolDeployer = _protocolDeployer;
        battleChainCaip2 = _battleChainCaip2;
    }

    /*//////////////////////////////////////////////////////////////
                          HANDLER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new contract via BattleChainDeployer
    function deployContract(uint256 /* saltSeed */ ) external {
        deployCount++;

        // Generate unique contract address
        contractCounter++;
        address newContract = address(uint160(0x1000 + contractCounter));

        // Register via mock deployer
        vm.prank(address(mockDeployer));
        attackRegistry.registerDeployment(newContract, protocolDeployer);

        // Track deployed contract
        deployedContracts.push(newContract);
        isDeployedContract[newContract] = true;
    }

    /// @notice Authorize a new owner for a deployed contract
    function authorizeOwner(uint256 contractSeed, address newOwner) external {
        if (deployedContracts.length == 0) return;
        if (newOwner == address(0)) return;

        authorizeOwnerCount++;

        uint256 idx = contractSeed % deployedContracts.length;
        address contractAddr = deployedContracts[idx];

        address currentOwner = attackRegistry.getAuthorizedOwner(contractAddr);
        if (currentOwner == address(0)) return;

        vm.prank(currentOwner);
        try attackRegistry.authorizeAgreementOwner(contractAddr, newOwner) {
            // Success
        } catch {
            // Expected failure cases
        }
    }

    /// @notice Create a new agreement with deployed contracts
    function createAgreement(uint256 contractSeed) external {
        if (deployedContracts.length == 0) return;

        createAgreementCount++;

        // Select 1-3 contracts for the agreement
        uint256 numContracts = (contractSeed % 3) + 1;
        if (numContracts > deployedContracts.length) {
            numContracts = deployedContracts.length;
        }

        address[] memory contracts = new address[](numContracts);
        for (uint256 i = 0; i < numContracts; i++) {
            uint256 idx = (contractSeed + i) % deployedContracts.length;
            contracts[i] = deployedContracts[idx];
        }

        // Create agreement
        Agreement newAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // Track agreement
        registeredAgreements.push(address(newAgreement));
        isRegisteredAgreement[address(newAgreement)] = true;

        // Track contract->agreement mapping
        for (uint256 i = 0; i < numContracts; i++) {
            contractToAgreement[contracts[i]] = address(newAgreement);
        }
    }

    /// @notice Request attack mode for an agreement (authorized path)
    function requestUnderAttack(uint256 agreementSeed) external {
        if (registeredAgreements.length == 0) return;

        requestUnderAttackCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        IAttackRegistry.ContractState currentState = attackRegistry.getAgreementState(agreementAddr);

        // Only valid from NOT_DEPLOYED state
        if (currentState != IAttackRegistry.ContractState.NOT_DEPLOYED) return;

        uint256 balBefore = _bondTokenBalance();
        vm.prank(protocolDeployer);
        try attackRegistry.requestUnderAttack(agreementAddr) {
            _updateHighestState(agreementAddr, IAttackRegistry.ContractState.ATTACK_REQUESTED);
            ghost_totalDeposited += balBefore - _bondTokenBalance();
        } catch {
            // Expected failure cases (authorization, commitment, etc.)
        }
    }

    /// @notice Request attack mode for external contracts (non-authorized path)
    function requestUnderAttackByNonAuthorized(uint256 agreementSeed) external {
        if (registeredAgreements.length == 0) return;

        requestUnderAttackByNonAuthorizedCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        IAttackRegistry.ContractState currentState = attackRegistry.getAgreementState(agreementAddr);

        // Only valid from NOT_DEPLOYED state
        if (currentState != IAttackRegistry.ContractState.NOT_DEPLOYED) return;

        uint256 balBefore = _bondTokenBalance();
        vm.prank(protocolDeployer);
        try attackRegistry.requestUnderAttackByNonAuthorized(agreementAddr) {
            _updateHighestState(agreementAddr, IAttackRegistry.ContractState.ATTACK_REQUESTED);
            ghost_totalDeposited += balBefore - _bondTokenBalance();
        } catch {
            // Expected failure cases
        }
    }

    /// @notice DAO approves an attack request
    function approveAttack(uint256 agreementSeed) external {
        if (registeredAgreements.length == 0) return;

        approveAttackCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        IAttackRegistry.ContractState currentState = attackRegistry.getAgreementState(agreementAddr);

        // Only valid from ATTACK_REQUESTED state
        if (currentState != IAttackRegistry.ContractState.ATTACK_REQUESTED) return;

        vm.prank(registryModerator);
        try attackRegistry.approveAttack(agreementAddr) {
            _updateHighestState(agreementAddr, IAttackRegistry.ContractState.UNDER_ATTACK);
        } catch {
            // Unexpected failure
        }
    }

    /// @notice DAO rejects an attack request
    function rejectAttackRequest(uint256 agreementSeed, bool slashBond) external {
        if (registeredAgreements.length == 0) return;

        rejectAttackRequestCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        IAttackRegistry.ContractState currentState = attackRegistry.getAgreementState(agreementAddr);

        // Only valid from ATTACK_REQUESTED state
        if (currentState != IAttackRegistry.ContractState.ATTACK_REQUESTED) return;

        vm.prank(registryModerator);
        try attackRegistry.rejectAttackRequest(agreementAddr, slashBond) {
            // Reset state tracking since agreement was rejected
            highestStateReached[agreementAddr] = IAttackRegistry.ContractState.NOT_DEPLOYED;
        } catch {
            // Unexpected failure
        }
    }

    /// @notice Attack moderator requests promotion
    function promote(uint256 agreementSeed) external {
        if (registeredAgreements.length == 0) return;

        promoteCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        IAttackRegistry.ContractState currentState = attackRegistry.getAgreementState(agreementAddr);

        // Only valid from UNDER_ATTACK state
        if (currentState != IAttackRegistry.ContractState.UNDER_ATTACK) return;

        address attackModerator = attackRegistry.getAttackModerator(agreementAddr);

        vm.prank(attackModerator);
        try attackRegistry.promote(agreementAddr) {
            _updateHighestState(agreementAddr, IAttackRegistry.ContractState.PROMOTION_REQUESTED);
        } catch {
            // Unexpected failure
        }
    }

    /// @notice Attack moderator cancels promotion
    function cancelPromotion(uint256 agreementSeed) external {
        if (registeredAgreements.length == 0) return;

        cancelPromotionCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        IAttackRegistry.ContractState currentState = attackRegistry.getAgreementState(agreementAddr);

        // Only valid from PROMOTION_REQUESTED state (and before 3 days pass)
        if (currentState != IAttackRegistry.ContractState.PROMOTION_REQUESTED) return;

        address attackModerator = attackRegistry.getAttackModerator(agreementAddr);

        vm.prank(attackModerator);
        try attackRegistry.cancelPromotion(agreementAddr) {
            // State goes back to UNDER_ATTACK (which is <= PROMOTION_REQUESTED, so no update needed)
        } catch {
            // Expected if 3 days have passed and state is now PRODUCTION
        }
    }

    /// @notice Attack moderator marks agreement as corrupted
    function markCorrupted(uint256 agreementSeed) external {
        if (registeredAgreements.length == 0) return;

        markCorruptedCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        IAttackRegistry.ContractState currentState = attackRegistry.getAgreementState(agreementAddr);

        // Only valid from UNDER_ATTACK or PROMOTION_REQUESTED state
        if (
            currentState != IAttackRegistry.ContractState.UNDER_ATTACK
                && currentState != IAttackRegistry.ContractState.PROMOTION_REQUESTED
        ) return;

        address attackModerator = attackRegistry.getAttackModerator(agreementAddr);

        vm.prank(attackModerator);
        try attackRegistry.markCorrupted(agreementAddr) {
            wasEverCorrupted[agreementAddr] = true;
            _updateHighestState(agreementAddr, IAttackRegistry.ContractState.CORRUPTED);
        } catch {
            // Unexpected failure
        }
    }

    /// @notice DAO instantly promotes an agreement
    function instantPromote(uint256 agreementSeed) external {
        if (registeredAgreements.length == 0) return;

        instantPromoteCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        IAttackRegistry.ContractState currentState = attackRegistry.getAgreementState(agreementAddr);

        // Valid from ATTACK_REQUESTED, UNDER_ATTACK, or PROMOTION_REQUESTED
        if (
            currentState != IAttackRegistry.ContractState.ATTACK_REQUESTED
                && currentState != IAttackRegistry.ContractState.UNDER_ATTACK
                && currentState != IAttackRegistry.ContractState.PROMOTION_REQUESTED
        ) return;

        vm.prank(registryModerator);
        try attackRegistry.instantPromote(agreementAddr) {
            wasEverPromoted[agreementAddr] = true;
            _updateHighestState(agreementAddr, IAttackRegistry.ContractState.PRODUCTION);
        } catch {
            // Unexpected failure
        }
    }

    /// @notice Skip attack mode and go directly to production
    function goToProduction(uint256 agreementSeed) external {
        if (registeredAgreements.length == 0) return;

        goToProductionCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        IAttackRegistry.ContractState currentState = attackRegistry.getAgreementState(agreementAddr);

        // Only valid from NOT_DEPLOYED state
        if (currentState != IAttackRegistry.ContractState.NOT_DEPLOYED) return;

        vm.prank(protocolDeployer);
        try attackRegistry.goToProduction(agreementAddr) {
            wasEverPromoted[agreementAddr] = true;
            _updateHighestState(agreementAddr, IAttackRegistry.ContractState.PRODUCTION);
        } catch {
            // Expected failure cases (authorization, commitment, etc.)
        }
    }

    /// @notice Transfer attack moderator role
    function transferAttackModerator(uint256 agreementSeed, address newModerator) external {
        if (registeredAgreements.length == 0) return;
        if (newModerator == address(0)) return;

        transferAttackModeratorCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        address currentModerator = attackRegistry.getAttackModerator(agreementAddr);
        if (currentModerator == address(0)) return;

        vm.prank(currentModerator);
        try attackRegistry.transferAttackModerator(agreementAddr, newModerator) {
            // Success
        } catch {
            // Expected failure cases
        }
    }

    /// @notice Warp time forward (bounded to reasonable values)
    function warpTime(uint256 secondsToWarp) external {
        warpTimeCount++;

        // Bound to max 30 days to keep tests reasonable
        uint256 boundedSeconds = secondsToWarp % (30 days);
        // Add minimum 1 second to ensure time always moves forward
        boundedSeconds = boundedSeconds + 1;

        vm.warp(block.timestamp + boundedSeconds);

        // Update ghost state for any agreements that auto-promoted via time
        _updateAllAgreementStates();
    }

    /// @notice Add a new contract to an existing agreement's scope (triggers auto-sync)
    function addContractToScope(uint256 agreementSeed) external {
        if (registeredAgreements.length == 0) return;
        if (deployedContracts.length == 0) return;

        addContractToScopeCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        IAttackRegistry.ContractState currentState = attackRegistry.getAgreementState(agreementAddr);
        // Only try when in active state
        if (
            currentState != IAttackRegistry.ContractState.UNDER_ATTACK
                && currentState != IAttackRegistry.ContractState.ATTACK_REQUESTED
        ) return;

        // Deploy a new contract and add to scope
        contractCounter++;
        address newContract = address(uint160(0x1000 + contractCounter));
        vm.prank(address(mockDeployer));
        attackRegistry.registerDeployment(newContract, protocolDeployer);
        deployedContracts.push(newContract);
        isDeployedContract[newContract] = true;

        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({
            accountAddress: _addressToString(newContract),
            childContractScope: ChildContractScope.None
        });

        vm.prank(protocolDeployer);
        try Agreement(agreementAddr).addAccounts(battleChainCaip2, accounts) {
            contractToAgreement[newContract] = agreementAddr;
        } catch {
            // Expected failure cases
        }
    }

    /// @notice Call syncNewContracts on an agreement
    function syncNewContracts(uint256 agreementSeed) external {
        if (registeredAgreements.length == 0) return;

        syncNewContractsCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        try attackRegistry.syncNewContracts(agreementAddr) {
            // Success
        } catch {
            // Expected failure cases
        }
    }

    /// @notice Attempt to claim a bond for an agreement
    function claimBond(uint256 agreementSeed) external {
        if (registeredAgreements.length == 0) return;

        claimBondCount++;

        uint256 idx = agreementSeed % registeredAgreements.length;
        address agreementAddr = registeredAgreements[idx];

        BondDeposit memory deposit = attackRegistry.getBondDeposit(agreementAddr);
        if (deposit.depositor == address(0)) return;
        if (deposit.claimed || deposit.slashed) return;

        uint256 balBefore = _bondTokenBalance();
        vm.prank(deposit.depositor);
        try attackRegistry.claimBond(agreementAddr) {
            ghost_totalClaimed += _bondTokenBalance() - balBefore;
        } catch {
            // Expected failure cases (not claimable yet, etc.)
        }
    }

    /*//////////////////////////////////////////////////////////////
                          GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function registeredAgreementsLength() external view returns (uint256) {
        return registeredAgreements.length;
    }

    function deployedContractsLength() external view returns (uint256) {
        return deployedContracts.length;
    }

    function getHighestStateReached(address agreementAddr) external view returns (IAttackRegistry.ContractState) {
        return highestStateReached[agreementAddr];
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get bond token balance of the attack registry (0 if no bond token set)
    function _bondTokenBalance() internal view returns (uint256) {
        address token = attackRegistry.getBondToken();
        if (token == address(0)) return 0;
        return IERC20(token).balanceOf(address(attackRegistry));
    }

    /// @notice Update highest state reached if new state is higher
    function _updateHighestState(address agreementAddr, IAttackRegistry.ContractState newState) internal {
        if (uint256(newState) > uint256(highestStateReached[agreementAddr])) {
            highestStateReached[agreementAddr] = newState;
        }
    }

    /// @notice Update ghost state for all agreements (handles time-based promotions)
    function _updateAllAgreementStates() internal {
        for (uint256 i = 0; i < registeredAgreements.length; i++) {
            address agreementAddr = registeredAgreements[i];
            IAttackRegistry.ContractState currentState = attackRegistry.getAgreementState(agreementAddr);

            // If state progressed due to time, update tracking
            if (currentState == IAttackRegistry.ContractState.PRODUCTION) {
                if (!wasEverPromoted[agreementAddr]) {
                    // Auto-promoted via deadline or promotion delay
                    wasEverPromoted[agreementAddr] = true;
                }
                _updateHighestState(agreementAddr, IAttackRegistry.ContractState.PRODUCTION);
            } else {
                _updateHighestState(agreementAddr, currentState);
            }
        }
    }

    /// @notice Creates an agreement with the given contracts in scope
    function _createAgreementWithContracts(address _owner, address[] memory contracts)
        internal
        returns (Agreement)
    {
        // Build accounts array from contracts
        BCAccount[] memory accounts = new BCAccount[](contracts.length);
        for (uint256 i = 0; i < contracts.length; i++) {
            accounts[i] = BCAccount({
                accountAddress: _addressToString(contracts[i]),
                childContractScope: ChildContractScope.None
            });
        }

        BCChain[] memory chains = new BCChain[](1);
        chains[0] = BCChain({
            accounts: accounts,
            assetRecoveryAddress: "0x0000000000000000000000000000000000000022",
            caip2ChainId: battleChainCaip2
        });

        Contact[] memory contacts = new Contact[](1);
        contacts[0] = Contact({ name: "Test", contact: "test@test.com" });

        BountyTerms memory bountyTerms = BountyTerms({
            bountyPercentage: 10,
            bountyCapUsd: 5_000_000,
            retainable: false,
            identity: IdentityRequirements.Anonymous,
            diligenceRequirements: "none",
            aggregateBountyCapUsd: 10_000_000
        });

        AgreementDetails memory details = AgreementDetails({
            protocolName: "Test Protocol",
            chains: chains,
            contactDetails: contacts,
            bountyTerms: bountyTerms,
            agreementURI: "ipfs://test"
        });

        // Use the factory to create agreement
        vm.prank(_owner);
        address agreementAddr =
            agreementFactory.create(details, _owner, keccak256(abi.encodePacked(_owner, contracts, block.timestamp)));
        Agreement newAgreement = Agreement(agreementAddr);

        // Extend commitment window to meet MIN_COMMITMENT (7 days)
        vm.prank(_owner);
        newAgreement.extendCommitmentWindow(block.timestamp + 30 days);

        return newAgreement;
    }

    /// @notice Converts an address to a lowercase hex string with 0x prefix
    function _addressToString(address addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i)) >> 4) & 0xf];
            str[3 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i))) & 0xf];
        }
        return string(str);
    }

    /*//////////////////////////////////////////////////////////////
                          CALL SUMMARY
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns a summary of all handler calls for debugging
    function callSummary() external view returns (string memory) {
        return string(
            abi.encodePacked(
                "Call Summary:\n",
                "  deployContract: ", _uint2str(deployCount), "\n",
                "  authorizeOwner: ", _uint2str(authorizeOwnerCount), "\n",
                "  createAgreement: ", _uint2str(createAgreementCount), "\n",
                "  requestUnderAttack: ", _uint2str(requestUnderAttackCount), "\n",
                "  requestUnderAttackByNonAuthorized: ", _uint2str(requestUnderAttackByNonAuthorizedCount), "\n",
                "  approveAttack: ", _uint2str(approveAttackCount), "\n",
                "  rejectAttackRequest: ", _uint2str(rejectAttackRequestCount), "\n",
                "  promote: ", _uint2str(promoteCount), "\n",
                "  cancelPromotion: ", _uint2str(cancelPromotionCount), "\n",
                "  markCorrupted: ", _uint2str(markCorruptedCount), "\n",
                "  instantPromote: ", _uint2str(instantPromoteCount), "\n",
                "  goToProduction: ", _uint2str(goToProductionCount), "\n",
                "  transferAttackModerator: ", _uint2str(transferAttackModeratorCount), "\n",
                "  warpTime: ", _uint2str(warpTimeCount), "\n",
                "  addContractToScope: ", _uint2str(addContractToScopeCount), "\n",
                "  syncNewContracts: ", _uint2str(syncNewContractsCount), "\n",
                "  claimBond: ", _uint2str(claimBondCount), "\n",
                "  Total Agreements: ", _uint2str(registeredAgreements.length), "\n",
                "  Total Contracts: ", _uint2str(deployedContracts.length)
            )
        );
    }

    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
