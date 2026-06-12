// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { BattleChainSafeHarborRegistry } from "src/BattleChainSafeHarborRegistry.sol";
import { AgreementFactory } from "src/AgreementFactory.sol";
import { Agreement } from "src/Agreement.sol";
import { AgreementDetails } from "src/types/AgreementTypes.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DeployBattleChainSafeHarbor } from "script/Deploy.s.sol";
import { getMockAgreementDetails } from "test/utils/GetAgreementDetails.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { OwnableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract AgreementFactoryTest is Test {
    BattleChainSafeHarborRegistry registry;
    AgreementFactory factory;
    HelperConfig helperConfig;
    DeployBattleChainSafeHarbor deployer;

    address owner;
    address protocol;
    string battleChainCaip2;

    function setUp() public {
        protocol = address(0xAB);

        // Use HelperConfig and DeployBattleChainSafeHarbor for deployment
        helperConfig = new HelperConfig();
        deployer = new DeployBattleChainSafeHarbor();

        // Initialize deployer with helperConfig
        deployer.initialize(helperConfig);

        // Get network config
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getNetworkConfig();
        owner = networkConfig.owner;
        battleChainCaip2 = helperConfig.getBattleChainCaip2ChainId();

        // Deploy Registry
        deployer.deployRegistryImplementation();
        registry = BattleChainSafeHarborRegistry(deployer.deployRegistryProxy());

        // Deploy the factory (now upgradeable)
        deployer.deployAgreementFactoryImplementation();
        factory = AgreementFactory(deployer.deployAgreementFactoryProxy());
    }

    function test_create() public {
        AgreementDetails memory agreementDetails = getMockAgreementDetails("0xAABB", battleChainCaip2);
        bytes32 salt = keccak256("test-salt");

        vm.prank(protocol);
        address agreementAddress = factory.create(agreementDetails, protocol, salt);

        Agreement agreement = Agreement(agreementAddress);
        AgreementDetails memory storedDetails = agreement.getDetails();
        assertEq(keccak256(abi.encode(storedDetails)), keccak256(abi.encode(agreementDetails)));
        assertEq(agreement.owner(), protocol, "Agreement owner should be protocol");
    }

    function test_create_multipleAgreements() public {
        AgreementDetails memory details1 = getMockAgreementDetails("0xAABB", battleChainCaip2);

        // Create first agreement
        vm.prank(protocol);
        address agreement1 = factory.create(details1, protocol, keccak256("salt1"));

        // Create second agreement with different details
        AgreementDetails memory details2 = getMockAgreementDetails("0xCCDD", battleChainCaip2);
        address protocol2 = address(0xCD);
        vm.prank(protocol2);
        address agreement2 = factory.create(details2, protocol2, keccak256("salt2"));

        // Verify they're different contracts
        assertTrue(agreement1 != agreement2, "Agreements should be at different addresses");

        // Verify each has correct owner
        assertEq(Agreement(agreement1).owner(), protocol);
        assertEq(Agreement(agreement2).owner(), protocol2);
    }

    function test_sameSaltDifferentSenders() public {
        AgreementDetails memory agreementDetails = getMockAgreementDetails("0xAABB", battleChainCaip2);
        bytes32 salt = keccak256("same-salt");

        // Deploy from protocol 1
        vm.prank(protocol);
        address agreement1 = factory.create(agreementDetails, protocol, salt);

        // Deploy from protocol 2 with same salt
        address protocol2 = address(0xCD);
        vm.prank(protocol2);
        address agreement2 = factory.create(agreementDetails, protocol2, salt);

        // Addresses should be different due to msg.sender in salt
        assertTrue(agreement1 != agreement2, "Same salt should produce different addresses for different senders");
    }

    function test_sameSaltDifferentChains() public {
        AgreementDetails memory agreementDetails = getMockAgreementDetails("0xAABB", battleChainCaip2);
        bytes32 salt = keccak256("same-salt");

        // Deploy on "chain 1" (current chain)
        vm.prank(protocol);
        address agreement1 = factory.create(agreementDetails, protocol, salt);

        // Simulate different chain by changing chainid
        vm.chainId(627); // BattleChain Testnet

        // Deploy with same salt on "chain 2"
        vm.prank(protocol);
        address agreement2 = factory.create(agreementDetails, protocol, salt);

        // Addresses should be different due to chainid in salt
        assertTrue(agreement1 != agreement2, "Same salt should produce different addresses on different chains");
    }

    function test_registryAddress() public view {
        assertEq(factory.getRegistry(), address(registry));
    }

    function test_getBattleChainCaip2ChainId() public view {
        // The factory should return the BattleChain CAIP-2 chain ID
        string memory chainId = factory.getBattleChainCaip2ChainId();
        assertTrue(bytes(chainId).length > 0, "BattleChain CAIP-2 chain ID should not be empty");
    }

    function test_isAgreementContract() public {
        AgreementDetails memory agreementDetails = getMockAgreementDetails("0xAABB", battleChainCaip2);
        bytes32 salt = keccak256("test-is-agreement");

        vm.prank(protocol);
        address agreementAddress = factory.create(agreementDetails, protocol, salt);

        // Should be tracked as an agreement
        assertTrue(factory.isAgreementContract(agreementAddress), "Created agreement should be tracked");
    }

    function test_isAgreementContract_notAgreement() public view {
        // Random address should not be considered an agreement
        address randomAddress = address(0x1234);
        assertFalse(factory.isAgreementContract(randomAddress), "Random address should not be an agreement");
    }

    function test_initialize_zeroOwner() public {
        AgreementFactory impl = new AgreementFactory();
        bytes memory initData =
            abi.encodeWithSelector(AgreementFactory.initialize.selector, address(0), address(registry), battleChainCaip2);
        // Reverts via OZ's __Ownable_init (zero check now lives downstream)
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0))
        );
        new ERC1967Proxy(address(impl), initData);
    }

    function test_initialize_zeroRegistry() public {
        AgreementFactory impl = new AgreementFactory();
        bytes memory initData =
            abi.encodeWithSelector(AgreementFactory.initialize.selector, owner, address(0), battleChainCaip2);
        vm.expectRevert(AgreementFactory.AgreementFactory__ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_create_emitsEvent() public {
        AgreementDetails memory agreementDetails = getMockAgreementDetails("0xAABB", battleChainCaip2);
        bytes32 salt = keccak256("test-event");

        vm.prank(protocol);
        vm.expectEmit(false, true, true, false);
        emit AgreementFactory.AgreementCreated(address(0), protocol, salt);
        factory.create(agreementDetails, protocol, salt);
    }
}
