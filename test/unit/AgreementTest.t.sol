// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
import { BattleChainSafeHarborRegistry } from "src/BattleChainSafeHarborRegistry.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DeployBattleChainSafeHarbor } from "script/Deploy.s.sol";
import { getMockAgreementDetails } from "test/utils/GetAgreementDetails.sol";

contract AgreementTest is Test {
    uint256 mockKey;
    address mockAddress;
    address owner;
    string battleChainCaip2;

    Agreement agreement;
    BattleChainSafeHarborRegistry registry;
    HelperConfig helperConfig;
    DeployBattleChainSafeHarbor deployer;

    function setUp() public {
        mockKey = 0xA113;
        mockAddress = vm.addr(mockKey);

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

        // Create a test agreement
        AgreementDetails memory details = getMockAgreementDetails("0x01", battleChainCaip2);
        vm.prank(owner);
        agreement = new Agreement(address(registry), owner, battleChainCaip2, details);
    }

    /*//////////////////////////////////////////////////////////////
                            BASIC TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwner() public view {
        assertEq(agreement.owner(), owner);
        assertFalse(agreement.owner() == address(0x02));
    }

    function testGetDetails() public view {
        AgreementDetails memory _details = agreement.getDetails();
        AgreementDetails memory expectedDetails = getMockAgreementDetails("0x01", battleChainCaip2);
        assertEq(keccak256(abi.encode(expectedDetails)), keccak256(abi.encode(_details)));
    }

    /*//////////////////////////////////////////////////////////////
                          PROTOCOL NAME TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetProtocolName() public {
        string memory newName = "Updated Protocol";

        // Should fail when called by non-owner
        vm.expectRevert();
        agreement.setProtocolName(newName);

        // Should succeed when called by owner
        vm.prank(owner);
        agreement.setProtocolName(newName);

        AgreementDetails memory _details = agreement.getDetails();
        assertEq(_details.protocolName, newName);
    }

    /*//////////////////////////////////////////////////////////////
                        CONTACT DETAILS TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetContactDetails() public {
        Contact[] memory newContacts = new Contact[](2);
        newContacts[0] = Contact({ name: "New Contact 1", contact: "@newcontact1" });

        // Should fail when called by non-owner
        vm.expectRevert();
        agreement.setContactDetails(newContacts);

        // Should succeed when called by owner
        vm.prank(owner);
        agreement.setContactDetails(newContacts);

        AgreementDetails memory _details = agreement.getDetails();
        assertEq(keccak256(abi.encode(newContacts)), keccak256(abi.encode(_details.contactDetails)));
    }

    /*//////////////////////////////////////////////////////////////
                            CHAIN TESTS
    //////////////////////////////////////////////////////////////*/

    function testAddOrSetChains() public {
        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({ accountAddress: "0x04", childContractScope: ChildContractScope.None });

        // Test adding a new chain via addOrSetChains
        BCChain[] memory newChains = new BCChain[](1);
        newChains[0] = BCChain({ assetRecoveryAddress: "0x05", accounts: accounts, caip2ChainId: "eip155:627" });

        // Should fail when called by non-owner
        vm.expectRevert();
        agreement.addOrSetChains(newChains);

        // Should succeed when called by owner - adds new chain
        vm.prank(owner);
        agreement.addOrSetChains(newChains);

        AgreementDetails memory details = agreement.getDetails();
        assertEq(details.chains.length, 2); // Original chain + new chain

        // Now test updating an existing chain via addOrSetChains
        BCAccount[] memory updatedAccounts = new BCAccount[](1);
        updatedAccounts[0] = BCAccount({ accountAddress: "0x99", childContractScope: ChildContractScope.All });

        BCChain[] memory updateChains = new BCChain[](1);
        updateChains[0] =
            BCChain({ assetRecoveryAddress: "0x88", accounts: updatedAccounts, caip2ChainId: "eip155:627" });

        vm.prank(owner);
        agreement.addOrSetChains(updateChains);

        details = agreement.getDetails();
        assertEq(details.chains.length, 2); // Should still be 2 chains
    }

    function testRemoveChains() public {
        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({ accountAddress: "0x01", childContractScope: ChildContractScope.None });

        BCChain[] memory newChains = new BCChain[](1);
        newChains[0] = BCChain({ assetRecoveryAddress: "0x05", accounts: accounts, caip2ChainId: "eip155:627" });

        vm.prank(owner);
        agreement.addOrSetChains(newChains);

        // Should fail when called by non-owner
        vm.expectRevert();
        string[] memory chainToRemove = new string[](1);
        chainToRemove[0] = "eip155:627";
        agreement.removeChains(chainToRemove);

        // Should fail when removing non-existent chain
        vm.prank(owner);
        vm.expectRevert();
        string[] memory nonExistentChain = new string[](1);
        nonExistentChain[0] = "eip155:99999999";
        agreement.removeChains(nonExistentChain);

        // Should succeed when called by owner
        vm.prank(owner);
        agreement.removeChains(chainToRemove);

        // Verify the change
        AgreementDetails memory _details = agreement.getDetails();
        AgreementDetails memory expectedDetails = getMockAgreementDetails("0x01", battleChainCaip2);
        assertEq(keccak256(abi.encode(_details)), keccak256(abi.encode(expectedDetails)));
    }

    /*//////////////////////////////////////////////////////////////
                           ACCOUNT TESTS
    //////////////////////////////////////////////////////////////*/

    function testAddAccounts() public {
        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000002", childContractScope: ChildContractScope.None
        });

        // Should fail when called by non-owner
        vm.expectRevert();
        agreement.addAccounts(battleChainCaip2, accounts);

        // Should fail when adding to non-existent chain
        vm.prank(owner);
        vm.expectRevert();
        agreement.addAccounts("eip155:999", accounts);

        // Should succeed when called by owner
        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, accounts);

        // Verify the change
        AgreementDetails memory _details = agreement.getDetails();
        BCAccount memory _account = _details.chains[0].accounts[_details.chains[0].accounts.length - 1];

        assertEq(keccak256(abi.encode(accounts[0])), keccak256(abi.encode(_account)));
    }

    function testRemoveAccounts() public {
        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000002", childContractScope: ChildContractScope.None
        });

        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, accounts);

        // Should fail when called by non-owner
        vm.expectRevert();
        string[] memory accountToRemove = new string[](1);
        accountToRemove[0] = "0x0000000000000000000000000000000000000002";
        agreement.removeAccounts(battleChainCaip2, accountToRemove);

        // Should fail when removing from non-existent chain
        vm.prank(owner);
        vm.expectRevert();
        agreement.removeAccounts("eip155:999", accountToRemove);

        // Should fail when removing non-existent account
        vm.prank(owner);
        vm.expectRevert();
        string[] memory nonExistentAccount = new string[](1);
        nonExistentAccount[0] = "0x0000000000000000000000000000000000000999";
        agreement.removeAccounts(battleChainCaip2, nonExistentAccount);

        // Should succeed when called by owner
        vm.prank(owner);
        agreement.removeAccounts(battleChainCaip2, accountToRemove);

        // Verify the change - should be back to original state
        AgreementDetails memory _details = agreement.getDetails();
        AgreementDetails memory expectedDetails = getMockAgreementDetails("0x01", battleChainCaip2);
        assertEq(keccak256(abi.encode(_details)), keccak256(abi.encode(expectedDetails)));
    }

    /*//////////////////////////////////////////////////////////////
                         BOUNTY TERMS TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetBountyTerms() public {
        AgreementDetails memory initialDetails = getMockAgreementDetails("0x01", battleChainCaip2);
        BountyTerms memory newTerms = initialDetails.bountyTerms;
        newTerms.bountyPercentage = 20;
        newTerms.bountyCapUsd = 2_000_000;
        // Must set aggregateBountyCapUsd >= bountyCapUsd or 0 (no aggregate cap)
        newTerms.aggregateBountyCapUsd = 0;

        // Should fail when called by non-owner
        vm.expectRevert();
        agreement.setBountyTerms(newTerms);

        // Should succeed when called by owner
        vm.prank(owner);
        agreement.setBountyTerms(newTerms);

        // Verify the change
        AgreementDetails memory _details = agreement.getDetails();
        assertEq(keccak256(abi.encode(newTerms)), keccak256(abi.encode(_details.bountyTerms)));

        // Should fail when trying to set both aggregateBountyCapUsd and retainable
        newTerms.aggregateBountyCapUsd = 5_000_000;
        newTerms.retainable = true;
        vm.prank(owner);
        vm.expectRevert(Agreement.Agreement__CannotSetBothAggregateBountyCapUsdAndRetainable.selector);
        agreement.setBountyTerms(newTerms);
    }

    function testSetBountyTermsValidation() public {
        BountyTerms memory terms = agreement.getBountyTerms();

        // Test bounty percentage > 100 should fail
        terms.bountyPercentage = 101;
        terms.aggregateBountyCapUsd = 0;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Agreement.Agreement__BountyPercentageExceedsMax.selector, 101));
        agreement.setBountyTerms(terms);

        // Test aggregate cap < individual cap should fail
        terms.bountyPercentage = 10;
        terms.bountyCapUsd = 1_000_000;
        terms.aggregateBountyCapUsd = 500_000; // Less than individual cap
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Agreement.Agreement__AggregateBountyCapBelowIndividualCap.selector, 500_000, 1_000_000
            )
        );
        agreement.setBountyTerms(terms);

        // Test valid aggregate cap >= individual cap should succeed
        terms.aggregateBountyCapUsd = 2_000_000;
        vm.prank(owner);
        agreement.setBountyTerms(terms);
    }

    /*//////////////////////////////////////////////////////////////
            COMMITMENT-WINDOW FAVORABILITY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Initial mock state: diligenceRequirements = "none", aggregateBountyCapUsd = 1000.
    ///      Each test opens the commitment window via extendCommitmentWindow, then verifies
    ///      the favorability rules in setBountyTerms.

    function testSetBountyTerms_diligenceRequirements_inWindow() public {
        BountyTerms memory current = agreement.getBountyTerms();
        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 30 days);

        // In-window: replacing existing requirements with new requirements is blocked
        // (this is the attack: protocol introduces stricter diligence mid-commitment).
        BountyTerms memory tighter = current;
        tighter.diligenceRequirements = "must be US citizen";
        vm.prank(owner);
        vm.expectRevert(Agreement.Agreement__UnfavorableBountyChange.selector);
        agreement.setBountyTerms(tighter);

        // In-window: any in-place edit (even a typo "fix") is blocked since string comparison
        // cannot distinguish relaxation from tightening.
        BountyTerms memory rephrased = current;
        rephrased.diligenceRequirements = "non";
        vm.prank(owner);
        vm.expectRevert(Agreement.Agreement__UnfavorableBountyChange.selector);
        agreement.setBountyTerms(rephrased);

        // In-window: clearing to empty is allowed (unambiguously favorable).
        BountyTerms memory cleared = current;
        cleared.diligenceRequirements = "";
        vm.prank(owner);
        agreement.setBountyTerms(cleared);
        assertEq(agreement.getBountyTerms().diligenceRequirements, "");

        // In-window: unchanged value is allowed (no-op).
        BountyTerms memory unchanged = agreement.getBountyTerms();
        vm.prank(owner);
        agreement.setBountyTerms(unchanged);
    }

    function testSetBountyTerms_diligenceRequirements_outOfWindow() public {
        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 1 days);
        vm.warp(block.timestamp + 2 days);

        BountyTerms memory newTerms = agreement.getBountyTerms();
        newTerms.diligenceRequirements = "must be US citizen and complete KYC";
        vm.prank(owner);
        agreement.setBountyTerms(newTerms);
        assertEq(
            agreement.getBountyTerms().diligenceRequirements, "must be US citizen and complete KYC"
        );
    }

    function testSetBountyTerms_aggregateBountyCapUsd_inWindow_blocksAddingCap() public {
        // Clear the cap before opening the window, so we can test the 0 -> non-zero transition.
        BountyTerms memory uncapped = agreement.getBountyTerms();
        uncapped.aggregateBountyCapUsd = 0;
        vm.prank(owner);
        agreement.setBountyTerms(uncapped);

        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 30 days);

        // In-window: adding a cap (0 -> non-zero) is blocked.
        BountyTerms memory addCap = uncapped;
        addCap.aggregateBountyCapUsd = 5_000;
        vm.prank(owner);
        vm.expectRevert(Agreement.Agreement__UnfavorableBountyChange.selector);
        agreement.setBountyTerms(addCap);
    }

    function testSetBountyTerms_aggregateBountyCapUsd_inWindow_blocksLowering() public {
        // Mock starts with aggregateBountyCapUsd = 1000.
        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 30 days);

        // In-window: lowering the cap (non-zero -> smaller non-zero) is blocked.
        BountyTerms memory lower = agreement.getBountyTerms();
        lower.aggregateBountyCapUsd = 500;
        vm.prank(owner);
        vm.expectRevert(Agreement.Agreement__UnfavorableBountyChange.selector);
        agreement.setBountyTerms(lower);
    }

    function testSetBountyTerms_aggregateBountyCapUsd_inWindow_allowsRaising() public {
        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 30 days);

        // In-window: raising the cap (non-zero -> larger non-zero) is allowed.
        BountyTerms memory higher = agreement.getBountyTerms();
        higher.aggregateBountyCapUsd = 5_000;
        vm.prank(owner);
        agreement.setBountyTerms(higher);
        assertEq(agreement.getBountyTerms().aggregateBountyCapUsd, 5_000);
    }

    function testSetBountyTerms_aggregateBountyCapUsd_inWindow_allowsRemoving() public {
        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 30 days);

        // In-window: removing the cap (non-zero -> 0) is allowed.
        BountyTerms memory removeCap = agreement.getBountyTerms();
        removeCap.aggregateBountyCapUsd = 0;
        vm.prank(owner);
        agreement.setBountyTerms(removeCap);
        assertEq(agreement.getBountyTerms().aggregateBountyCapUsd, 0);
    }

    function testSetBountyTerms_aggregateBountyCapUsd_outOfWindow() public {
        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 1 days);
        vm.warp(block.timestamp + 2 days);

        // After the window: any change is allowed, including adding a cap from 0.
        BountyTerms memory uncapped = agreement.getBountyTerms();
        uncapped.aggregateBountyCapUsd = 0;
        vm.prank(owner);
        agreement.setBountyTerms(uncapped);

        BountyTerms memory addCap = uncapped;
        addCap.aggregateBountyCapUsd = 500;
        vm.prank(owner);
        agreement.setBountyTerms(addCap);
        assertEq(agreement.getBountyTerms().aggregateBountyCapUsd, 500);
    }

    /*//////////////////////////////////////////////////////////////
                        AGREEMENT URI TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetAgreementURI() public {
        string memory newURI = "ipfs://newHash";

        // Should fail when called by non-owner
        vm.expectRevert();
        agreement.setAgreementURI(newURI);

        // Should succeed when called by owner
        vm.prank(owner);
        agreement.setAgreementURI(newURI);

        // Verify the change
        assertEq(agreement.getAgreementURI(), newURI);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function testRemoveChainsLastElement() public {
        // The agreement starts with one chain (eip155:626)
        // Remove it - this tests the idx == lastIdx branch
        string[] memory chainToRemove = new string[](1);
        chainToRemove[0] = battleChainCaip2;

        vm.prank(owner);
        agreement.removeChains(chainToRemove);

        // Verify chain was removed
        string[] memory chainIds = agreement.getChainIds();
        assertEq(chainIds.length, 0);
    }

    function testRemoveAccountsLastElement() public {
        // First add a second account so we can test the idx == lastIdx branch
        // while still leaving one account (since removing all accounts is now blocked)
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000002", childContractScope: ChildContractScope.All
        });
        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, newAccounts);

        // Now remove the second account (tests the idx == lastIdx branch)
        string[] memory accountToRemove = new string[](1);
        accountToRemove[0] = "0x0000000000000000000000000000000000000002";

        vm.prank(owner);
        agreement.removeAccounts(battleChainCaip2, accountToRemove);

        // Verify one account remains
        AgreementDetails memory _details = agreement.getDetails();
        assertEq(_details.chains[0].accounts.length, 1);
    }

    function testRemoveAccountsCannotRemoveAll() public {
        // The agreement starts with one account on eip155:626
        // Trying to remove all accounts should revert
        string[] memory accountToRemove = new string[](1);
        accountToRemove[0] = "0x0000000000000000000000000000000000000001";

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Agreement.Agreement__CannotRemoveAllAccounts.selector, battleChainCaip2));
        agreement.removeAccounts(battleChainCaip2, accountToRemove);
    }

    function testRemoveAccountsFromNonExistentChain() public {
        string[] memory accountToRemove = new string[](1);
        accountToRemove[0] = "0x0000000000000000000000000000000000000001";

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Agreement.Agreement__ChainNotFoundByCaip2Id.selector, "eip155:999"));
        agreement.removeAccounts("eip155:999", accountToRemove);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testInitializeCannotSetBothAggregateBountyCapUsdAndRetainable() public {
        AgreementDetails memory invalidDetails = getMockAgreementDetails("0x01", battleChainCaip2);
        invalidDetails.bountyTerms.aggregateBountyCapUsd = 1000;
        invalidDetails.bountyTerms.retainable = true;

        string memory caip2 = helperConfig.getBattleChainCaip2ChainId();
        vm.expectRevert(Agreement.Agreement__CannotSetBothAggregateBountyCapUsdAndRetainable.selector);
        new Agreement(address(registry), owner, caip2, invalidDetails);
    }

    function testInitializeDuplicateChainValidation() public {
        AgreementDetails memory baseDetails = getMockAgreementDetails("0x01", battleChainCaip2);

        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({ accountAddress: "0x01", childContractScope: ChildContractScope.All });

        BCChain memory chain = BCChain({ accounts: accounts, assetRecoveryAddress: "0x01", caip2ChainId: battleChainCaip2 });

        BCChain[] memory duplicateChains = new BCChain[](2);
        duplicateChains[0] = chain;
        duplicateChains[1] = chain;

        AgreementDetails memory invalidDetails = AgreementDetails({
            protocolName: "testProtocol",
            chains: duplicateChains,
            contactDetails: baseDetails.contactDetails,
            bountyTerms: baseDetails.bountyTerms,
            agreementURI: "ipfs://testHash"
        });

        string memory caip2 = helperConfig.getBattleChainCaip2ChainId();
        vm.expectRevert(abi.encodeWithSelector(Agreement.Agreement__DuplicateChainId.selector, battleChainCaip2));
        new Agreement(address(registry), owner, caip2, invalidDetails);
    }

    function testInitializeInvalidChainValidation() public {
        AgreementDetails memory baseDetails = getMockAgreementDetails("0x01", battleChainCaip2);

        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({ accountAddress: "0x01", childContractScope: ChildContractScope.All });

        BCChain memory chain =
            BCChain({ accounts: accounts, assetRecoveryAddress: "0x01", caip2ChainId: "eip155:99999999" });

        BCChain[] memory invalidChains = new BCChain[](1);
        invalidChains[0] = chain;

        AgreementDetails memory invalidDetails = AgreementDetails({
            protocolName: "testProtocol",
            chains: invalidChains,
            contactDetails: baseDetails.contactDetails,
            bountyTerms: baseDetails.bountyTerms,
            agreementURI: "ipfs://testHash"
        });

        string memory caip2 = helperConfig.getBattleChainCaip2ChainId();
        vm.expectRevert(abi.encodeWithSelector(Agreement.Agreement__InvalidChainId.selector, "eip155:99999999"));
        new Agreement(address(registry), owner, caip2, invalidDetails);
    }

    function testConstructorZeroRegistryAddress() public {
        string memory caip2 = helperConfig.getBattleChainCaip2ChainId();
        AgreementDetails memory details = getMockAgreementDetails("0x01", battleChainCaip2);
        vm.expectRevert(Agreement.Agreement__ZeroAddress.selector);
        new Agreement(address(0), owner, caip2, details);
    }

    function testInitializeZeroAccountsValidation() public {
        AgreementDetails memory baseDetails = getMockAgreementDetails("0x01", battleChainCaip2);

        BCAccount[] memory emptyAccounts = new BCAccount[](0);

        BCChain memory chain =
            BCChain({ accounts: emptyAccounts, assetRecoveryAddress: "0x01", caip2ChainId: battleChainCaip2 });

        BCChain[] memory chainsWithNoAccounts = new BCChain[](1);
        chainsWithNoAccounts[0] = chain;

        AgreementDetails memory invalidDetails = AgreementDetails({
            protocolName: "testProtocol",
            chains: chainsWithNoAccounts,
            contactDetails: baseDetails.contactDetails,
            bountyTerms: baseDetails.bountyTerms,
            agreementURI: "ipfs://testHash"
        });

        string memory caip2 = helperConfig.getBattleChainCaip2ChainId();
        vm.expectRevert(abi.encodeWithSelector(Agreement.Agreement__ZeroAccountsForChainId.selector, battleChainCaip2));
        new Agreement(address(registry), owner, caip2, invalidDetails);
    }

    function testInitializeInvalidAssetRecoveryAddress() public {
        AgreementDetails memory baseDetails = getMockAgreementDetails("0x01", battleChainCaip2);

        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({ accountAddress: "0x01", childContractScope: ChildContractScope.All });

        BCChain memory chain = BCChain({
            accounts: accounts,
            assetRecoveryAddress: "", // Empty recovery address
            caip2ChainId: battleChainCaip2
        });

        BCChain[] memory chainsWithInvalidRecovery = new BCChain[](1);
        chainsWithInvalidRecovery[0] = chain;

        AgreementDetails memory invalidDetails = AgreementDetails({
            protocolName: "testProtocol",
            chains: chainsWithInvalidRecovery,
            contactDetails: baseDetails.contactDetails,
            bountyTerms: baseDetails.bountyTerms,
            agreementURI: "ipfs://testHash"
        });

        string memory caip2 = helperConfig.getBattleChainCaip2ChainId();
        vm.expectRevert(abi.encodeWithSelector(Agreement.Agreement__InvalidAssetRecoveryAddress.selector, battleChainCaip2));
        new Agreement(address(registry), owner, caip2, invalidDetails);
    }

    function testInitializeZeroLengthChainId() public {
        AgreementDetails memory baseDetails = getMockAgreementDetails("0x01", battleChainCaip2);

        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({ accountAddress: "0x01", childContractScope: ChildContractScope.All });

        BCChain memory chain = BCChain({
            accounts: accounts,
            assetRecoveryAddress: "0x01",
            caip2ChainId: "" // Empty chain ID
        });

        BCChain[] memory chainsWithEmptyId = new BCChain[](1);
        chainsWithEmptyId[0] = chain;

        AgreementDetails memory invalidDetails = AgreementDetails({
            protocolName: "testProtocol",
            chains: chainsWithEmptyId,
            contactDetails: baseDetails.contactDetails,
            bountyTerms: baseDetails.bountyTerms,
            agreementURI: "ipfs://testHash"
        });

        string memory caip2 = helperConfig.getBattleChainCaip2ChainId();
        vm.expectRevert(Agreement.Agreement__ChainIdHasZeroLength.selector);
        new Agreement(address(registry), owner, caip2, invalidDetails);
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetters() public view {
        // Test getProtocolName
        string memory protocolName = agreement.getProtocolName();
        assertEq(protocolName, "testProtocol");

        // Test getBountyTerms
        BountyTerms memory terms = agreement.getBountyTerms();
        assertEq(terms.bountyPercentage, 10);
        assertEq(terms.bountyCapUsd, 100);

        // Test getAgreementURI
        string memory uri = agreement.getAgreementURI();
        assertEq(uri, "ipfs://testHash");

        // Test getRegistry
        address registryAddress = agreement.getRegistry();
        assertEq(registryAddress, address(registry));

        // Test getChainIds
        string[] memory chainIds = agreement.getChainIds();
        assertEq(chainIds.length, 1);
        assertEq(chainIds[0], battleChainCaip2);
    }

    /*//////////////////////////////////////////////////////////////
                    BATTLECHAIN SCOPE CACHE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetBattleChainScopeAddresses() public view {
        // The mock agreement details have "0x01" as the account address
        // This should be parsed to the native address
        address[] memory scopeAddresses = agreement.getBattleChainScopeAddresses();
        assertEq(scopeAddresses.length, 1);
        assertEq(scopeAddresses[0], address(0x01));
    }

    function testGetBattleChainScopeCount() public view {
        uint256 count = agreement.getBattleChainScopeCount();
        assertEq(count, 1);
    }

    function testIsContractInScope() public view {
        // address(0x01) should be in scope (from the initial agreement)
        assertTrue(agreement.isContractInScope(address(0x01)));
        // Random address should not be in scope
        assertFalse(agreement.isContractInScope(address(0x999)));
    }

    function testAddAccountsUpdatesBattleChainCache() public {
        // Add a new account to BattleChain chain
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000ABC", childContractScope: ChildContractScope.None
        });

        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, newAccounts);

        // Verify cache is updated
        assertEq(agreement.getBattleChainScopeCount(), 2);
        assertTrue(agreement.isContractInScope(address(0x0ABC)));

        address[] memory scopeAddresses = agreement.getBattleChainScopeAddresses();
        assertEq(scopeAddresses.length, 2);
    }

    function testRemoveAccountsUpdatesBattleChainCache() public {
        // First add an account
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000ABC", childContractScope: ChildContractScope.None
        });

        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, newAccounts);
        assertEq(agreement.getBattleChainScopeCount(), 2);

        // Now remove it
        string[] memory accountsToRemove = new string[](1);
        accountsToRemove[0] = "0x0000000000000000000000000000000000000ABC";

        vm.prank(owner);
        agreement.removeAccounts(battleChainCaip2, accountsToRemove);

        // Verify cache is updated
        assertEq(agreement.getBattleChainScopeCount(), 1);
        assertFalse(agreement.isContractInScope(address(0x0ABC)));
    }

    function testAddChainUpdatesBattleChainCache() public {
        // Add a non-BattleChain chain first - should NOT update cache
        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000DEF", childContractScope: ChildContractScope.None
        });

        BCChain[] memory newChains = new BCChain[](1);
        newChains[0] = BCChain({
            assetRecoveryAddress: "0x05",
            accounts: accounts,
            caip2ChainId: "eip155:627" // Testnet, not mainnet
        });

        vm.prank(owner);
        agreement.addOrSetChains(newChains);

        // Cache should still be 1 (only mainnet accounts)
        assertEq(agreement.getBattleChainScopeCount(), 1);
        assertFalse(agreement.isContractInScope(address(0x0DEF)));
    }

    function testRemoveBattleChainClearsBattleChainCache() public {
        // Remove the BattleChain chain
        string[] memory chainsToRemove = new string[](1);
        chainsToRemove[0] = battleChainCaip2;

        vm.prank(owner);
        agreement.removeChains(chainsToRemove);

        // Cache should be cleared
        assertEq(agreement.getBattleChainScopeCount(), 0);
        assertFalse(agreement.isContractInScope(address(0x01)));

        address[] memory scopeAddresses = agreement.getBattleChainScopeAddresses();
        assertEq(scopeAddresses.length, 0);
    }

    function testAddOrSetChainUpdateExistingBattleChainScope() public {
        // Update the BattleChain chain with new accounts
        BCAccount[] memory newAccounts = new BCAccount[](2);
        newAccounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000AAA", childContractScope: ChildContractScope.None
        });
        newAccounts[1] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000BBB", childContractScope: ChildContractScope.None
        });

        BCChain[] memory updateChains = new BCChain[](1);
        updateChains[0] = BCChain({ assetRecoveryAddress: "0x88", accounts: newAccounts, caip2ChainId: battleChainCaip2 });

        vm.prank(owner);
        agreement.addOrSetChains(updateChains);

        // Cache should now have 2 new addresses (replacing the old one)
        assertEq(agreement.getBattleChainScopeCount(), 2);
        assertTrue(agreement.isContractInScope(address(0x0AAA)));
        assertTrue(agreement.isContractInScope(address(0x0BBB)));
        assertFalse(agreement.isContractInScope(address(0x01))); // Original should be gone
    }

    function testBattleChainScopeCacheWithLowercaseAddress() public {
        // Add account with lowercase hex
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: "0x00000000000000000000000000000000000abc01", childContractScope: ChildContractScope.None
        });

        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, newAccounts);

        // Should be in scope
        assertTrue(agreement.isContractInScope(address(0xABC01)));
    }

    function testBattleChainScopeCacheWithUppercaseAddress() public {
        // Add account with uppercase hex
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: "0x00000000000000000000000000000000000ABC02", childContractScope: ChildContractScope.None
        });

        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, newAccounts);

        // Should be in scope
        assertTrue(agreement.isContractInScope(address(0xABC02)));
    }

    function testBattleChainScopeCacheWithMixedCaseAddress() public {
        // Add account with mixed case hex
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: "0x00000000000000000000000000000000000AbC03", childContractScope: ChildContractScope.None
        });

        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, newAccounts);

        // Should be in scope
        assertTrue(agreement.isContractInScope(address(0xABC03)));
    }

    function testInvalidShortAddressReverts() public {
        // Short addresses should revert since _parseAddress requires 40 hex chars
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({ accountAddress: "0x123", childContractScope: ChildContractScope.None });

        vm.prank(owner);
        vm.expectRevert(Agreement.Agreement__InvalidAddressLength.selector);
        agreement.addAccounts(battleChainCaip2, newAccounts);
    }

    function testBattleChainCaip2ChainIdGetter() public view {
        string memory caip2 = agreement.getBattleChainCaip2ChainId();
        assertEq(caip2, battleChainCaip2);
    }

    /*//////////////////////////////////////////////////////////////
                COMMITMENT WINDOW SCOPE PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testRemoveChainsBlockedDuringCommitmentWindow() public {
        // First add a second chain so we can try to remove it
        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000002", childContractScope: ChildContractScope.None
        });

        BCChain[] memory newChains = new BCChain[](1);
        newChains[0] = BCChain({ assetRecoveryAddress: "0x05", accounts: accounts, caip2ChainId: "eip155:627" });

        vm.prank(owner);
        agreement.addOrSetChains(newChains);

        // Set commitment window to 30 days from now
        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 30 days);

        // Try to remove the chain - should fail
        string[] memory chainToRemove = new string[](1);
        chainToRemove[0] = "eip155:627";

        vm.prank(owner);
        vm.expectRevert(Agreement.Agreement__CannotReduceScopeDuringCommitment.selector);
        agreement.removeChains(chainToRemove);

        // Fast forward past commitment window
        vm.warp(block.timestamp + 31 days);

        // Now it should succeed
        vm.prank(owner);
        agreement.removeChains(chainToRemove);

        // Verify chain was removed
        string[] memory chainIds = agreement.getChainIds();
        assertEq(chainIds.length, 1);
    }

    function testRemoveAccountsBlockedDuringCommitmentWindow() public {
        // First add a second account so we can try to remove it
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000ABC", childContractScope: ChildContractScope.None
        });

        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, newAccounts);
        assertEq(agreement.getBattleChainScopeCount(), 2);

        // Set commitment window to 30 days from now
        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 30 days);

        // Try to remove the account - should fail
        string[] memory accountToRemove = new string[](1);
        accountToRemove[0] = "0x0000000000000000000000000000000000000ABC";

        vm.prank(owner);
        vm.expectRevert(Agreement.Agreement__CannotReduceScopeDuringCommitment.selector);
        agreement.removeAccounts(battleChainCaip2, accountToRemove);

        // Fast forward past commitment window
        vm.warp(block.timestamp + 31 days);

        // Now it should succeed
        vm.prank(owner);
        agreement.removeAccounts(battleChainCaip2, accountToRemove);

        // Verify account was removed
        assertEq(agreement.getBattleChainScopeCount(), 1);
    }

    function testAddOrSetChainsBlockedWhenReplacingDuringCommitmentWindow() public {
        // Set commitment window to 30 days from now
        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 30 days);

        // Try to replace an existing chain - should fail
        BCAccount[] memory updatedAccounts = new BCAccount[](1);
        updatedAccounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000099", childContractScope: ChildContractScope.All
        });

        BCChain[] memory updateChains = new BCChain[](1);
        updateChains[0] =
            BCChain({ assetRecoveryAddress: "0x88", accounts: updatedAccounts, caip2ChainId: battleChainCaip2 });

        vm.prank(owner);
        vm.expectRevert(Agreement.Agreement__CannotReduceScopeDuringCommitment.selector);
        agreement.addOrSetChains(updateChains);

        // Fast forward past commitment window
        vm.warp(block.timestamp + 31 days);

        // Now it should succeed
        vm.prank(owner);
        agreement.addOrSetChains(updateChains);

        // Verify chain was updated
        assertTrue(agreement.isContractInScope(address(0x99)));
        assertFalse(agreement.isContractInScope(address(0x01))); // Original should be replaced
    }

    function testAddOrSetChainsAllowedForNewChainDuringCommitmentWindow() public {
        // Set commitment window to 30 days from now
        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 30 days);

        // Adding a NEW chain should still work (favorable to whitehats)
        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000DEF", childContractScope: ChildContractScope.None
        });

        BCChain[] memory newChains = new BCChain[](1);
        newChains[0] = BCChain({ assetRecoveryAddress: "0x05", accounts: accounts, caip2ChainId: "eip155:627" });

        vm.prank(owner);
        agreement.addOrSetChains(newChains);

        // Verify chain was added
        string[] memory chainIds = agreement.getChainIds();
        assertEq(chainIds.length, 2);
    }

    function testAddAccountsAllowedDuringCommitmentWindow() public {
        // Set commitment window to 30 days from now
        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 30 days);

        // Adding accounts should still work (favorable to whitehats)
        BCAccount[] memory newAccounts = new BCAccount[](1);
        newAccounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000ABC", childContractScope: ChildContractScope.None
        });

        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, newAccounts);

        // Verify account was added
        assertEq(agreement.getBattleChainScopeCount(), 2);
        assertTrue(agreement.isContractInScope(address(0xABC)));
    }

    function testScopeChangesAllowedWithNoCommitmentWindow() public {
        // With no commitment window set (default 0), all operations should work
        assertEq(agreement.getCantChangeUntil(), 0);

        // Remove the original chain - should work
        string[] memory chainToRemove = new string[](1);
        chainToRemove[0] = battleChainCaip2;

        vm.prank(owner);
        agreement.removeChains(chainToRemove);

        // Verify chain was removed
        string[] memory chainIds = agreement.getChainIds();
        assertEq(chainIds.length, 0);
    }

    function testCommitmentWindowProtectsMultipleScopeOperations() public {
        // Set up: Add additional chain and accounts
        BCAccount[] memory accounts = new BCAccount[](1);
        accounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000002", childContractScope: ChildContractScope.None
        });

        BCChain[] memory newChains = new BCChain[](1);
        newChains[0] = BCChain({ assetRecoveryAddress: "0x05", accounts: accounts, caip2ChainId: "eip155:627" });

        vm.prank(owner);
        agreement.addOrSetChains(newChains);

        BCAccount[] memory moreAccounts = new BCAccount[](1);
        moreAccounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000ABC", childContractScope: ChildContractScope.None
        });

        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, moreAccounts);

        // Set commitment window
        vm.prank(owner);
        agreement.extendCommitmentWindow(block.timestamp + 30 days);

        // All unfavorable operations should be blocked
        string[] memory chainToRemove = new string[](1);
        chainToRemove[0] = "eip155:627";

        vm.prank(owner);
        vm.expectRevert(Agreement.Agreement__CannotReduceScopeDuringCommitment.selector);
        agreement.removeChains(chainToRemove);

        string[] memory accountToRemove = new string[](1);
        accountToRemove[0] = "0x0000000000000000000000000000000000000ABC";

        vm.prank(owner);
        vm.expectRevert(Agreement.Agreement__CannotReduceScopeDuringCommitment.selector);
        agreement.removeAccounts(battleChainCaip2, accountToRemove);

        BCChain[] memory replaceChains = new BCChain[](1);
        replaceChains[0] = BCChain({ assetRecoveryAddress: "0x99", accounts: accounts, caip2ChainId: battleChainCaip2 });

        vm.prank(owner);
        vm.expectRevert(Agreement.Agreement__CannotReduceScopeDuringCommitment.selector);
        agreement.addOrSetChains(replaceChains);

        // But favorable operations should still work
        BCAccount[] memory additionalAccounts = new BCAccount[](1);
        additionalAccounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000DEF", childContractScope: ChildContractScope.None
        });

        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, additionalAccounts);

        // Verify favorable change was applied
        assertTrue(agreement.isContractInScope(address(0xDEF)));
    }

    /*//////////////////////////////////////////////////////////////
                        CHAIN GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetChainAccounts() public view {
        // Get accounts for the initial chain
        BCAccount[] memory accounts = agreement.getChainAccounts(battleChainCaip2);

        assertEq(accounts.length, 1);
        assertEq(accounts[0].accountAddress, "0x0000000000000000000000000000000000000001");
    }

    function testGetChainAccountsMultipleAccounts() public {
        // Add more accounts
        BCAccount[] memory newAccounts = new BCAccount[](2);
        newAccounts[0] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000002", childContractScope: ChildContractScope.None
        });
        newAccounts[1] = BCAccount({
            accountAddress: "0x0000000000000000000000000000000000000003", childContractScope: ChildContractScope.All
        });

        vm.prank(owner);
        agreement.addAccounts(battleChainCaip2, newAccounts);

        // Get all accounts
        BCAccount[] memory accounts = agreement.getChainAccounts(battleChainCaip2);

        assertEq(accounts.length, 3);
        assertEq(accounts[0].accountAddress, "0x0000000000000000000000000000000000000001");
        assertEq(accounts[1].accountAddress, "0x0000000000000000000000000000000000000002");
        assertEq(accounts[2].accountAddress, "0x0000000000000000000000000000000000000003");
    }

    function testGetChainAccountsNonExistentChain() public view {
        // Should return empty array for non-existent chain
        BCAccount[] memory accounts = agreement.getChainAccounts("eip155:999");
        assertEq(accounts.length, 0);
    }

    function testGetAssetRecoveryAddress() public view {
        string memory recoveryAddr = agreement.getAssetRecoveryAddress(battleChainCaip2);
        assertEq(recoveryAddr, "0x0000000000000000000000000000000000000022");
    }

    function testGetAssetRecoveryAddressNonExistentChain() public view {
        string memory recoveryAddr = agreement.getAssetRecoveryAddress("eip155:999");
        assertEq(bytes(recoveryAddr).length, 0);
    }
}
