/*
 * Certora Formal Verification — Agreement
 *
 * Verifies commitment window protections, bounty term validation,
 * and scope monotonicity during commitment.
 *
 * Properties map to certora/invariants.md:
 *   Invariants 26-37 (Agreement sections)
 */

using AgreementHarness as _Agr;

methods {
    // --- Agreement public getters (envfree) ---
    function getCantChangeUntil() external returns (uint256) envfree;
    function getBountyPercentage() external returns (uint256) envfree;
    function getBountyCapUsd() external returns (uint256) envfree;
    function getAggregateBountyCapUsd() external returns (uint256) envfree;
    function getRetainable() external returns (bool) envfree;
    function getIdentity() external returns (uint8) envfree;
    function getChainCount() external returns (uint256) envfree;
    function getBattleChainScopeCount() external returns (uint256) envfree;
    function owner() external returns (address) envfree;

    // --- External calls summarized ---
    function _.isChainValid(string) external => ALWAYS(true);
    function _.getAttackRegistry() external => ALWAYS(0);
    function _.registerContractForExistingAgreement(address) external => NONDET;
    function _.unregisterContractForExistingAgreement(address) external => NONDET;
}

/*//////////////////////////////////////////////////////////////
         COMMITMENT WINDOW MONOTONICITY (Invariant 26)
//////////////////////////////////////////////////////////////*/

/// @notice Invariant 26: s_cantChangeUntil can only increase
rule commitmentWindowMonotonic(env e, method f, calldataarg args)
filtered {
    f -> f.contract == currentContract && !f.isView
}
{
    mathint windowBefore = getCantChangeUntil();

    f(e, args);

    mathint windowAfter = getCantChangeUntil();

    assert windowAfter >= windowBefore,
        "Commitment window must only increase, never decrease";
}

/// @notice extendCommitmentWindow correctly rejects shorter windows
rule extendCommitmentWindowRejectsShortening(env e, uint256 newWindow) {
    mathint currentWindow = getCantChangeUntil();

    extendCommitmentWindow@withrevert(e, newWindow);

    assert !lastReverted => to_mathint(newWindow) > currentWindow,
        "extendCommitmentWindow must require strictly greater window";
}

/*//////////////////////////////////////////////////////////////
    COMMITMENT WINDOW BOUNTY PROTECTIONS (Invariants 27-31)
//////////////////////////////////////////////////////////////*/

/// @notice Invariant 27: During commitment, bountyPercentage can only increase
/// @notice Invariant 28: During commitment, bountyCapUsd can only increase
/// @notice Invariant 29: During commitment, aggregateBountyCapUsd can only increase
/// @notice Invariant 30: During commitment, identity can only become less strict
/// @notice Invariant 31: During commitment, retainable cannot change true->false
rule bountyTermsProtectedDuringCommitment(env e, method f, calldataarg args)
filtered {
    f -> f.contract == currentContract && !f.isView
}
{
    mathint windowEnd = getCantChangeUntil();
    // Only check during commitment window
    require to_mathint(e.block.timestamp) < windowEnd, "UNSAFE: within commitment";

    mathint pctBefore = getBountyPercentage();
    mathint capBefore = getBountyCapUsd();
    mathint aggCapBefore = getAggregateBountyCapUsd();
    bool retainableBefore = getRetainable();
    mathint identityBefore = getIdentity();

    f(e, args);

    mathint pctAfter = getBountyPercentage();
    mathint capAfter = getBountyCapUsd();
    mathint aggCapAfter = getAggregateBountyCapUsd();
    bool retainableAfter = getRetainable();
    mathint identityAfter = getIdentity();

    // Inv 27: bountyPercentage can only increase
    assert pctAfter >= pctBefore,
        "bountyPercentage must not decrease during commitment";

    // Inv 28: bountyCapUsd can only increase
    assert capAfter >= capBefore,
        "bountyCapUsd must not decrease during commitment";

    // Inv 29: aggregateBountyCapUsd can only increase
    assert aggCapAfter >= aggCapBefore,
        "aggregateBountyCapUsd must not decrease during commitment";

    // Inv 30: identity requirements can only become less strict (lower value)
    assert identityAfter <= identityBefore,
        "identity requirements must not become stricter during commitment";

    // Inv 31: retainable cannot change from true to false
    assert retainableBefore => retainableAfter,
        "retainable must not change from true to false during commitment";
}

/*//////////////////////////////////////////////////////////////
    COMMITMENT WINDOW SCOPE PROTECTIONS (Invariants 32-34)
//////////////////////////////////////////////////////////////*/

