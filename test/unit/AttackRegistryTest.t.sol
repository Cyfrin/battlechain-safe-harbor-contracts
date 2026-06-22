// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import {
    AgreementDetails,
    Contact,
    ChildContractScope,
    Account as BCAccount,
    Chain as BCChain,
    BountyTerms
} from "src/types/AgreementTypes.sol";
import { Agreement } from "src/Agreement.sol";
import { AgreementFactory } from "src/AgreementFactory.sol";
import { AttackRegistry } from "src/AttackRegistry.sol";
import { IAttackRegistry } from "src/interface/IAttackRegistry.sol";
import { BondDeposit } from "src/types/AttackRegistryTypes.sol";
import { BattleChainSafeHarborRegistry } from "src/BattleChainSafeHarborRegistry.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DeployBattleChainSafeHarbor } from "script/Deploy.s.sol";
import { DeployAttackRegistry } from "script/DeployAttackRegistry.s.sol";
import { BattleChainDeployer } from "src/BattleChainDeployer.sol";
import { IdentityRequirements } from "src/types/AgreementTypes.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { OwnableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { BondManager } from "src/BondManager.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";

contract AttackRegistryTest is Test {
    address owner;
    address registryModerator;
    address treasury;
    string battleChainCaip2;
    address attacker;
    address protocolDeployer;
    address agreementOwner;

    MockERC20 bondToken;
    uint256 constant FEE_AMOUNT = 100e18;
    uint256 constant VERIFIED_BOND = 500e18;
    uint256 constant UNVERIFIED_BOND = 1000e18;

    AttackRegistry attackRegistry;
    BattleChainSafeHarborRegistry safeHarborRegistry;
    AgreementFactory agreementFactory;
    BattleChainDeployer battleChainDeployerContract;
    HelperConfig helperConfig;
    DeployBattleChainSafeHarbor safeHarborDeployer;
    DeployAttackRegistry attackRegistryDeployer;

    // Test contract addresses (will be deployed via BattleChainDeployer)
    address contract1;
    address contract2;
    address contract3;

    // Counter for unique contract addresses
    uint256 contractCounter;

    function setUp() public {
        attacker = makeAddr("attacker");
        protocolDeployer = makeAddr("protocolDeployer");
        agreementOwner = makeAddr("agreementOwner");

        // Deploy HelperConfig and SafeHarbor contracts
        helperConfig = new HelperConfig();
        safeHarborDeployer = new DeployBattleChainSafeHarbor();
        safeHarborDeployer.initialize(helperConfig);

        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getNetworkConfig();
        owner = networkConfig.owner;
        registryModerator = networkConfig.registryModerator;
        treasury = networkConfig.treasury;
        battleChainCaip2 = helperConfig.getBattleChainCaip2ChainId();

        // Deploy SafeHarbor Registry
        safeHarborDeployer.deployRegistryImplementation();
        safeHarborRegistry = BattleChainSafeHarborRegistry(safeHarborDeployer.deployRegistryProxy());

        // Deploy AgreementFactory
        safeHarborDeployer.deployAgreementFactoryImplementation();
        agreementFactory = AgreementFactory(safeHarborDeployer.deployAgreementFactoryProxy());

        // Deploy AttackRegistry using the deploy script
        attackRegistryDeployer = new DeployAttackRegistry();
        attackRegistryDeployer.initialize(helperConfig);
        attackRegistryDeployer.deployAttackRegistryImplementation();

        // Pre-compute deterministic proxy address (CREATE3) so BattleChainDeployer can reference it
        (, address expectedProxy,) = attackRegistryDeployer.computeExpectedAddresses(networkConfig.deployer);

        // Deploy BattleChainDeployer with the pre-computed proxy address
        battleChainDeployerContract =
            BattleChainDeployer(attackRegistryDeployer.deployBattleChainDeployer(expectedProxy));

        // Deploy AttackRegistry Proxy (initialize wires up BattleChainDeployer)
        attackRegistry = AttackRegistry(
            attackRegistryDeployer.deployAttackRegistryProxy(address(safeHarborRegistry), address(agreementFactory))
        );

        // Wire up AttackRegistry on SafeHarborRegistry so Agreement auto-sync works
        vm.prank(owner);
        safeHarborRegistry.setAttackRegistry(address(attackRegistry));

        // Deploy mock ERC20 and configure bond system
        bondToken = new MockERC20();
        vm.startPrank(owner);
        attackRegistry.setBondToken(address(bondToken));
        attackRegistry.setFeeAmount(FEE_AMOUNT);
        attackRegistry.setVerifiedBondAmount(VERIFIED_BOND);
        attackRegistry.setUnverifiedBondAmount(UNVERIFIED_BOND);
        vm.stopPrank();

        // Fund test actors with tokens and approve AttackRegistry
        _fundAndApprove(protocolDeployer, 1_000_000e18);
        _fundAndApprove(agreementOwner, 1_000_000e18);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Simulates deploying a contract via BattleChainDeployer (registers it automatically)
    function _deployContractViaBattleChain(
        address deployer,
        bytes32 /* salt */
    )
        internal
        returns (address)
    {
        // Generate unique contract address
        contractCounter++;
        address newContract = address(uint160(0x1000 + contractCounter));

        // Register via mock deployer (simulates BattleChainDeployer calling registerDeployment)
        vm.prank(address(battleChainDeployerContract));
        attackRegistry.registerDeployment(newContract, deployer);

        return newContract;
    }

    /// @dev Creates an agreement with the given contracts in scope (using factory for tracking)
    function _createAgreementWithContracts(address _owner, address[] memory contracts) internal returns (Agreement) {
        // Build accounts array from contracts
        BCAccount[] memory accounts = new BCAccount[](contracts.length);
        for (uint256 i = 0; i < contracts.length; i++) {
            accounts[i] = BCAccount({
                accountAddress: _addressToString(contracts[i]), childContractScope: ChildContractScope.None
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

        // Use the factory to create agreement (so it's tracked)
        vm.prank(_owner);
        address agreementAddr = agreementFactory.create(details, _owner, keccak256(abi.encodePacked(_owner, contracts)));
        Agreement newAgreement = Agreement(agreementAddr);

        // Extend commitment window to meet MIN_COMMITMENT (7 days)
        vm.prank(_owner);
        newAgreement.extendCommitmentWindow(block.timestamp + 30 days);

        return newAgreement;
    }

    /// @dev Mints bond tokens and approves the attack registry for the given caller
    function _fundAndApprove(address caller, uint256 amount) internal {
        bondToken.mint(caller, amount);
        vm.prank(caller);
        bondToken.approve(address(attackRegistry), amount);
    }

    /// @dev Converts an address to a lowercase hex string with 0x prefix
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
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testInitialization() public view {
        assertEq(attackRegistry.owner(), owner);
        assertEq(attackRegistry.getRegistryModerator(), registryModerator);
        assertEq(attackRegistry.getSafeHarborRegistry(), address(safeHarborRegistry));
        assertEq(attackRegistry.getAgreementFactory(), address(agreementFactory));
        assertEq(attackRegistry.getBattleChainDeployer(), address(battleChainDeployerContract));
    }

    function testInitializeRevertsWithZeroOwner() public {
        AttackRegistry impl = new AttackRegistry();
        bytes memory initData = abi.encodeWithSelector(
            AttackRegistry.initialize.selector,
            address(0),
            registryModerator,
            address(safeHarborRegistry),
            address(agreementFactory),
            address(battleChainDeployerContract),
            treasury
        );
        // Reverts via OZ's __Ownable_init (zero check now lives downstream)
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0))
        );
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeRevertsWithZeroTreasury() public {
        AttackRegistry impl = new AttackRegistry();
        bytes memory initData = abi.encodeWithSelector(
            AttackRegistry.initialize.selector,
            owner,
            registryModerator,
            address(safeHarborRegistry),
            address(agreementFactory),
            address(battleChainDeployerContract),
            address(0)
        );
        // Reverts via _setTreasury in BondManager (zero check now lives downstream)
        vm.expectRevert(BondManager.BondManager__ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeRevertsWithZeroModerator() public {
        AttackRegistry impl = new AttackRegistry();
        bytes memory initData = abi.encodeWithSelector(
            AttackRegistry.initialize.selector,
            owner,
            address(0),
            address(safeHarborRegistry),
            address(agreementFactory),
            address(battleChainDeployerContract),
            treasury
        );
        vm.expectRevert(AttackRegistry.AttackRegistry__ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeRevertsWithZeroRegistry() public {
        AttackRegistry impl = new AttackRegistry();
        bytes memory initData = abi.encodeWithSelector(
            AttackRegistry.initialize.selector,
            owner,
            registryModerator,
            address(0),
            address(agreementFactory),
            address(battleChainDeployerContract),
            treasury
        );
        vm.expectRevert(AttackRegistry.AttackRegistry__ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeRevertsWithZeroFactory() public {
        AttackRegistry impl = new AttackRegistry();
        bytes memory initData = abi.encodeWithSelector(
            AttackRegistry.initialize.selector,
            owner,
            registryModerator,
            address(safeHarborRegistry),
            address(0),
            address(battleChainDeployerContract),
            treasury
        );
        vm.expectRevert(AttackRegistry.AttackRegistry__ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeRevertsWithZeroBattleChainDeployer() public {
        AttackRegistry impl = new AttackRegistry();
        bytes memory initData = abi.encodeWithSelector(
            AttackRegistry.initialize.selector,
            owner,
            registryModerator,
            address(safeHarborRegistry),
            address(agreementFactory),
            address(0),
            treasury
        );
        vm.expectRevert(AttackRegistry.AttackRegistry__ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    /*//////////////////////////////////////////////////////////////
                    BATTLECHAIN DEPLOYER TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeployViaBattleChainDeployer() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // Contract should be registered with deployer as authorized owner
        assertEq(attackRegistry.getContractDeployer(contract1), protocolDeployer);
        assertEq(attackRegistry.getAuthorizedOwner(contract1), protocolDeployer);

        // Contract state should be NOT_DEPLOYED (not linked to an agreement yet)
        assertEq(attackRegistry.getAgreementForContract(contract1), address(0));
    }

    function testRegisterDeploymentOnlyBattleChainDeployer() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(AttackRegistry.AttackRegistry__Unauthorized.selector, attacker));
        attackRegistry.registerDeployment(makeAddr("fakeContract"), protocolDeployer);
    }

    /*//////////////////////////////////////////////////////////////
                    AUTHORIZE AGREEMENT OWNER TESTS
    //////////////////////////////////////////////////////////////*/

    function testAuthorizeAgreementOwner() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // Deployer authorizes agreement owner
        vm.prank(protocolDeployer);
        attackRegistry.authorizeAgreementOwner(contract1, agreementOwner);

        assertEq(attackRegistry.getAuthorizedOwner(contract1), agreementOwner);
    }

    function testAuthorizeAgreementOwnerUnauthorized() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // Attacker tries to authorize themselves
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(AttackRegistry.AttackRegistry__Unauthorized.selector, attacker));
        attackRegistry.authorizeAgreementOwner(contract1, attacker);
    }

    function testAuthorizeAgreementOwnerNotDeployedViaBattleChain() public {
        address fakeContract = makeAddr("fakeContract");

        // Try to authorize for a contract not deployed via BattleChainDeployer
        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__NotDeployedViaBattleChainDeployer.selector, fakeContract
            )
        );
        attackRegistry.authorizeAgreementOwner(fakeContract, agreementOwner);
    }

    function testAuthorizeAgreementOwnerChainedTransfer() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // Deployer authorizes agreementOwner
        vm.prank(protocolDeployer);
        attackRegistry.authorizeAgreementOwner(contract1, agreementOwner);

        // agreementOwner can now authorize someone else
        address newOwner = makeAddr("newOwner");
        vm.prank(agreementOwner);
        attackRegistry.authorizeAgreementOwner(contract1, newOwner);

        assertEq(attackRegistry.getAuthorizedOwner(contract1), newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                    REQUEST UNDER ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestUnderAttack() public {
        // Deploy contract via BattleChainDeployer
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // Create agreement with protocolDeployer as owner (same as authorized owner)
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // Request attack (protocolDeployer is both agreement owner and authorized)
        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Verify state
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.ATTACK_REQUESTED)
        );
        assertEq(attackRegistry.getAgreementForContract(contract1), address(testAgreement));
    }

    function testRequestUnderAttackWithAuthorization() public {
        // Deploy contract via BattleChainDeployer
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // Deployer authorizes agreementOwner
        vm.prank(protocolDeployer);
        attackRegistry.authorizeAgreementOwner(contract1, agreementOwner);

        // Create agreement with agreementOwner as owner
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(agreementOwner, contracts);

        // agreementOwner can now request attack
        vm.prank(agreementOwner);
        attackRegistry.requestUnderAttack(address(testAgreement));

        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.ATTACK_REQUESTED)
        );
    }

    function testRequestUnderAttackNotAuthorized() public {
        // Deploy contract via BattleChainDeployer
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // Create agreement with agreementOwner (NOT the authorized owner)
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(agreementOwner, contracts);

        // agreementOwner tries to request attack but is not authorized
        vm.prank(agreementOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__AgreementOwnerNotAuthorized.selector, contract1, agreementOwner
            )
        );
        attackRegistry.requestUnderAttack(address(testAgreement));
    }

    function testRequestUnderAttackNotAgreementOwner() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // Attacker tries to request attack
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__NotAgreementOwner.selector, attacker, protocolDeployer
            )
        );
        attackRegistry.requestUnderAttack(address(testAgreement));
    }

    function testRequestUnderAttackInvalidAgreement() public {
        address fakeAgreement = makeAddr("fakeAgreement");

        vm.prank(protocolDeployer);
        vm.expectRevert(abi.encodeWithSelector(AttackRegistry.AttackRegistry__InvalidAgreement.selector, fakeAgreement));
        attackRegistry.requestUnderAttack(fakeAgreement);
    }

    // Note: testRequestUnderAttackEmptyScope is omitted because the Agreement contract
    // already validates that all chains have accounts and all chain IDs are valid.
    // The AttackRegistry__EmptyContractArray error would only occur if the Agreement's
    // getBattleChainScopeAddresses() returns empty, but Agreement validation prevents this.

    /*//////////////////////////////////////////////////////////////
                REQUEST UNDER ATTACK BY NON-AUTHORIZED TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestUnderAttackByNonAuthorized() public {
        // Deploy contract NOT via BattleChainDeployer
        contract1 = makeAddr("externalContract");

        // Create agreement with the contract
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(agreementOwner, contracts);

        // Request attack for external contract
        vm.prank(agreementOwner);
        attackRegistry.requestUnderAttackByNonAuthorized(address(testAgreement));

        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.ATTACK_REQUESTED)
        );
    }

    function testRequestUnderAttackByNonAuthorizedRevertsForBattleChainDeployedContract() public {
        // Deploy contract via BattleChainDeployer (sets s_contractDeployer)
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // Create agreement that includes the BattleChainDeployer-deployed contract
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(agreementOwner, contracts);

        // requestUnderAttackByNonAuthorized should revert — contract was deployed via BattleChainDeployer
        vm.prank(agreementOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AttackRegistry.AttackRegistry__DeployedViaBattleChainDeployer.selector, contract1)
        );
        attackRegistry.requestUnderAttackByNonAuthorized(address(testAgreement));
    }

    /*//////////////////////////////////////////////////////////////
                        GO TO PRODUCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGoToProduction() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // Go directly to production (skip attack phase)
        vm.prank(protocolDeployer);
        attackRegistry.goToProduction(address(testAgreement));

        // Should be in PRODUCTION immediately
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PRODUCTION)
        );
        assertFalse(attackRegistry.isTopLevelContractUnderAttack(contract1));
    }

    function testGoToProductionNotAuthorized() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(agreementOwner, contracts);

        // agreementOwner is not authorized for the contract
        vm.prank(agreementOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__AgreementOwnerNotAuthorized.selector, contract1, agreementOwner
            )
        );
        attackRegistry.goToProduction(address(testAgreement));
    }

    /*//////////////////////////////////////////////////////////////
                        APPROVE ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    function testApproveAttack() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // Request attack
        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // DAO approves attack
        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.UNDER_ATTACK)
        );
        assertTrue(attackRegistry.isTopLevelContractUnderAttack(contract1));
    }

    function testApproveAttackUnauthorized() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Attacker tries to approve
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(AttackRegistry.AttackRegistry__Unauthorized.selector, attacker));
        attackRegistry.approveAttack(address(testAgreement));
    }

    function testApproveAttackInvalidState() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // Try to approve without requesting first
        vm.prank(registryModerator);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__InvalidState.selector, IAttackRegistry.ContractState.NOT_DEPLOYED
            )
        );
        attackRegistry.approveAttack(address(testAgreement));
    }

    /*//////////////////////////////////////////////////////////////
                    REJECT ATTACK REQUEST TESTS
    //////////////////////////////////////////////////////////////*/

    function testRejectAttackRequest() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // DAO rejects the request
        vm.prank(registryModerator);
        attackRegistry.rejectAttackRequest(address(testAgreement), false);

        // Agreement should be back to NOT_DEPLOYED
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.NOT_DEPLOYED)
        );

        // Contract should be unlinked from agreement
        assertEq(attackRegistry.getAgreementForContract(contract1), address(0));
    }

    function testRejectAttackRequestUnauthorized() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(AttackRegistry.AttackRegistry__Unauthorized.selector, attacker));
        attackRegistry.rejectAttackRequest(address(testAgreement), false);
    }

    function testRejectAttackRequestInvalidState() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Approve first
        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // Try to reject from UNDER_ATTACK state
        vm.prank(registryModerator);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__InvalidState.selector, IAttackRegistry.ContractState.UNDER_ATTACK
            )
        );
        attackRegistry.rejectAttackRequest(address(testAgreement), false);
    }

    /*//////////////////////////////////////////////////////////////
                        PROMOTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testPromote() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // Attack moderator requests promotion
        vm.prank(protocolDeployer);
        attackRegistry.promote(address(testAgreement));

        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PROMOTION_REQUESTED)
        );

        // Still attackable during promotion window
        assertTrue(attackRegistry.isTopLevelContractUnderAttack(contract1));

        // After 3 days, should be PRODUCTION
        vm.warp(block.timestamp + 3 days);
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PRODUCTION)
        );
        assertFalse(attackRegistry.isTopLevelContractUnderAttack(contract1));
    }

    function testPromoteInvalidState() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Try to promote from ATTACK_REQUESTED - should fail
        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__InvalidState.selector, IAttackRegistry.ContractState.ATTACK_REQUESTED
            )
        );
        attackRegistry.promote(address(testAgreement));
    }

    function testPromoteUnauthorized() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // Attacker tries to promote
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(AttackRegistry.AttackRegistry__Unauthorized.selector, attacker));
        attackRegistry.promote(address(testAgreement));
    }

    /*//////////////////////////////////////////////////////////////
                    CANCEL PROMOTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelPromotion() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        vm.prank(protocolDeployer);
        attackRegistry.promote(address(testAgreement));

        // Cancel promotion
        vm.prank(protocolDeployer);
        attackRegistry.cancelPromotion(address(testAgreement));

        // Should be back to UNDER_ATTACK
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.UNDER_ATTACK)
        );
    }

    function testCancelPromotionInvalidState() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // Try to cancel promotion when not in PROMOTION_REQUESTED state
        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__InvalidState.selector, IAttackRegistry.ContractState.UNDER_ATTACK
            )
        );
        attackRegistry.cancelPromotion(address(testAgreement));
    }

    /*//////////////////////////////////////////////////////////////
                    MARK CORRUPTED TESTS
    //////////////////////////////////////////////////////////////*/

    function testMarkCorrupted() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // Mark as corrupted (attack succeeded)
        vm.prank(protocolDeployer);
        attackRegistry.markCorrupted(address(testAgreement));

        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.CORRUPTED)
        );
        assertFalse(attackRegistry.isTopLevelContractUnderAttack(contract1));
    }

    function testMarkCorruptedFromPromotionRequested() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        vm.prank(protocolDeployer);
        attackRegistry.promote(address(testAgreement));

        // Mark as corrupted from PROMOTION_REQUESTED state
        vm.prank(protocolDeployer);
        attackRegistry.markCorrupted(address(testAgreement));

        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.CORRUPTED)
        );
    }

    function testMarkCorruptedInvalidState() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Try to mark corrupted from ATTACK_REQUESTED state
        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__InvalidState.selector, IAttackRegistry.ContractState.ATTACK_REQUESTED
            )
        );
        attackRegistry.markCorrupted(address(testAgreement));
    }

    function testCorruptedIsTerminal() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        vm.prank(protocolDeployer);
        attackRegistry.markCorrupted(address(testAgreement));

        // Try to promote from CORRUPTED - should fail
        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__InvalidState.selector, IAttackRegistry.ContractState.CORRUPTED
            )
        );
        attackRegistry.promote(address(testAgreement));
    }

    /*//////////////////////////////////////////////////////////////
                    INSTANT PROMOTE TESTS
    //////////////////////////////////////////////////////////////*/

    function testInstantPromote() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // DAO instant promotes
        vm.prank(registryModerator);
        attackRegistry.instantPromote(address(testAgreement));

        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PRODUCTION)
        );
    }

    function testInstantPromoteFromAttackRequested() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // DAO instant promotes from ATTACK_REQUESTED (skips attack phase entirely)
        vm.prank(registryModerator);
        attackRegistry.instantPromote(address(testAgreement));

        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PRODUCTION)
        );
    }

    function testInstantPromoteFromPromotionRequested() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        vm.prank(protocolDeployer);
        attackRegistry.promote(address(testAgreement));

        // DAO instant promotes from PROMOTION_REQUESTED
        vm.prank(registryModerator);
        attackRegistry.instantPromote(address(testAgreement));

        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PRODUCTION)
        );
    }

    function testInstantPromoteInvalidState() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // Try to instant promote from NOT_DEPLOYED
        vm.prank(registryModerator);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__InvalidState.selector, IAttackRegistry.ContractState.NOT_DEPLOYED
            )
        );
        attackRegistry.instantPromote(address(testAgreement));
    }

    /*//////////////////////////////////////////////////////////////
                    TRANSFER ATTACK MODERATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testTransferAttackModerator() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // Transfer attack moderator
        address newModerator = makeAddr("newModerator");
        vm.prank(protocolDeployer);
        attackRegistry.transferAttackModerator(address(testAgreement), newModerator);

        assertEq(attackRegistry.getAttackModerator(address(testAgreement)), newModerator);

        // New moderator can now promote
        vm.prank(newModerator);
        attackRegistry.promote(address(testAgreement));
    }

    function testTransferAttackModeratorUnauthorized() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // Attacker tries to transfer
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(AttackRegistry.AttackRegistry__Unauthorized.selector, attacker));
        attackRegistry.transferAttackModerator(address(testAgreement), attacker);
    }

    function testTransferAttackModeratorZeroAddress() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        vm.prank(protocolDeployer);
        vm.expectRevert(AttackRegistry.AttackRegistry__ZeroAddress.selector);
        attackRegistry.transferAttackModerator(address(testAgreement), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    OWNER FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeRegistryModerator() public {
        address newModerator = makeAddr("newModerator");

        vm.prank(owner);
        attackRegistry.changeRegistryModerator(newModerator);

        assertEq(attackRegistry.getRegistryModerator(), newModerator);
    }

    function testChangeRegistryModeratorUnauthorized() public {
        vm.prank(attacker);
        vm.expectRevert();
        attackRegistry.changeRegistryModerator(attacker);
    }

    function testChangeRegistryModeratorZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(AttackRegistry.AttackRegistry__ZeroAddress.selector);
        attackRegistry.changeRegistryModerator(address(0));
    }

    function testSetSafeHarborRegistry() public {
        address newRegistry = makeAddr("newRegistry");

        vm.prank(owner);
        attackRegistry.setSafeHarborRegistry(newRegistry);

        assertEq(attackRegistry.getSafeHarborRegistry(), newRegistry);
    }

    function testSetSafeHarborRegistryZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(AttackRegistry.AttackRegistry__ZeroAddress.selector);
        attackRegistry.setSafeHarborRegistry(address(0));
    }

    function testSetAgreementFactory() public {
        address newFactory = makeAddr("newFactory");

        vm.prank(owner);
        attackRegistry.setAgreementFactory(newFactory);

        assertEq(attackRegistry.getAgreementFactory(), newFactory);
    }

    function testSetAgreementFactoryZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(AttackRegistry.AttackRegistry__ZeroAddress.selector);
        attackRegistry.setAgreementFactory(address(0));
    }

    function testSetBattleChainDeployer() public {
        address newDeployer = makeAddr("newDeployer");

        vm.prank(owner);
        attackRegistry.setBattleChainDeployer(newDeployer);

        assertEq(attackRegistry.getBattleChainDeployer(), newDeployer);
    }

    function testSetBattleChainDeployerZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(AttackRegistry.AttackRegistry__ZeroAddress.selector);
        attackRegistry.setBattleChainDeployer(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    STATE TRANSITIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function testAutoPromoteAfterDeadline() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Fast forward past the 14-day window
        vm.warp(block.timestamp + 15 days);

        // Should auto-promote to PRODUCTION
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PRODUCTION)
        );
    }

    function testPromotionDelayIs3Days() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        vm.prank(protocolDeployer);
        attackRegistry.promote(address(testAgreement));

        // After 2 days, still PROMOTION_REQUESTED
        vm.warp(block.timestamp + 2 days);
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PROMOTION_REQUESTED)
        );

        // After 3 days total, should be PRODUCTION
        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PRODUCTION)
        );
    }

    function testNotDeployedState() public {
        // Random address not registered
        address randomContract = makeAddr("randomContract");
        assertEq(attackRegistry.getAgreementForContract(randomContract), address(0));
        assertFalse(attackRegistry.isTopLevelContractUnderAttack(randomContract));
    }

    /*//////////////////////////////////////////////////////////////
                    GET AGREEMENT INFO TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetAgreementInfo() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        IAttackRegistry.AgreementInfo memory info = attackRegistry.getAgreementInfo(address(testAgreement));

        assertEq(info.attackModerator, protocolDeployer);
        assertTrue(info.attackRequested);
        assertFalse(info.attackApproved);
        assertFalse(info.promoted);
        assertFalse(info.corrupted);
        assertTrue(info.isRegistered);
    }

    /*//////////////////////////////////////////////////////////////
            PROMOTION REQUESTED TIMESTAMP INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Invariant: `promotionRequestedTimestamp != 0` iff promotion is currently pending.
    ///      Every terminal-state transition (CORRUPTED or PRODUCTION) must clear the timestamp,
    ///      regardless of which state it's reached from.

    function _agreementInPromotionRequested() internal returns (Agreement) {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));
        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));
        vm.prank(protocolDeployer);
        attackRegistry.promote(address(testAgreement));

        // Sanity: timestamp set, state is PROMOTION_REQUESTED
        IAttackRegistry.AgreementInfo memory info = attackRegistry.getAgreementInfo(address(testAgreement));
        assertGt(info.promotionRequestedTimestamp, 0);
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PROMOTION_REQUESTED)
        );
        return testAgreement;
    }

    function testMarkCorruptedClearsPromotionTimestamp() public {
        Agreement testAgreement = _agreementInPromotionRequested();

        vm.prank(protocolDeployer);
        attackRegistry.markCorrupted(address(testAgreement));

        IAttackRegistry.AgreementInfo memory info = attackRegistry.getAgreementInfo(address(testAgreement));
        assertTrue(info.corrupted);
        assertEq(info.promotionRequestedTimestamp, 0);
    }

    function testInstantCorruptClearsPromotionTimestamp() public {
        Agreement testAgreement = _agreementInPromotionRequested();

        vm.prank(registryModerator);
        attackRegistry.instantCorrupt(address(testAgreement));

        IAttackRegistry.AgreementInfo memory info = attackRegistry.getAgreementInfo(address(testAgreement));
        assertTrue(info.corrupted);
        assertEq(info.promotionRequestedTimestamp, 0);
    }

    function testInstantPromoteClearsPromotionTimestamp() public {
        Agreement testAgreement = _agreementInPromotionRequested();

        vm.prank(registryModerator);
        attackRegistry.instantPromote(address(testAgreement));

        IAttackRegistry.AgreementInfo memory info = attackRegistry.getAgreementInfo(address(testAgreement));
        assertTrue(info.promoted);
        assertEq(info.promotionRequestedTimestamp, 0);
    }

    function testFinalizeStateClearsPromotionTimestamp() public {
        Agreement testAgreement = _agreementInPromotionRequested();

        // Wait for the 3-day promotion delay to elapse
        vm.warp(block.timestamp + attackRegistry.PROMOTION_DELAY() + 1);

        // State is computed PRODUCTION but not yet materialized
        IAttackRegistry.AgreementInfo memory pre = attackRegistry.getAgreementInfo(address(testAgreement));
        assertGt(pre.promotionRequestedTimestamp, 0);
        assertFalse(pre.promoted);

        attackRegistry.finalizeState(address(testAgreement));

        IAttackRegistry.AgreementInfo memory post = attackRegistry.getAgreementInfo(address(testAgreement));
        assertTrue(post.promoted);
        assertEq(post.promotionRequestedTimestamp, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    INSUFFICIENT COMMITMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestUnderAttackInsufficientCommitment() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // Create agreement with short commitment window
        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] =
            BCAccount({ accountAddress: _addressToString(contract1), childContractScope: ChildContractScope.None });

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

        vm.prank(protocolDeployer);
        address agreementAddr = agreementFactory.create(details, protocolDeployer, keccak256("short-commitment"));
        Agreement shortCommitmentAgreement = Agreement(agreementAddr);

        // Only extend to 1 day (less than MIN_COMMITMENT of 7 days)
        vm.prank(protocolDeployer);
        shortCommitmentAgreement.extendCommitmentWindow(block.timestamp + 1 days);

        uint256 minRequired = block.timestamp + 7 days;
        uint256 actual = block.timestamp + 1 days;

        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(AttackRegistry.AttackRegistry__InsufficientCommitment.selector, minRequired, actual)
        );
        attackRegistry.requestUnderAttack(address(shortCommitmentAgreement));
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE CONTRACTS TESTS
    //////////////////////////////////////////////////////////////*/

    function testMultipleContractsInAgreement() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        contract2 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(2)));
        contract3 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(3)));

        address[] memory contracts = new address[](3);
        contracts[0] = contract1;
        contracts[1] = contract2;
        contracts[2] = contract3;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // All contracts should be linked to the same agreement
        assertEq(attackRegistry.getAgreementForContract(contract1), address(testAgreement));
        assertEq(attackRegistry.getAgreementForContract(contract2), address(testAgreement));
        assertEq(attackRegistry.getAgreementForContract(contract3), address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // All contracts should be under attack
        assertTrue(attackRegistry.isTopLevelContractUnderAttack(contract1));
        assertTrue(attackRegistry.isTopLevelContractUnderAttack(contract2));
        assertTrue(attackRegistry.isTopLevelContractUnderAttack(contract3));
    }

    function testMultipleContractsPartialAuthorization() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        contract2 = _deployContractViaBattleChain(makeAddr("otherDeployer"), bytes32(uint256(2)));

        address[] memory contracts = new address[](2);
        contracts[0] = contract1;
        contracts[1] = contract2;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // protocolDeployer is only authorized for contract1, not contract2
        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__AgreementOwnerNotAuthorized.selector, contract2, protocolDeployer
            )
        );
        attackRegistry.requestUnderAttack(address(testAgreement));
    }

    /*//////////////////////////////////////////////////////////////
                    EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testAgreementStateChangedEvent() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.expectEmit(true, false, false, true);
        emit AttackRegistry.AgreementStateChanged(
            address(testAgreement), IAttackRegistry.ContractState.ATTACK_REQUESTED
        );

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));
    }

    function testContractRegisteredEvent() public {
        // Generate the address that will be created
        address expectedContract = address(uint160(0x1000 + contractCounter + 1));

        vm.expectEmit(true, true, false, false);
        emit AttackRegistry.ContractRegistered(expectedContract, address(0)); // Agreement is 0 during deployment
        // registration

        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(100)));
    }

    function testAgreementOwnerAuthorizedEvent() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        vm.expectEmit(true, true, false, false);
        emit AttackRegistry.AgreementOwnerAuthorized(contract1, agreementOwner);

        vm.prank(protocolDeployer);
        attackRegistry.authorizeAgreementOwner(contract1, agreementOwner);
    }

    /*//////////////////////////////////////////////////////////////
                    EXAMPLE FLOW TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Flow 1: Deploy -> Request Attack -> Under Attack -> Production
    function testHappyPathFlow() public {
        // 1. Deploy via BattleChainDeployer
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // 2. Create agreement
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // 3. Request attack mode
        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.ATTACK_REQUESTED)
        );

        // 4. DAO approves
        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.UNDER_ATTACK)
        );

        // 5. Protocol requests promotion
        vm.prank(protocolDeployer);
        attackRegistry.promote(address(testAgreement));
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PROMOTION_REQUESTED)
        );

        // 6. Wait 3 days for promotion
        vm.warp(block.timestamp + 3 days);
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PRODUCTION)
        );
    }

    /// @notice Flow 2: Deploy -> Request Attack -> Under Attack -> Corrupted
    function testAttackSucceededFlow() public {
        // 1. Deploy via BattleChainDeployer
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // 2. Create agreement
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // 3. Request attack mode
        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // 4. DAO approves
        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));
        assertTrue(attackRegistry.isTopLevelContractUnderAttack(contract1));

        // 5. Attack succeeds - protocol marks as corrupted
        vm.prank(protocolDeployer);
        attackRegistry.markCorrupted(address(testAgreement));
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.CORRUPTED)
        );
        assertFalse(attackRegistry.isTopLevelContractUnderAttack(contract1));
    }

    /// @notice Flow 3: Deploy -> Go To Production (skip attack)
    function testSkipAttackFlow() public {
        // 1. Deploy via BattleChainDeployer
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // 2. Create agreement
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // 3. Go directly to production (no attack phase)
        vm.prank(protocolDeployer);
        attackRegistry.goToProduction(address(testAgreement));

        // Immediately in PRODUCTION
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PRODUCTION)
        );
    }

    /*//////////////////////////////////////////////////////////////
            REGISTER CONTRACT FOR EXISTING AGREEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testRegisterContractForExistingAgreement_HappyPath() public {
        // Deploy initial contract and register agreement
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // Deploy a new contract and authorize it
        contract2 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(2)));

        // Add contract2 to agreement scope (triggers auto-sync)
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: _addressToString(contract2),
            childContractScope: ChildContractScope.None
        });
        vm.prank(protocolDeployer);
        testAgreement.addAccounts(battleChainCaip2, newAccounts);

        // Verify contract2 is now tracked
        assertTrue(attackRegistry.isTopLevelContractUnderAttack(contract2));
        assertEq(attackRegistry.getAgreementForContract(contract2), address(testAgreement));
    }

    function testRegisterContractForExistingAgreement_SkipsWhenNotRegistered() public {
        // Deploy contract, create agreement but DON'T register it
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // Add contract to scope — should not revert, sync is a no-op
        contract2 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(2)));
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: _addressToString(contract2),
            childContractScope: ChildContractScope.None
        });
        vm.prank(protocolDeployer);
        testAgreement.addAccounts(battleChainCaip2, newAccounts);

        // contract2 should NOT be in the attack registry
        assertEq(attackRegistry.getAgreementForContract(contract2), address(0));
    }

    function testRegisterContractForExistingAgreement_SkipsWhenTerminalState() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // Go directly to PRODUCTION
        vm.prank(protocolDeployer);
        attackRegistry.goToProduction(address(testAgreement));

        // Add a new contract — sync should silently skip
        contract2 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(2)));
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: _addressToString(contract2),
            childContractScope: ChildContractScope.None
        });
        vm.prank(protocolDeployer);
        testAgreement.addAccounts(battleChainCaip2, newAccounts);

        // contract2 should NOT be tracked
        assertEq(attackRegistry.getAgreementForContract(contract2), address(0));
    }

    function testRegisterContractForExistingAgreement_SkipsWhenAlreadyLinked() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // contract1 is already linked — adding it again should be idempotent (no revert)
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: _addressToString(contract1),
            childContractScope: ChildContractScope.None
        });
        vm.prank(protocolDeployer);
        testAgreement.addAccounts(battleChainCaip2, newAccounts);

        // Still correctly linked
        assertEq(attackRegistry.getAgreementForContract(contract1), address(testAgreement));
    }

    function testRegisterContractForExistingAgreement_RevertsWhenLinkedToOtherAgreement() public {
        // Register contract1 under agreement A
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contractsA = new address[](1);
        contractsA[0] = contract1;
        Agreement agreementA = _createAgreementWithContracts(protocolDeployer, contractsA);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(agreementA));

        // Create agreement B with a different initial contract
        contract2 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(2)));
        address[] memory contractsB = new address[](1);
        contractsB[0] = contract2;
        Agreement agreementB = _createAgreementWithContracts(protocolDeployer, contractsB);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(agreementB));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(agreementB));

        // Try to add contract1 (linked to agreementA) to agreementB's scope
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: _addressToString(contract1),
            childContractScope: ChildContractScope.None
        });
        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__ContractAlreadyLinked.selector, contract1, address(agreementA)
            )
        );
        agreementB.addAccounts(battleChainCaip2, newAccounts);
    }

    function testRegisterContractForExistingAgreement_RevertsWhenInvalidAgreement() public {
        // Call directly from a non-agreement address
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(AttackRegistry.AttackRegistry__InvalidAgreement.selector, attacker));
        attackRegistry.registerContractForExistingAgreement(makeAddr("someContract"));
    }

    function testRegisterContractForExistingAgreement_RejectsBCDeployedWithoutAuth() public {
        // Deploy contract1 by protocolDeployer, but don't authorize agreementOwner
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));

        // Create initial agreement with an external contract so it can register
        contract2 = makeAddr("externalContract");
        address[] memory contracts = new address[](1);
        contracts[0] = contract2;
        Agreement testAgreement = _createAgreementWithContracts(agreementOwner, contracts);

        vm.prank(agreementOwner);
        attackRegistry.requestUnderAttackByNonAuthorized(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // Try to add contract1 (BC-deployed, authorized to protocolDeployer, not agreementOwner)
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: _addressToString(contract1),
            childContractScope: ChildContractScope.None
        });
        vm.prank(agreementOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__AgreementOwnerNotAuthorized.selector, contract1, agreementOwner
            )
        );
        testAgreement.addAccounts(battleChainCaip2, newAccounts);
    }

    function testRegisterContractForExistingAgreement_AllowsBCDeployedWithAuth() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        contract2 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(2)));

        // Register with contract1 only
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // Add contract2 — protocolDeployer is authorized owner for both
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: _addressToString(contract2),
            childContractScope: ChildContractScope.None
        });
        vm.prank(protocolDeployer);
        testAgreement.addAccounts(battleChainCaip2, newAccounts);

        assertTrue(attackRegistry.isTopLevelContractUnderAttack(contract2));
    }

    function testRegisterContractForExistingAgreement_AllowsExternalContract() public {
        contract1 = makeAddr("externalContract1");
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(agreementOwner, contracts);

        vm.prank(agreementOwner);
        attackRegistry.requestUnderAttackByNonAuthorized(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // Add another external contract — should work without ownership check
        address externalContract2 = makeAddr("externalContract2");
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: _addressToString(externalContract2),
            childContractScope: ChildContractScope.None
        });
        vm.prank(agreementOwner);
        testAgreement.addAccounts(battleChainCaip2, newAccounts);

        assertTrue(attackRegistry.isTopLevelContractUnderAttack(externalContract2));
    }

    /*//////////////////////////////////////////////////////////////
            UNREGISTER CONTRACT FOR EXISTING AGREEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testUnregisterContractForExistingAgreement_HappyPath() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        contract2 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(2)));

        address[] memory contracts = new address[](2);
        contracts[0] = contract1;
        contracts[1] = contract2;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        assertTrue(attackRegistry.isTopLevelContractUnderAttack(contract2));

        // Wait for commitment window to expire so we can remove
        vm.warp(block.timestamp + 31 days);

        // Remove contract2 — triggers auto-sync unregister
        string[] memory accountsToRemove = new string[](1);
        accountsToRemove[0] = _addressToString(contract2);
        vm.prank(protocolDeployer);
        testAgreement.removeAccounts(battleChainCaip2, accountsToRemove);

        assertFalse(attackRegistry.isTopLevelContractUnderAttack(contract2));
        assertEq(attackRegistry.getAgreementForContract(contract2), address(0));
        // contract1 still under attack
        assertTrue(attackRegistry.isTopLevelContractUnderAttack(contract1));
    }

    function testUnregisterContractForExistingAgreement_SkipsWhenNotRegistered() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        contract2 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(2)));

        address[] memory contracts = new address[](2);
        contracts[0] = contract1;
        contracts[1] = contract2;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // DON'T register — warp past commitment window, then remove should not revert
        vm.warp(block.timestamp + 31 days);
        string[] memory accountsToRemove = new string[](1);
        accountsToRemove[0] = _addressToString(contract2);
        vm.prank(protocolDeployer);
        testAgreement.removeAccounts(battleChainCaip2, accountsToRemove);
    }

    function testUnregisterContractForExistingAgreement_SkipsWhenNotLinked() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Call unregister for a contract not linked to this agreement — should be idempotent
        vm.prank(address(testAgreement));
        attackRegistry.unregisterContractForExistingAgreement(makeAddr("unlinkedContract"));
    }

    /*//////////////////////////////////////////////////////////////
                    SYNC NEW CONTRACTS TESTS
    //////////////////////////////////////////////////////////////*/

    function testSyncNewContracts_HappyPath() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        // Deploy a fresh AttackRegistry (with same factory) where this agreement isn't registered,
        // so registerContractForExistingAgreement silently returns (simulates pre-sync agreement)
        AttackRegistry dummyImpl = new AttackRegistry();
        address dummyProxy = address(
            new ERC1967Proxy(
                address(dummyImpl),
                abi.encodeWithSelector(
                    AttackRegistry.initialize.selector,
                    owner,
                    registryModerator,
                    address(safeHarborRegistry),
                    address(agreementFactory),
                    address(battleChainDeployerContract),
                    treasury
                )
            )
        );
        vm.prank(owner);
        safeHarborRegistry.setAttackRegistry(dummyProxy);

        // Add contract2 — sync hits the dummy registry (no-op), so real registry won't have it
        contract2 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(2)));
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: _addressToString(contract2),
            childContractScope: ChildContractScope.None
        });
        vm.prank(protocolDeployer);
        testAgreement.addAccounts(battleChainCaip2, newAccounts);

        // Restore real attack registry
        vm.prank(owner);
        safeHarborRegistry.setAttackRegistry(address(attackRegistry));

        // contract2 is NOT yet tracked
        assertFalse(attackRegistry.isTopLevelContractUnderAttack(contract2));

        // Manual sync picks it up
        attackRegistry.syncNewContracts(address(testAgreement));

        assertTrue(attackRegistry.isTopLevelContractUnderAttack(contract2));
        assertEq(attackRegistry.getAgreementForContract(contract2), address(testAgreement));
    }

    function testSyncNewContracts_RevertsWhenNoNewContracts() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // All contracts already synced at registration time
        vm.expectRevert(
            abi.encodeWithSelector(AttackRegistry.AttackRegistry__NoNewContracts.selector, address(testAgreement))
        );
        attackRegistry.syncNewContracts(address(testAgreement));
    }

    function testSyncNewContracts_RevertsWhenNotRegistered() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // Don't register — syncNewContracts should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                AttackRegistry.AttackRegistry__AgreementNotRegistered.selector, address(testAgreement)
            )
        );
        attackRegistry.syncNewContracts(address(testAgreement));
    }

    function testAddOrSetChains_AutoSyncsWithAttackRegistry() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        assertTrue(attackRegistry.isTopLevelContractUnderAttack(contract1));

        // Wait for commitment window to expire so we can replace the chain
        vm.warp(block.timestamp + 31 days);

        // Replace BattleChain chain with new contracts via addOrSetChains
        contract2 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(2)));
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: _addressToString(contract2),
            childContractScope: ChildContractScope.None
        });
        BCChain[] memory newChains = new BCChain[](1);
        newChains[0] = BCChain({
            accounts: newAccounts,
            assetRecoveryAddress: "0x0000000000000000000000000000000000000022",
            caip2ChainId: battleChainCaip2
        });

        vm.prank(protocolDeployer);
        testAgreement.addOrSetChains(newChains);

        // contract1 should be unregistered (removed via _clearBattleChainScope)
        assertEq(attackRegistry.getAgreementForContract(contract1), address(0));
        // contract2 should be registered (added via _addToBattleChainScope)
        assertEq(attackRegistry.getAgreementForContract(contract2), address(testAgreement));
    }

    function testSyncNewContracts_RevertsWhenInvalidAgreement() public {
        address fakeAgreement = makeAddr("fakeAgreement");
        vm.expectRevert(abi.encodeWithSelector(AttackRegistry.AttackRegistry__InvalidAgreement.selector, fakeAgreement));
        attackRegistry.syncNewContracts(fakeAgreement);
    }

    /// @notice Flow 4: External Deploy -> Request Attack (Non-Authorized) -> Rejected
    function testExternalDeployRejectedFlow() public {
        // 1. Contract deployed externally (not via BattleChainDeployer)
        contract1 = makeAddr("externalContract");

        // 2. Create agreement
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(agreementOwner, contracts);

        // 3. Request attack via non-authorized path
        vm.prank(agreementOwner);
        attackRegistry.requestUnderAttackByNonAuthorized(address(testAgreement));
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.ATTACK_REQUESTED)
        );

        // 4. DAO rejects after due diligence
        vm.prank(registryModerator);
        attackRegistry.rejectAttackRequest(address(testAgreement), false);

        // Back to NOT_DEPLOYED
        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.NOT_DEPLOYED)
        );
    }

    /*//////////////////////////////////////////////////////////////
                    BOND COLLECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestUnderAttackCollectsFeeAndBond() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        uint256 balanceBefore = bondToken.balanceOf(protocolDeployer);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        uint256 balanceAfter = bondToken.balanceOf(protocolDeployer);
        assertEq(balanceBefore - balanceAfter, FEE_AMOUNT + VERIFIED_BOND);

        // Fee went to treasury, bond stayed in registry
        assertEq(bondToken.balanceOf(treasury), FEE_AMOUNT);
        assertEq(bondToken.balanceOf(address(attackRegistry)), VERIFIED_BOND);

        BondDeposit memory deposit = attackRegistry.getBondDeposit(address(testAgreement));
        assertEq(deposit.depositor, protocolDeployer);
        assertEq(deposit.feeAmount, FEE_AMOUNT);
        assertEq(deposit.bondAmount, VERIFIED_BOND);
        assertFalse(deposit.claimed);
        assertFalse(deposit.slashed);
    }

    function testRequestUnverifiedCollectsLargerBond() public {
        contract1 = makeAddr("externalContract");
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(agreementOwner, contracts);

        uint256 balanceBefore = bondToken.balanceOf(agreementOwner);

        vm.prank(agreementOwner);
        attackRegistry.requestUnderAttackForUnverifiedContracts(address(testAgreement));

        uint256 balanceAfter = bondToken.balanceOf(agreementOwner);
        assertEq(balanceBefore - balanceAfter, FEE_AMOUNT + UNVERIFIED_BOND);

        BondDeposit memory deposit = attackRegistry.getBondDeposit(address(testAgreement));
        assertEq(deposit.bondAmount, UNVERIFIED_BOND);
    }

    function testGoToProductionCollectsNothing() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        uint256 balanceBefore = bondToken.balanceOf(protocolDeployer);

        vm.prank(protocolDeployer);
        attackRegistry.goToProduction(address(testAgreement));

        assertEq(bondToken.balanceOf(protocolDeployer), balanceBefore);
    }

    function testZeroAmountsSkipTransfer() public {
        // Set all amounts to 0
        vm.startPrank(owner);
        attackRegistry.setFeeAmount(0);
        attackRegistry.setVerifiedBondAmount(0);
        vm.stopPrank();

        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        uint256 balanceBefore = bondToken.balanceOf(protocolDeployer);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        assertEq(bondToken.balanceOf(protocolDeployer), balanceBefore);
    }

    function testBondTokenZeroDisablesPayments() public {
        // Disable bond token
        vm.prank(owner);
        attackRegistry.setBondToken(address(0));

        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        uint256 balanceBefore = bondToken.balanceOf(protocolDeployer);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        assertEq(bondToken.balanceOf(protocolDeployer), balanceBefore);
    }

    function testClaimBondZeroBondSucceedsAfterProduction() public {
        // Fee-only configuration: bond amount = 0, fee non-zero. _collectFeeAndBond still
        // creates a BondDeposit with bondAmount = 0.
        vm.prank(owner);
        attackRegistry.setVerifiedBondAmount(0);

        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Sanity: deposit exists with bondAmount = 0
        BondDeposit memory pre = attackRegistry.getBondDeposit(address(testAgreement));
        assertEq(pre.bondAmount, 0);
        assertEq(pre.feeAmount, FEE_AMOUNT);
        assertFalse(pre.claimed);

        // Run the lifecycle to PRODUCTION
        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));
        vm.prank(protocolDeployer);
        attackRegistry.promote(address(testAgreement));
        vm.warp(block.timestamp + attackRegistry.PROMOTION_DELAY() + 1);

        uint256 balanceBefore = bondToken.balanceOf(protocolDeployer);

        // Claim succeeds (previously this would revert with BondNotYetClaimable)
        vm.prank(protocolDeployer);
        attackRegistry.claimBond(address(testAgreement));

        BondDeposit memory post = attackRegistry.getBondDeposit(address(testAgreement));
        assertTrue(post.claimed);
        // No tokens transferred — bond was zero
        assertEq(bondToken.balanceOf(protocolDeployer), balanceBefore);
    }

    function testClaimBondZeroBondRevertsBeforeProduction() public {
        // Zero-bond claims are gated on PRODUCTION (same as non-zero claims). Calling claimBond
        // while the agreement is still in an active state must revert.
        vm.prank(owner);
        attackRegistry.setVerifiedBondAmount(0);

        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Still in ATTACK_REQUESTED — claim must revert
        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                BondManager.BondManager__BondNotYetClaimable.selector, address(testAgreement)
            )
        );
        attackRegistry.claimBond(address(testAgreement));

        // Approve attack → UNDER_ATTACK. Claim still must revert.
        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                BondManager.BondManager__BondNotYetClaimable.selector, address(testAgreement)
            )
        );
        attackRegistry.claimBond(address(testAgreement));
    }

    function testClaimBondZeroBondCannotDoubleClaim() public {
        vm.prank(owner);
        attackRegistry.setVerifiedBondAmount(0);

        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Run the lifecycle to PRODUCTION
        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));
        vm.prank(protocolDeployer);
        attackRegistry.promote(address(testAgreement));
        vm.warp(block.timestamp + attackRegistry.PROMOTION_DELAY() + 1);

        // First claim succeeds (zero-bond short-circuit inside the PRODUCTION gate)
        vm.prank(protocolDeployer);
        attackRegistry.claimBond(address(testAgreement));

        // Second claim reverts via the BondAlreadyClaimed guard
        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(BondManager.BondManager__BondAlreadyClaimed.selector, address(testAgreement))
        );
        attackRegistry.claimBond(address(testAgreement));
    }

    function testClaimBondZeroBondNonDepositorReverts() public {
        vm.prank(owner);
        attackRegistry.setVerifiedBondAmount(0);

        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Non-depositor is rejected before reaching any state check (depositor guard runs first)
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                BondManager.BondManager__NotBondDepositor.selector, attacker, protocolDeployer
            )
        );
        attackRegistry.claimBond(address(testAgreement));
    }

    /*//////////////////////////////////////////////////////////////
                    SOFT REJECT (BOND CLAIMABLE)
    //////////////////////////////////////////////////////////////*/

    function testSoftRejectMakesBondClaimable() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.rejectAttackRequest(address(testAgreement), false);

        BondDeposit memory deposit = attackRegistry.getBondDeposit(address(testAgreement));
        assertTrue(deposit.bondClaimable);
        assertFalse(deposit.slashed);

        uint256 balanceBefore = bondToken.balanceOf(protocolDeployer);

        vm.prank(protocolDeployer);
        attackRegistry.claimBond(address(testAgreement));

        // Only bond returned — fee already went to treasury
        assertEq(bondToken.balanceOf(protocolDeployer) - balanceBefore, VERIFIED_BOND);
    }

    /*//////////////////////////////////////////////////////////////
                    HARD REJECT (SLASHED)
    //////////////////////////////////////////////////////////////*/

    function testHardRejectSlashesBond() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.rejectAttackRequest(address(testAgreement), true);

        BondDeposit memory deposit = attackRegistry.getBondDeposit(address(testAgreement));
        assertTrue(deposit.slashed);
        assertFalse(deposit.bondClaimable);

        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(BondManager.BondManager__BondAlreadySlashed.selector, address(testAgreement))
        );
        attackRegistry.claimBond(address(testAgreement));
    }

    /*//////////////////////////////////////////////////////////////
                    MARK CORRUPTED BOND TESTS
    //////////////////////////////////////////////////////////////*/

    function testMarkCorruptedMakesBondClaimable() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        vm.prank(protocolDeployer);
        attackRegistry.markCorrupted(address(testAgreement));

        BondDeposit memory deposit = attackRegistry.getBondDeposit(address(testAgreement));
        assertTrue(deposit.bondClaimable);

        uint256 balanceBefore = bondToken.balanceOf(protocolDeployer);

        vm.prank(protocolDeployer);
        attackRegistry.claimBond(address(testAgreement));

        // Only bond returned, fee kept
        assertEq(bondToken.balanceOf(protocolDeployer) - balanceBefore, VERIFIED_BOND);
    }

    /*//////////////////////////////////////////////////////////////
                    INSTANT PROMOTE / CORRUPT BOND TESTS
    //////////////////////////////////////////////////////////////*/

    function testInstantPromoteSlashesBond() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.instantPromote(address(testAgreement));

        BondDeposit memory deposit = attackRegistry.getBondDeposit(address(testAgreement));
        assertTrue(deposit.slashed);

        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(BondManager.BondManager__BondAlreadySlashed.selector, address(testAgreement))
        );
        attackRegistry.claimBond(address(testAgreement));
    }

    function testInstantCorruptSlashesBond() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.instantCorrupt(address(testAgreement));

        BondDeposit memory deposit = attackRegistry.getBondDeposit(address(testAgreement));
        assertTrue(deposit.slashed);
    }

    /*//////////////////////////////////////////////////////////////
                    PROMOTE -> PRODUCTION BOND TESTS
    //////////////////////////////////////////////////////////////*/

    function testPromoteToProductionMakesBondClaimable() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.approveAttack(address(testAgreement));

        vm.prank(protocolDeployer);
        attackRegistry.promote(address(testAgreement));

        // Wait for promotion delay
        vm.warp(block.timestamp + 3 days);

        // finalizeState materializes production and marks bond claimable
        attackRegistry.finalizeState(address(testAgreement));

        BondDeposit memory deposit = attackRegistry.getBondDeposit(address(testAgreement));
        assertTrue(deposit.bondClaimable);

        uint256 balanceBefore = bondToken.balanceOf(protocolDeployer);
        vm.prank(protocolDeployer);
        attackRegistry.claimBond(address(testAgreement));
        assertEq(bondToken.balanceOf(protocolDeployer) - balanceBefore, VERIFIED_BOND);
    }

    /*//////////////////////////////////////////////////////////////
                    TIME-BASED AUTO-PROMOTION BOND TESTS
    //////////////////////////////////////////////////////////////*/

    function testClaimBondLazyMarksOnAutoPromotion() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Auto-promote after deadline (14 days)
        vm.warp(block.timestamp + 15 days);

        assertEq(
            uint256(attackRegistry.getAgreementState(address(testAgreement))),
            uint256(IAttackRegistry.ContractState.PRODUCTION)
        );

        // Bond not yet marked claimable in storage, but claimBond handles it lazily
        uint256 balanceBefore = bondToken.balanceOf(protocolDeployer);
        vm.prank(protocolDeployer);
        attackRegistry.claimBond(address(testAgreement));
        assertEq(bondToken.balanceOf(protocolDeployer) - balanceBefore, VERIFIED_BOND);
    }

    /*//////////////////////////////////////////////////////////////
                    CLAIM BOND REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function testClaimBondRevertsForWrongCaller() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.rejectAttackRequest(address(testAgreement), false);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(BondManager.BondManager__NotBondDepositor.selector, attacker, protocolDeployer)
        );
        attackRegistry.claimBond(address(testAgreement));
    }

    function testClaimBondRevertsOnDoubleClaim() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.rejectAttackRequest(address(testAgreement), false);

        vm.prank(protocolDeployer);
        attackRegistry.claimBond(address(testAgreement));

        vm.prank(protocolDeployer);
        vm.expectRevert(
            abi.encodeWithSelector(BondManager.BondManager__BondAlreadyClaimed.selector, address(testAgreement))
        );
        attackRegistry.claimBond(address(testAgreement));
    }

    function testClaimBondRevertsForNonExistentDeposit() public {
        address fakeAgreement = makeAddr("noDeposit");
        vm.prank(protocolDeployer);
        vm.expectRevert(abi.encodeWithSelector(BondManager.BondManager__NoBondDeposit.selector, fakeAgreement));
        attackRegistry.claimBond(fakeAgreement);
    }

    /*//////////////////////////////////////////////////////////////
                    BOND FORFEIT ON RE-REGISTRATION
    //////////////////////////////////////////////////////////////*/

    function testReRegistrationForfeitsUnclaimedBond() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        // First registration + soft reject
        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.prank(registryModerator);
        attackRegistry.rejectAttackRequest(address(testAgreement), false);

        uint256 reservedBefore = attackRegistry.getReservedByToken(address(bondToken));
        assertEq(reservedBefore, VERIFIED_BOND);

        // Re-register without claiming — old bond forfeited
        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // s_reservedByToken should be exactly one bond (old decremented, new incremented)
        uint256 reservedAfter = attackRegistry.getReservedByToken(address(bondToken));
        assertEq(reservedAfter, VERIFIED_BOND);

        // Old deposit overwritten — only the new one is claimable
        BondDeposit memory deposit = attackRegistry.getBondDeposit(address(testAgreement));
        assertEq(deposit.bondAmount, VERIFIED_BOND);
        assertFalse(deposit.bondClaimable);
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAW FUNDS TESTS
    //////////////////////////////////////////////////////////////*/

    function testWithdrawFundsGuardsReserved() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Soft reject — bond is claimable (reserved), not withdrawable
        vm.prank(registryModerator);
        attackRegistry.rejectAttackRequest(address(testAgreement), false);

        // Registry holds only the bond (fee went to treasury)
        assertEq(bondToken.balanceOf(address(attackRegistry)), VERIFIED_BOND);
        assertEq(attackRegistry.getReservedByToken(address(bondToken)), VERIFIED_BOND);

        // Withdraw returns 0 — entire balance is reserved
        vm.prank(owner);
        uint256 withdrawn = attackRegistry.withdrawFunds(address(bondToken), treasury);
        assertEq(withdrawn, 0);
    }

    function testWithdrawAfterSlash() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        // Hard reject — slashes bond, unreserves it
        vm.prank(registryModerator);
        attackRegistry.rejectAttackRequest(address(testAgreement), true);

        // Slashed bond is now withdrawable
        assertEq(bondToken.balanceOf(address(attackRegistry)), VERIFIED_BOND);
        assertEq(attackRegistry.getReservedByToken(address(bondToken)), 0);

        address withdrawTo = makeAddr("withdrawRecipient");
        vm.prank(owner);
        uint256 withdrawn = attackRegistry.withdrawFunds(address(bondToken), withdrawTo);
        assertEq(withdrawn, VERIFIED_BOND);
        assertEq(bondToken.balanceOf(withdrawTo), VERIFIED_BOND);
    }

    function testWithdrawFundsUnauthorized() public {
        vm.prank(attacker);
        vm.expectRevert();
        attackRegistry.withdrawFunds(address(bondToken), attacker);
    }

    /*//////////////////////////////////////////////////////////////
                    BOND SETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetBondToken() public {
        address newToken = makeAddr("newToken");
        vm.prank(owner);
        attackRegistry.setBondToken(newToken);
        assertEq(attackRegistry.getBondToken(), newToken);
    }

    function testSetBondTokenToZeroDisables() public {
        vm.prank(owner);
        attackRegistry.setBondToken(address(0));
        assertEq(attackRegistry.getBondToken(), address(0));
    }

    function testSetBondTokenUnauthorized() public {
        vm.prank(attacker);
        vm.expectRevert();
        attackRegistry.setBondToken(makeAddr("token"));
    }

    function testSetTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        vm.prank(owner);
        attackRegistry.setTreasury(newTreasury);
        assertEq(attackRegistry.getTreasury(), newTreasury);
    }

    function testSetTreasuryZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert(BondManager.BondManager__ZeroAddress.selector);
        attackRegistry.setTreasury(address(0));
    }

    function testSetFeeAmount() public {
        vm.prank(owner);
        attackRegistry.setFeeAmount(999);
        assertEq(attackRegistry.getFeeAmount(), 999);
    }

    function testSetVerifiedBondAmount() public {
        vm.prank(owner);
        attackRegistry.setVerifiedBondAmount(2000);
        assertEq(attackRegistry.getVerifiedBondAmount(), 2000);
    }

    function testSetUnverifiedBondAmount() public {
        vm.prank(owner);
        attackRegistry.setUnverifiedBondAmount(5000);
        assertEq(attackRegistry.getUnverifiedBondAmount(), 5000);
    }

    function testBondGettersReturnConfigured() public {
        assertEq(attackRegistry.getBondToken(), address(bondToken));
        assertEq(attackRegistry.getFeeAmount(), FEE_AMOUNT);
        assertEq(attackRegistry.getVerifiedBondAmount(), VERIFIED_BOND);
        assertEq(attackRegistry.getUnverifiedBondAmount(), UNVERIFIED_BOND);
        assertEq(attackRegistry.getTreasury(), treasury);
    }

    /*//////////////////////////////////////////////////////////////
                    BOND EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testFeeCollectedEvent() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.expectEmit(true, true, false, true);
        emit BondManager.FeeCollected(address(testAgreement), protocolDeployer, FEE_AMOUNT);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));
    }

    function testBondDepositedEvent() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.expectEmit(true, true, false, true);
        emit BondManager.BondDeposited(address(testAgreement), protocolDeployer, VERIFIED_BOND);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));
    }

    function testBondSlashedEvent() public {
        contract1 = _deployContractViaBattleChain(protocolDeployer, bytes32(uint256(1)));
        address[] memory contracts = new address[](1);
        contracts[0] = contract1;
        Agreement testAgreement = _createAgreementWithContracts(protocolDeployer, contracts);

        vm.prank(protocolDeployer);
        attackRegistry.requestUnderAttack(address(testAgreement));

        vm.expectEmit(true, false, false, true);
        emit BondManager.BondSlashed(address(testAgreement), VERIFIED_BOND);

        vm.prank(registryModerator);
        attackRegistry.rejectAttackRequest(address(testAgreement), true);
    }
}
