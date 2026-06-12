// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    AgreementDetails,
    Account,
    ChildContractScope,
    Chain,
    Contact,
    BountyTerms,
    IdentityRequirements
} from "src/types/AgreementTypes.sol";

function getMockAgreementDetails(
    string memory accountAddress,
    string memory battleChainCaip2
)
    pure
    returns (AgreementDetails memory mockDetails)
{
    // If a short address is provided (like "0x01"), pad it to a full 42-char address
    // This is for backward compatibility with existing tests
    string memory fullAccountAddress = accountAddress;
    if (bytes(accountAddress).length < 42) {
        // For simple cases, just use a known full address
        fullAccountAddress = "0x0000000000000000000000000000000000000001";
    }
    Account memory account = Account({ accountAddress: fullAccountAddress, childContractScope: ChildContractScope.All });

    Chain memory chain = Chain({
        accounts: new Account[](1),
        assetRecoveryAddress: "0x0000000000000000000000000000000000000022",
        caip2ChainId: battleChainCaip2
    });
    chain.accounts[0] = account;

    Contact memory contact = Contact({ name: "Test Name", contact: "test@mail.com" });

    BountyTerms memory bountyTerms = BountyTerms({
        bountyPercentage: 10,
        bountyCapUsd: 100,
        retainable: false,
        identity: IdentityRequirements.Anonymous,
        diligenceRequirements: "none",
        aggregateBountyCapUsd: 1000
    });

    mockDetails = AgreementDetails({
        protocolName: "testProtocol",
        chains: new Chain[](1),
        contactDetails: new Contact[](1),
        bountyTerms: bountyTerms,
        agreementURI: "ipfs://testHash"
    });
    mockDetails.chains[0] = chain;
    mockDetails.contactDetails[0] = contact;

    return mockDetails;
}
