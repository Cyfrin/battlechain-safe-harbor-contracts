// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { BattleChainSafeHarborRegistry } from "src/BattleChainSafeHarborRegistry.sol";
import { Agreement } from "src/Agreement.sol";
import { AgreementDetails } from "src/types/AgreementTypes.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DeployBattleChainSafeHarbor } from "script/Deploy.s.sol";
import { UpgradeBattleChainSafeHarbor } from "script/Upgrade.s.sol";
import { getMockAgreementDetails } from "test/utils/GetAgreementDetails.sol";

contract UpgradeTest is Test {
    address owner;
    string battleChainCaip2;

    BattleChainSafeHarborRegistry registry;
    BattleChainSafeHarborRegistry registryImpl;
    HelperConfig helperConfig;
    DeployBattleChainSafeHarbor deployer;
    UpgradeBattleChainSafeHarbor upgrader;

    Agreement agreement;
    address agreementAddress;

    function setUp() public {
        // Use HelperConfig and DeployBattleChainSafeHarbor for deployment
        helperConfig = new HelperConfig();
        deployer = new DeployBattleChainSafeHarbor();
        upgrader = new UpgradeBattleChainSafeHarbor();

        // Initialize deployer and upgrader with helperConfig
        deployer.initialize(helperConfig);
        upgrader.initialize(helperConfig);

        // Get network config
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getNetworkConfig();
        owner = networkConfig.owner;
        battleChainCaip2 = helperConfig.getBattleChainCaip2ChainId();

        // Deploy Registry Implementation
        registryImpl = BattleChainSafeHarborRegistry(deployer.deployRegistryImplementation());

        // Deploy Registry Proxy
        registry = BattleChainSafeHarborRegistry(deployer.deployRegistryProxy());

        // Create a test agreement
        AgreementDetails memory details = getMockAgreementDetails("0xaabbccdd", battleChainCaip2);
        vm.prank(owner);
        agreement = new Agreement(address(registry), owner, helperConfig.getBattleChainCaip2ChainId(), details);
        agreementAddress = address(agreement);
    }

    /*//////////////////////////////////////////////////////////////
                        UPGRADE SCRIPT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_upgradeWithScript() public {
        // Adopt an agreement first to have state to preserve
        address entity = address(0xee);
        vm.prank(entity);
        registry.adoptSafeHarbor(agreementAddress);

        // Verify state before upgrade
        assertEq(registry.getAgreement(entity), agreementAddress);
        assertTrue(registry.isChainValid(battleChainCaip2));
        string memory versionBefore = registry.version();

        // Deploy new implementation using the upgrade script
        address newImpl = upgrader.deployImplementation(type(BattleChainSafeHarborRegistry).creationCode, bytes11(keccak256("test.upgrade.v2")));

        // Upgrade directly on registry as owner
        vm.prank(owner);
        registry.upgradeToAndCall(newImpl, "");

        // Verify state is preserved
        assertEq(registry.getAgreement(entity), agreementAddress);
        assertTrue(registry.isChainValid(battleChainCaip2));
        assertEq(registry.version(), versionBefore);
    }

    function test_multipleUpgrades() public {
        // Adopt an agreement
        address entity = address(0xee);
        vm.prank(entity);
        registry.adoptSafeHarbor(agreementAddress);

        // First upgrade
        address newImpl1 = upgrader.deployImplementation(type(BattleChainSafeHarborRegistry).creationCode, bytes11(keccak256("test.upgrade.v2")));
        vm.prank(owner);
        registry.upgradeToAndCall(newImpl1, "");

        // Verify state after first upgrade
        assertEq(registry.getAgreement(entity), agreementAddress);

        // Add more state
        address entity2 = address(0xff);
        vm.prank(entity2);
        registry.adoptSafeHarbor(agreementAddress);

        // Second upgrade
        address newImpl2 = upgrader.deployImplementation(type(BattleChainSafeHarborRegistry).creationCode, bytes11(keccak256("test.upgrade.v3")));
        vm.prank(owner);
        registry.upgradeToAndCall(newImpl2, "");

        // Verify all state preserved
        assertEq(registry.getAgreement(entity), agreementAddress);
        assertEq(registry.getAgreement(entity2), agreementAddress);
        assertTrue(registry.isChainValid(battleChainCaip2));
    }

    function test_upgradeProxy_onlyOwner() public {
        // Deploy new implementation
        address newImpl = upgrader.deployImplementation(type(BattleChainSafeHarborRegistry).creationCode, bytes11(keccak256("test.upgrade.auth")));

        // Non-owner should fail
        address attacker = address(0xdead);
        vm.prank(attacker);
        vm.expectRevert();
        registry.upgradeToAndCall(newImpl, "");
    }

    function test_computeExpectedAddress() public {
        bytes11 entropy = bytes11(keccak256("test.compute.address"));
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getNetworkConfig();
        address expected = upgrader.computeExpectedAddress(networkConfig.deployer, entropy);

        // Should return a non-zero address
        assertTrue(expected != address(0));
    }

    function test_upgradeWithValidChains() public {
        // Add some valid chains before upgrade
        string[] memory newChains = new string[](1);
        newChains[0] = "eip155:627";

        vm.prank(owner);
        registry.setValidChains(newChains);

        // Verify chains are valid
        assertTrue(registry.isChainValid(battleChainCaip2));
        assertTrue(registry.isChainValid("eip155:627"));

        // Upgrade
        address newImpl = upgrader.deployImplementation(type(BattleChainSafeHarborRegistry).creationCode, bytes11(keccak256("test.upgrade.chains")));
        vm.prank(owner);
        registry.upgradeToAndCall(newImpl, "");

        // Verify chains still valid after upgrade
        assertTrue(registry.isChainValid(battleChainCaip2));
        assertTrue(registry.isChainValid("eip155:627"));
    }

    function test_upgradePreservesOwner() public {
        // Verify owner before upgrade
        assertEq(registry.owner(), owner);

        // Upgrade
        address newImpl = upgrader.deployImplementation(type(BattleChainSafeHarborRegistry).creationCode, bytes11(keccak256("test.upgrade.owner")));
        vm.prank(owner);
        registry.upgradeToAndCall(newImpl, "");

        // Verify owner preserved
        assertEq(registry.owner(), owner);
    }
}