/// @notice Invariant 32: During commitment, chains cannot be removed
rule removeChainsBlockedDuringCommitment(env e, string[] caip2ChainIds) {
    mathint windowEnd = getCantChangeUntil();
    require to_mathint(e.block.timestamp) < windowEnd, "UNSAFE: within commitment";

    removeChains@withrevert(e, caip2ChainIds);

    assert lastReverted,
        "removeChains must revert during commitment window";
}

/// @notice Invariant 33: During commitment, accounts cannot be removed
rule removeAccountsBlockedDuringCommitment(
    env e, string caip2ChainId, string[] accountAddresses
) {
    mathint windowEnd = getCantChangeUntil();
    require to_mathint(e.block.timestamp) < windowEnd, "UNSAFE: within commitment";

    removeAccounts@withrevert(e, caip2ChainId, accountAddresses);

    assert lastReverted,
        "removeAccounts must revert during commitment window";
}

/// @notice Invariant 34: During commitment, agreement URI cannot be changed
rule setAgreementURIBlockedDuringCommitment(env e, string agreementURI) {
    mathint windowEnd = getCantChangeUntil();
    require to_mathint(e.block.timestamp) < windowEnd, "UNSAFE: within commitment";

    setAgreementURI@withrevert(e, agreementURI);

    assert lastReverted,
        "setAgreementURI must revert during commitment window";
}

/*//////////////////////////////////////////////////////////////
          BOUNTY VALIDATION (Invariants 35-37)
//////////////////////////////////////////////////////////////*/

/// @notice Invariant 35: bountyPercentage always <= 100
rule bountyPercentageMax(env e, method f, calldataarg args)
filtered {
    f -> f.contract == currentContract && !f.isView
}
{
    mathint pctBefore = getBountyPercentage();
    require pctBefore <= 100, "SAFE: valid initial state";

    f(e, args);

    mathint pctAfter = getBountyPercentage();
    assert pctAfter <= 100,
        "bountyPercentage must never exceed 100";
}

/// @notice Invariant 36: aggregateBountyCapUsd and retainable cannot both be set
rule aggregateCapAndRetainableMutuallyExclusive(env e, method f, calldataarg args)
filtered {
    f -> f.contract == currentContract && !f.isView
}
{
    mathint aggCapBefore = getAggregateBountyCapUsd();
    bool retBefore = getRetainable();
    require !(aggCapBefore > 0 && retBefore), "SAFE: valid initial state";

    f(e, args);

    mathint aggCapAfter = getAggregateBountyCapUsd();
    bool retAfter = getRetainable();
    assert !(aggCapAfter > 0 && retAfter),
        "aggregateBountyCapUsd > 0 and retainable = true are mutually exclusive";
}

/// @notice Invariant 37: if aggregateBountyCapUsd > 0 then >= bountyCapUsd
rule aggregateCapNotBelowIndividual(env e, method f, calldataarg args)
filtered {
    f -> f.contract == currentContract && !f.isView
}
{
    mathint aggCapBefore = getAggregateBountyCapUsd();
    mathint capBefore = getBountyCapUsd();
    require aggCapBefore == 0 || aggCapBefore >= capBefore, "SAFE: valid initial";

    f(e, args);

    mathint aggCapAfter = getAggregateBountyCapUsd();
    mathint capAfter = getBountyCapUsd();
    assert aggCapAfter == 0 || aggCapAfter >= capAfter,
        "aggregateBountyCapUsd must be >= bountyCapUsd when set";
}

/*//////////////////////////////////////////////////////////////
                ACCESS CONTROL
//////////////////////////////////////////////////////////////*/

/// @notice Only owner can modify agreement state
rule onlyOwnerCanModify(env e, method f, calldataarg args)
filtered {
    f -> f.contract == currentContract
         && !f.isView
         && f.selector != sig:acceptOwnership().selector
         && f.selector != sig:transferOwnership(address).selector
         && f.selector != sig:renounceOwnership().selector
}
{
    address currentOwner = owner();

    f@withrevert(e, args);

    assert !lastReverted => e.msg.sender == currentOwner,
        "Only the agreement owner can call state-changing functions";
}

/*//////////////////////////////////////////////////////////////
                    SANITY / SATISFY RULES
//////////////////////////////////////////////////////////////*/

/// @notice Sanity: setBountyTerms is reachable
rule setBountyTermsSanity(env e) {
    mathint pctBefore = getBountyPercentage();

    // Use calldataarg since BountyTerms is a complex struct
    calldataarg args;
    setBountyTerms(e, args);

    satisfy getBountyPercentage() != pctBefore;
}

/// @notice Sanity: extendCommitmentWindow is reachable
rule extendCommitmentWindowSanity(env e, uint256 newWindow) {
    extendCommitmentWindow(e, newWindow);
    satisfy true;
}
