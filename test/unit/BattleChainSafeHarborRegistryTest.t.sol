// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { BattleChainSafeHarborRegistry } from "src/BattleChainSafeHarborRegistry.sol";
import { Agreement } from "src/Agreement.sol";
import { AgreementDetails } from "src/types/AgreementTypes.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DeployBattleChainSafeHarbor } from "script/Deploy.s.sol";
import { getMockAgreementDetails } from "test/utils/GetAgreementDetails.sol";
import { BATTLECHAIN_SAFE_HARBOR_VERSION } from "src/Version.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BattleChainSafeHarborRegistryTest is Test {
    address owner;
    string battleChainCaip2;

    BattleChainSafeHarborRegistry registry;
    BattleChainSafeHarborRegistry registryImpl;
    HelperConfig helperConfig;
    DeployBattleChainSafeHarbor deployer;

    Agreement agreement;
    address agreementAddress;

    function setUp() public {
        // Use HelperConfig and DeployBattleChainSafeHarbor for deployment
        helperConfig = new HelperConfig();
        deployer = new DeployBattleChainSafeHarbor();

        // Initialize deployer with helperConfig
        deployer.initialize(helperConfig);

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
        agreement = new Agreement(address(registry), owner, battleChainCaip2, details);
        agreementAddress = address(agreement);
    }

    /*//////////////////////////////////////////////////////////////
                          CHAIN VALIDITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setValidChains() public {
        string[] memory caip2ChainIds = new string[](2);
        caip2ChainIds[0] = "eip155:99999991";
        caip2ChainIds[1] = "eip155:99999992";

        // Should fail if not called by owner
        vm.expectRevert();
        registry.setValidChains(caip2ChainIds);

        // Should succeed if called by owner
        vm.expectEmit();
        emit BattleChainSafeHarborRegistry.ChainValiditySet(caip2ChainIds[0], true);
        vm.expectEmit();
        emit BattleChainSafeHarborRegistry.ChainValiditySet(caip2ChainIds[1], true);
        vm.prank(owner);
        registry.setValidChains(caip2ChainIds);

        // Verify chains are valid
        assertTrue(registry.isChainValid(battleChainCaip2)); // Already valid from deployment
        assertTrue(registry.isChainValid("eip155:99999991"));
        assertTrue(registry.isChainValid("eip155:99999992"));
        assertFalse(registry.isChainValid("eip155:88888888"));
    }

    function test_setInvalidChains() public {
        // First add some chains to remove
        string[] memory newChains = new string[](2);
        newChains[0] = "eip155:99999991";
        newChains[1] = "eip155:99999992";
        vm.prank(owner);
        registry.setValidChains(newChains);

        // Verify they're valid
        assertTrue(registry.isChainValid("eip155:99999991"));
        assertTrue(registry.isChainValid("eip155:99999992"));

        string[] memory invalidChains = new string[](1);
        invalidChains[0] = "eip155:99999992";

        // Should fail if not called by owner
        vm.expectRevert();
        registry.setInvalidChains(invalidChains);

        // Should succeed if called by owner
        vm.expectEmit();
        emit BattleChainSafeHarborRegistry.ChainValiditySet("eip155:99999992", false);
        vm.prank(owner);
        registry.setInvalidChains(invalidChains);

        assertTrue(registry.isChainValid("eip155:99999991"));
        assertFalse(registry.isChainValid("eip155:99999992"));
    }

    /*//////////////////////////////////////////////////////////////
                            ADOPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_adoptSafeHarbor() public {
        address entity = address(0xee);

        vm.expectEmit();
        emit BattleChainSafeHarborRegistry.BattleChainSafeHarborAdoption(entity, agreementAddress);
        vm.prank(entity);
        registry.adoptSafeHarbor(agreementAddress);
    }

    function test_getAgreement() public {
        address entity = address(0xee);

        vm.prank(entity);
        registry.adoptSafeHarbor(agreementAddress);
        address _agreement = registry.getAgreement(entity);
        assertEq(agreementAddress, _agreement);
    }

    function test_getAgreement_missing() public {
        address entity = address(0xee);

        vm.expectRevert(BattleChainSafeHarborRegistry.BattleChainSafeHarborRegistry__NoAgreement.selector);
        registry.getAgreement(entity);
    }

    function test_version() public view {
        assertEq(registry.version(), BATTLECHAIN_SAFE_HARBOR_VERSION);
    }

    /*//////////////////////////////////////////////////////////////
                            UPGRADE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_upgrade_onlyOwner() public {
        // Deploy a new implementation
        BattleChainSafeHarborRegistry newImpl = new BattleChainSafeHarborRegistry();

        // Should fail if not called by owner
        vm.expectRevert();
        registry.upgradeToAndCall(address(newImpl), "");

        // Should succeed if called by owner
        vm.prank(owner);
        registry.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_preservesState() public {
        // First adopt an agreement
        address entity = address(0xee);
        vm.prank(entity);
        registry.adoptSafeHarbor(agreementAddress);

        // Verify state before upgrade
        assertEq(registry.getAgreement(entity), agreementAddress);
        assertTrue(registry.isChainValid(battleChainCaip2));

        // Deploy new implementation and upgrade
        BattleChainSafeHarborRegistry newImpl = new BattleChainSafeHarborRegistry();
        vm.prank(owner);
        registry.upgradeToAndCall(address(newImpl), "");

        // Verify state is preserved after upgrade
        assertEq(registry.getAgreement(entity), agreementAddress);
        assertTrue(registry.isChainValid(battleChainCaip2));
    }

    function test_upgrade_cannotReinitialize() public {
        // Deploy new implementation and upgrade
        BattleChainSafeHarborRegistry newImpl = new BattleChainSafeHarborRegistry();
        vm.prank(owner);
        registry.upgradeToAndCall(address(newImpl), "");

        // Try to re-initialize - should fail
        string[] memory chains = new string[](1);
        chains[0] = "eip155:1";
        vm.expectRevert();
        registry.initialize(owner, chains, makeAddr("dummyFactory"), makeAddr("dummyAttackRegistry"));
    }

    function test_implementation_cannotBeInitialized() public {
        // The implementation contract should have initializers disabled
        string[] memory chains = new string[](1);
        chains[0] = "eip155:1";
        vm.expectRevert();
        registryImpl.initialize(owner, chains, makeAddr("dummyFactory"), makeAddr("dummyAttackRegistry"));
    }
}
