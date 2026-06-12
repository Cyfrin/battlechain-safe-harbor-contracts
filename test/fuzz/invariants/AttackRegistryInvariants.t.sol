// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { AttackRegistryHandler, MockBattleChainDeployer } from "../handlers/AttackRegistryHandler.sol";
import { AttackRegistry } from "src/AttackRegistry.sol";
import { AgreementFactory } from "src/AgreementFactory.sol";
import { Agreement } from "src/Agreement.sol";
import { BattleChainSafeHarborRegistry } from "src/BattleChainSafeHarborRegistry.sol";
import { IAttackRegistry } from "src/interface/IAttackRegistry.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DeployBattleChainSafeHarbor } from "script/Deploy.s.sol";
import { DeployAttackRegistry } from "script/DeployAttackRegistry.s.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title AttackRegistryInvariants
/// @notice Invariant tests for the AttackRegistry state machine
/// @dev Tests state machine invariants, data consistency, and access control properties
contract AttackRegistryInvariants is StdInvariant, Test {
    /*//////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    //////////////////////////////////////////////////////////////*/
    AttackRegistryHandler public handler;
    AttackRegistry public attackRegistry;
    AgreementFactory public agreementFactory;
    BattleChainSafeHarborRegistry public safeHarborRegistry;
    MockBattleChainDeployer public mockDeployer;

    /*//////////////////////////////////////////////////////////////
                            ACTORS
    //////////////////////////////////////////////////////////////*/
    address public owner;
    address public registryModerator;
    address public protocolDeployer;
    MockERC20 public bondToken;

    /*//////////////////////////////////////////////////////////////
                              SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        protocolDeployer = makeAddr("protocolDeployer");

        // Deploy HelperConfig and SafeHarbor contracts
        HelperConfig helperConfig = new HelperConfig();
        DeployBattleChainSafeHarbor safeHarborDeployer = new DeployBattleChainSafeHarbor();
        safeHarborDeployer.initialize(helperConfig);

        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getNetworkConfig();
        owner = networkConfig.owner;
        registryModerator = networkConfig.registryModerator;

        // Deploy SafeHarbor Registry
        safeHarborDeployer.deployRegistryImplementation();
        safeHarborRegistry = BattleChainSafeHarborRegistry(safeHarborDeployer.deployRegistryProxy());

        // Deploy AgreementFactory
        safeHarborDeployer.deployAgreementFactoryImplementation();
        agreementFactory = AgreementFactory(safeHarborDeployer.deployAgreementFactoryProxy());

        // Deploy AttackRegistry
        DeployAttackRegistry attackRegistryDeployer = new DeployAttackRegistry();
        attackRegistryDeployer.initialize(helperConfig);
        attackRegistryDeployer.deployAttackRegistryImplementation();

        // Pre-compute deterministic proxy address (CREATE3) so MockBattleChainDeployer can reference it
        (, address expectedProxy,) = attackRegistryDeployer.computeExpectedAddresses(networkConfig.deployer);

        // Deploy MockBattleChainDeployer with the pre-computed proxy address
        mockDeployer = new MockBattleChainDeployer(expectedProxy);

        // Set mock deployer on the deploy script so it's included in initialize
        attackRegistryDeployer.setBattleChainDeployerAddress(address(mockDeployer));

        // Deploy AttackRegistry Proxy (initialize wires up mockDeployer)
        attackRegistry = AttackRegistry(
            attackRegistryDeployer.deployAttackRegistryProxy(address(safeHarborRegistry), address(agreementFactory))
        );

        // Configure bond system
        bondToken = new MockERC20();
        vm.startPrank(owner);
        attackRegistry.setBondToken(address(bondToken));
        attackRegistry.setFeeAmount(100e18);
        attackRegistry.setVerifiedBondAmount(500e18);
        attackRegistry.setUnverifiedBondAmount(1000e18);
        attackRegistry.setTreasury(makeAddr("treasury"));
        vm.stopPrank();

        // Fund protocolDeployer with bond tokens
        bondToken.mint(protocolDeployer, 100_000_000e18);
        vm.prank(protocolDeployer);
        bondToken.approve(address(attackRegistry), type(uint256).max);

        // Deploy handler
        handler = new AttackRegistryHandler(
            attackRegistry,
            agreementFactory,
            safeHarborRegistry,
            mockDeployer,
            owner,
            registryModerator,
            protocolDeployer,
            helperConfig.getBattleChainCaip2ChainId()
        );

        // Target the handler for invariant testing
        targetContract(address(handler));

        // Label addresses for better trace output
        vm.label(address(handler), "Handler");
        vm.label(address(attackRegistry), "AttackRegistry");
        vm.label(address(agreementFactory), "AgreementFactory");
        vm.label(address(safeHarborRegistry), "SafeHarborRegistry");
        vm.label(address(mockDeployer), "MockDeployer");
        vm.label(owner, "Owner");
        vm.label(registryModerator, "RegistryModerator");
        vm.label(protocolDeployer, "ProtocolDeployer");
    }

    /*//////////////////////////////////////////////////////////////
                    STATE MACHINE INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice SM-1: Terminal states (CORRUPTED, PRODUCTION) are permanent
    /// @dev Once an agreement reaches CORRUPTED or PRODUCTION, it can never leave
    function statefulFuzz_terminalStatesArePermanent() public view {
        uint256 length = handler.registeredAgreementsLength();
        for (uint256 i = 0; i < length; i++) {
            address agreementAddr = handler.registeredAgreements(i);

            // If ever marked corrupted, must still be corrupted
            if (handler.wasEverCorrupted(agreementAddr)) {
                IAttackRegistry.AgreementInfo memory info = attackRegistry.getAgreementInfo(agreementAddr);
                assertTrue(info.corrupted, "SM-1: Agreement was corrupted but corrupted flag is now false");
                assertEq(
                    uint256(attackRegistry.getAgreementState(agreementAddr)),
                    uint256(IAttackRegistry.ContractState.CORRUPTED),
                    "SM-1: Agreement was corrupted but state is not CORRUPTED"
                );
            }

            // If ever promoted (explicitly), promoted flag should be set
            // Note: Auto-promotion via time doesn't set the promoted flag but still results in PRODUCTION state
            if (handler.wasEverPromoted(agreementAddr)) {
                IAttackRegistry.ContractState state = attackRegistry.getAgreementState(agreementAddr);
                assertTrue(
                    state == IAttackRegistry.ContractState.PRODUCTION,
                    "SM-1: Agreement was promoted but state is not PRODUCTION"
                );
            }
        }
    }

    /// @notice SM-3: No state regression - agreements cannot move backwards in the state machine
    /// @dev Current state must be >= highest state ever reached (accounting for state ordering)
    function statefulFuzz_noStateRegression() public view {
        uint256 length = handler.registeredAgreementsLength();
        for (uint256 i = 0; i < length; i++) {
            address agreementAddr = handler.registeredAgreements(i);
            IAttackRegistry.ContractState currentState = attackRegistry.getAgreementState(agreementAddr);
            IAttackRegistry.ContractState highestState = handler.getHighestStateReached(agreementAddr);

            // Special cases for valid "backwards" transitions:
            // 1. ATTACK_REQUESTED -> NOT_DEPLOYED (via rejectAttackRequest)
            // 2. PROMOTION_REQUESTED -> UNDER_ATTACK (via cancelPromotion)
            // These are handled in the handler by resetting highestStateReached appropriately

            // For terminal states, the check is absolute
            if (highestState == IAttackRegistry.ContractState.CORRUPTED) {
                assertEq(
                    uint256(currentState),
                    uint256(IAttackRegistry.ContractState.CORRUPTED),
                    "SM-3: State regressed from CORRUPTED"
                );
            }
            if (highestState == IAttackRegistry.ContractState.PRODUCTION) {
                assertEq(
                    uint256(currentState),
                    uint256(IAttackRegistry.ContractState.PRODUCTION),
                    "SM-3: State regressed from PRODUCTION"
                );
            }
        }
    }

    /// @notice SM-4: Promotion delay is enforced (3 days must pass)
    /// @dev When in PROMOTION_REQUESTED, the timestamp must be set and delay must be respected
    function statefulFuzz_promotionDelayEnforced() public view {
        uint256 length = handler.registeredAgreementsLength();
        for (uint256 i = 0; i < length; i++) {
            address agreementAddr = handler.registeredAgreements(i);
            IAttackRegistry.AgreementInfo memory info = attackRegistry.getAgreementInfo(agreementAddr);
            IAttackRegistry.ContractState state = attackRegistry.getAgreementState(agreementAddr);

            // If in PROMOTION_REQUESTED state, timestamp must be set and 3 days haven't passed
            if (state == IAttackRegistry.ContractState.PROMOTION_REQUESTED) {
                assertTrue(info.promotionRequestedTimestamp > 0, "SM-4: PROMOTION_REQUESTED but no timestamp set");
                assertTrue(
                    block.timestamp < info.promotionRequestedTimestamp + attackRegistry.PROMOTION_DELAY(),
                    "SM-4: Should be PRODUCTION if 3 days passed"
                );
            }

            // If promotionRequestedTimestamp is set and 3 days have passed, must be PRODUCTION or CORRUPTED
            if (info.promotionRequestedTimestamp > 0 && !info.corrupted) {
                if (block.timestamp >= info.promotionRequestedTimestamp + attackRegistry.PROMOTION_DELAY()) {
                    assertEq(
                        uint256(state),
                        uint256(IAttackRegistry.ContractState.PRODUCTION),
                        "SM-4: Promotion delay passed but not in PRODUCTION"
                    );
                }
            }
        }
    }

    /// @notice SM-5: Deadline auto-promotion (14 days) is enforced
    /// @dev After deadline, agreement auto-promotes to PRODUCTION only if NOT yet approved for attack.
    ///      Once attackApproved=true (UNDER_ATTACK), the deadline check is bypassed in the contract.
    function statefulFuzz_deadlineAutoPromotion() public view {
        uint256 length = handler.registeredAgreementsLength();
        for (uint256 i = 0; i < length; i++) {
            address agreementAddr = handler.registeredAgreements(i);
            IAttackRegistry.AgreementInfo memory info = attackRegistry.getAgreementInfo(agreementAddr);
            IAttackRegistry.ContractState state = attackRegistry.getAgreementState(agreementAddr);

            // Deadline auto-promotion only applies when:
            // - isRegistered = true
            // - attackApproved = false (once approved, deadline is bypassed)
            // - promotionRequestedTimestamp = 0 (no explicit promotion request pending)
            // - corrupted = false
            // - promoted = false
            if (
                info.isRegistered && info.deadlineTimestamp > 0 && !info.corrupted && !info.promoted
                    && !info.attackApproved && info.promotionRequestedTimestamp == 0
            ) {
                if (block.timestamp >= info.deadlineTimestamp) {
                    // In this scenario, should be PRODUCTION
                    assertEq(
                        uint256(state),
                        uint256(IAttackRegistry.ContractState.PRODUCTION),
                        "SM-5: Deadline passed but not in PRODUCTION"
                    );
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    DATA CONSISTENCY INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice DC-1: A top-level contract can only be linked to ONE agreement at a time
    /// @dev If contract->agreement mapping exists, no other agreement should claim this contract
    function statefulFuzz_singleAgreementPerContract() public view {
        uint256 contractLength = handler.deployedContractsLength();
        uint256 agreementLength = handler.registeredAgreementsLength();

        for (uint256 i = 0; i < contractLength; i++) {
            address contractAddr = handler.deployedContracts(i);
            address linkedAgreement = attackRegistry.getAgreementForContract(contractAddr);

            if (linkedAgreement != address(0)) {
                // Count how many agreements claim this contract
                uint256 claimCount = 0;
                for (uint256 j = 0; j < agreementLength; j++) {
                    address agreementAddr = handler.registeredAgreements(j);
                    Agreement agreement = Agreement(agreementAddr);

                    // Check if this contract is in the agreement's scope
                    if (agreement.isContractInScope(contractAddr)) {
                        // If in scope and agreement is linked, count it
                        if (attackRegistry.getAgreementForContract(contractAddr) == agreementAddr) {
                            claimCount++;
                        }
                    }
                }
                assertTrue(claimCount <= 1, "DC-1: Contract linked to multiple agreements");
            }
        }
    }

    /// @notice DC-2: Contract-Agreement mapping is bidirectional
    /// @dev If contract maps to agreement, contract must be in agreement's scope
    function statefulFuzz_contractAgreementBidirectional() public view {
        uint256 contractLength = handler.deployedContractsLength();

        for (uint256 i = 0; i < contractLength; i++) {
            address contractAddr = handler.deployedContracts(i);
            address linkedAgreement = attackRegistry.getAgreementForContract(contractAddr);

            if (linkedAgreement != address(0)) {
                // Verify the contract is in the agreement's BattleChain scope
                Agreement agreement = Agreement(linkedAgreement);
                assertTrue(
                    agreement.isContractInScope(contractAddr), "DC-2: Contract linked to agreement but not in scope"
                );
            }
        }
    }

    /// @notice DC-3: Registered agreements have required fields initialized
    /// @dev If isRegistered=true, attackModerator must be set
    function statefulFuzz_registeredAgreementComplete() public view {
        uint256 length = handler.registeredAgreementsLength();
        for (uint256 i = 0; i < length; i++) {
            address agreementAddr = handler.registeredAgreements(i);
            IAttackRegistry.AgreementInfo memory info = attackRegistry.getAgreementInfo(agreementAddr);

            if (info.isRegistered) {
                // Attack moderator must be set for registered agreements
                assertTrue(info.attackModerator != address(0), "DC-3: Registered agreement has no attack moderator");
            }
        }
    }

    /// @notice DC-4: Deployer-AuthorizedOwner consistency
    /// @dev If s_contractDeployer is set, s_authorizedOwner must also be set
    function statefulFuzz_deployerAuthorizedOwnerConsistency() public view {
        uint256 length = handler.deployedContractsLength();
        for (uint256 i = 0; i < length; i++) {
            address contractAddr = handler.deployedContracts(i);

            address deployer = attackRegistry.getContractDeployer(contractAddr);
            address authorizedOwner = attackRegistry.getAuthorizedOwner(contractAddr);

            if (deployer != address(0)) {
                assertTrue(authorizedOwner != address(0), "DC-4: Deployer set but no authorized owner");
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    GETTERS DON'T REVERT INVARIANT
    //////////////////////////////////////////////////////////////*/

    /// @notice Getter functions should never revert for any valid input
    function statefulFuzz_gettersDontRevert() public view {
        uint256 agreementLength = handler.registeredAgreementsLength();
        uint256 contractLength = handler.deployedContractsLength();

        // Test agreement getters
        for (uint256 i = 0; i < agreementLength; i++) {
            address agreementAddr = handler.registeredAgreements(i);

            // These should never revert
            attackRegistry.getAgreementState(agreementAddr);
            attackRegistry.getAttackModerator(agreementAddr);
            attackRegistry.getAgreementInfo(agreementAddr);
        }

        // Test contract getters
        for (uint256 i = 0; i < contractLength; i++) {
            address contractAddr = handler.deployedContracts(i);

            // These should never revert
            attackRegistry.getAgreementForContract(contractAddr);
            attackRegistry.getContractDeployer(contractAddr);
            attackRegistry.getAuthorizedOwner(contractAddr);
            attackRegistry.isTopLevelContractUnderAttack(contractAddr);
        }

        // Global getters
        attackRegistry.getRegistryModerator();
        attackRegistry.getSafeHarborRegistry();
        attackRegistry.getAgreementFactory();
        attackRegistry.getBattleChainDeployer();
        attackRegistry.version();
    }

    /*//////////////////////////////////////////////////////////////
                    AGREEMENT STATE CONSISTENCY
    //////////////////////////////////////////////////////////////*/

    /// @notice Agreement state must be consistent with its info flags
    /// @dev Validates that state returned by getAgreementState matches the underlying data
    ///      following the exact priority order from _getAgreementState:
    ///      1. corrupted -> CORRUPTED
    ///      2. promoted -> PRODUCTION
    ///      3. !isRegistered -> NOT_DEPLOYED
    ///      4. promotionRequestedTimestamp + delay passed -> PRODUCTION
    ///      5. promotionRequestedTimestamp set -> PROMOTION_REQUESTED
    ///      6. attackApproved -> UNDER_ATTACK
    ///      7. deadline passed -> PRODUCTION
    ///      8. attackRequested -> ATTACK_REQUESTED
    ///      9. else -> NEW_DEPLOYMENT
    function statefulFuzz_stateConsistentWithInfo() public view {
        uint256 length = handler.registeredAgreementsLength();
        for (uint256 i = 0; i < length; i++) {
            address agreementAddr = handler.registeredAgreements(i);
            IAttackRegistry.AgreementInfo memory info = attackRegistry.getAgreementInfo(agreementAddr);
            IAttackRegistry.ContractState state = attackRegistry.getAgreementState(agreementAddr);

            // 1. CORRUPTED takes precedence over everything
            if (info.corrupted) {
                assertEq(
                    uint256(state),
                    uint256(IAttackRegistry.ContractState.CORRUPTED),
                    "State should be CORRUPTED when corrupted flag is true"
                );
                continue;
            }

            // 2. PRODUCTION (via promoted flag) takes precedence over other non-terminal states
            if (info.promoted) {
                assertEq(
                    uint256(state),
                    uint256(IAttackRegistry.ContractState.PRODUCTION),
                    "State should be PRODUCTION when promoted flag is true"
                );
                continue;
            }

            // 3. If not registered, must be NOT_DEPLOYED
            if (!info.isRegistered) {
                assertEq(
                    uint256(state),
                    uint256(IAttackRegistry.ContractState.NOT_DEPLOYED),
                    "State should be NOT_DEPLOYED when not registered"
                );
                continue;
            }

            // 4 & 5. Check promotion timestamp
            if (info.promotionRequestedTimestamp > 0) {
                if (block.timestamp >= info.promotionRequestedTimestamp + attackRegistry.PROMOTION_DELAY()) {
                    assertEq(
                        uint256(state),
                        uint256(IAttackRegistry.ContractState.PRODUCTION),
                        "State should be PRODUCTION after promotion delay"
                    );
                } else {
                    assertEq(
                        uint256(state),
                        uint256(IAttackRegistry.ContractState.PROMOTION_REQUESTED),
                        "State should be PROMOTION_REQUESTED before delay passes"
                    );
                }
                continue;
            }

            // 6. If attackApproved, must be UNDER_ATTACK (deadline check is bypassed when approved)
            if (info.attackApproved) {
                assertEq(
                    uint256(state),
                    uint256(IAttackRegistry.ContractState.UNDER_ATTACK),
                    "State should be UNDER_ATTACK when attack is approved"
                );
                continue;
            }

            // 7. Check deadline (only reached if attackApproved is false)
            if (info.deadlineTimestamp > 0 && block.timestamp >= info.deadlineTimestamp) {
                assertEq(
                    uint256(state),
                    uint256(IAttackRegistry.ContractState.PRODUCTION),
                    "State should be PRODUCTION after deadline (when not approved)"
                );
                continue;
            }

            // 8. If attackRequested, must be ATTACK_REQUESTED
            if (info.attackRequested) {
                assertEq(
                    uint256(state),
                    uint256(IAttackRegistry.ContractState.ATTACK_REQUESTED),
                    "State should be ATTACK_REQUESTED when attack is requested"
                );
                continue;
            }

            // 9. If registered but nothing else, should be NEW_DEPLOYMENT
            // This state shouldn't normally be reached in practice
        }
    }

    /*//////////////////////////////////////////////////////////////
                    ISUNDERATTACK CONSISTENCY
    //////////////////////////////////////////////////////////////*/

    /// @notice isTopLevelContractUnderAttack must be consistent with agreement state
    function statefulFuzz_isUnderAttackConsistent() public view {
        uint256 length = handler.deployedContractsLength();
        for (uint256 i = 0; i < length; i++) {
            address contractAddr = handler.deployedContracts(i);
            bool isUnderAttack = attackRegistry.isTopLevelContractUnderAttack(contractAddr);

            address agreementAddr = attackRegistry.getAgreementForContract(contractAddr);

            if (agreementAddr == address(0)) {
                // No agreement linked, should not be under attack
                assertFalse(isUnderAttack, "Contract with no agreement should not be under attack");
            } else {
                IAttackRegistry.ContractState state = attackRegistry.getAgreementState(agreementAddr);

                // isUnderAttack should be true only for UNDER_ATTACK or PROMOTION_REQUESTED
                bool shouldBeUnderAttack =
                    (state == IAttackRegistry.ContractState.UNDER_ATTACK
                        || state == IAttackRegistry.ContractState.PROMOTION_REQUESTED);

                assertEq(isUnderAttack, shouldBeUnderAttack, "isUnderAttack inconsistent with agreement state");
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    BOND SOLVENCY INVARIANT
    //////////////////////////////////////////////////////////////*/

    /// @notice Bond solvency: registry balance >= totalClaimable
    /// @dev The registry must always hold enough bond tokens to cover all pending claimable deposits
    function statefulFuzz_bondSolvency() public view {
        address token = attackRegistry.getBondToken();
        if (token == address(0)) return;

        uint256 balance = IERC20(token).balanceOf(address(attackRegistry));
        uint256 reserved = attackRegistry.getReservedByToken(token);
        assertTrue(balance >= reserved, "BOND: Registry balance < reserved for token");
    }

    /*//////////////////////////////////////////////////////////////
                          CALL SUMMARY
    //////////////////////////////////////////////////////////////*/

    /// @notice Log call summary at the end of invariant tests
    function statefulFuzz_callSummary() public view {
        console2.log(handler.callSummary());
    }
}
