/*
 * Certora Formal Verification — AttackRegistry
 *
 * Verifies state machine transitions, terminal state finality,
 * access control, and bond accounting properties.
 *
 * Properties map to certora/invariants.md:
 *   Invariants 1-25 (AttackRegistry sections)
 */

using AttackRegistryHarness as _AR;

methods {
    // --- AttackRegistry public getters (envfree) ---
    function getAgreementState(address) external returns (IAttackRegistry.ContractState) envfree;
    function getAttackModerator(address) external returns (address) envfree;
    function getAgreementForContract(address) external returns (address) envfree;
    function getContractDeployer(address) external returns (address) envfree;
    function getAuthorizedOwner(address) external returns (address) envfree;
    function getRegistryModerator() external returns (address) envfree;
    function getSafeHarborRegistry() external returns (address) envfree;
    function getAgreementFactory() external returns (address) envfree;
    function getBattleChainDeployer() external returns (address) envfree;
    function owner() external returns (address) envfree;

    // --- BondManager public getters (envfree) ---
    function getBondToken() external returns (address) envfree;
    function getTreasury() external returns (address) envfree;
    function getFeeAmount() external returns (uint256) envfree;
    function getVerifiedBondAmount() external returns (uint256) envfree;
    function getUnverifiedBondAmount() external returns (uint256) envfree;
    function getReservedByToken(address) external returns (uint256) envfree;

    // --- External contract summaries ---
    function _.isAgreementContract(address) external => NONDET;
    function _.getBattleChainScopeAddresses() external => NONDET;
    function _.getCantChangeUntil() external => NONDET;
    function _.owner() external => NONDET;
    function _.isChainValid(string) external => NONDET;
    function _.getAttackRegistry() external => NONDET;

    // --- Unresolved external calls ---
    function _.safeTransferFrom(address, address, uint256) external => NONDET;
    function _.safeTransfer(address, uint256) external => NONDET;
    function _.balanceOf(address) external => NONDET;
}

/*//////////////////////////////////////////////////////////////
                    ENUM DEFINITIONS
//////////////////////////////////////////////////////////////*/

definition CVL_NOT_DEPLOYED() returns uint8 =
    assert_uint8(IAttackRegistry.ContractState.NOT_DEPLOYED);

definition CVL_NEW_DEPLOYMENT() returns uint8 =
    assert_uint8(IAttackRegistry.ContractState.NEW_DEPLOYMENT);

definition CVL_ATTACK_REQUESTED() returns uint8 =
    assert_uint8(IAttackRegistry.ContractState.ATTACK_REQUESTED);

definition CVL_UNDER_ATTACK() returns uint8 =
    assert_uint8(IAttackRegistry.ContractState.UNDER_ATTACK);

definition CVL_PROMOTION_REQUESTED() returns uint8 =
    assert_uint8(IAttackRegistry.ContractState.PROMOTION_REQUESTED);

definition CVL_PRODUCTION() returns uint8 =
    assert_uint8(IAttackRegistry.ContractState.PRODUCTION);

definition CVL_CORRUPTED() returns uint8 =
    assert_uint8(IAttackRegistry.ContractState.CORRUPTED);

/*//////////////////////////////////////////////////////////////
                    METHOD FILTERS
//////////////////////////////////////////////////////////////*/

definition openZeppelinsMethods(method f) returns bool =
    f.selector == sig:renounceOwnership().selector
    || f.selector == sig:transferOwnership(address).selector
    || f.selector == sig:acceptOwnership().selector
    || f.selector == sig:upgradeToAndCall(address, bytes).selector;

/*//////////////////////////////////////////////////////////////
                    HELPER FUNCTIONS
//////////////////////////////////////////////////////////////*/

/// @notice Standard env setup for non-payable functions
function setup(env e) {
    require e.msg.value == 0, "SAFE: non-payable functions revert on msg.value > 0";
}

/*//////////////////////////////////////////////////////////////
             TERMINAL STATE RULES (Invariants 1-4)
//////////////////////////////////////////////////////////////*/

/// @notice Invariant 1: CORRUPTED is terminal — once corrupted, state never changes
/// @notice Invariant 2: PRODUCTION is terminal — once promoted, state never changes
rule terminalStatesAreFinal(env e, method f, calldataarg args, address agreement)
filtered {
    f -> f.contract == currentContract
         && !openZeppelinsMethods(f)
         && !f.isView
}
{
    uint8 stateBefore = assert_uint8(getAgreementState(agreement));

    f(e, args);

    uint8 stateAfter = assert_uint8(getAgreementState(agreement));

    // Invariant 1: CORRUPTED is final
    assert stateBefore == CVL_CORRUPTED()
        => stateAfter == CVL_CORRUPTED(),
        "CORRUPTED state must be terminal";

    // Invariant 2: PRODUCTION is final
    assert stateBefore == CVL_PRODUCTION()
        => stateAfter == CVL_PRODUCTION(),
        "PRODUCTION state must be terminal";
}

/// @notice Invariant 3/4: PRODUCTION and CORRUPTED are both reachable states
rule productionIsReachable(address agreement) {
    uint8 state = assert_uint8(getAgreementState(agreement));
    satisfy state == CVL_PRODUCTION();
}

rule corruptedIsReachable(address agreement) {
    uint8 state = assert_uint8(getAgreementState(agreement));
    satisfy state == CVL_CORRUPTED();
}

/*//////////////////////////////////////////////////////////////
         STATE TRANSITION RULES (Invariants 5-11)
//////////////////////////////////////////////////////////////*/

/// @notice Invariants 5-7: Valid state transitions only
rule validStateTransitions(env e, method f, calldataarg args, address agreement)
filtered {
    f -> f.contract == currentContract
         && !openZeppelinsMethods(f)
         && !f.isView
}
{
    uint8 stateBefore = assert_uint8(getAgreementState(agreement));
    f(e, args);
    uint8 stateAfter = assert_uint8(getAgreementState(agreement));

    // If state changed, verify the transition is valid
    assert stateBefore != stateAfter => (
        // NOT_DEPLOYED -> ATTACK_REQUESTED or PRODUCTION
        (stateBefore == CVL_NOT_DEPLOYED() && (
            stateAfter == CVL_ATTACK_REQUESTED()
            || stateAfter == CVL_PRODUCTION()
        ))
        // ATTACK_REQUESTED -> UNDER_ATTACK, NOT_DEPLOYED, PRODUCTION
        || (stateBefore == CVL_ATTACK_REQUESTED() && (
            stateAfter == CVL_UNDER_ATTACK()
            || stateAfter == CVL_NOT_DEPLOYED()
            || stateAfter == CVL_PRODUCTION()
        ))
        // UNDER_ATTACK -> PROMOTION_REQUESTED, CORRUPTED, PRODUCTION
        || (stateBefore == CVL_UNDER_ATTACK() && (
            stateAfter == CVL_PROMOTION_REQUESTED()
            || stateAfter == CVL_CORRUPTED()
            || stateAfter == CVL_PRODUCTION()
        ))
        // PROMOTION_REQUESTED -> UNDER_ATTACK, PRODUCTION, CORRUPTED
        || (stateBefore == CVL_PROMOTION_REQUESTED() && (
            stateAfter == CVL_UNDER_ATTACK()
            || stateAfter == CVL_PRODUCTION()
            || stateAfter == CVL_CORRUPTED()
        ))
    ),
    "Invalid state transition detected";
}

/// @notice Invariant 8: promote reverts if state is not UNDER_ATTACK
rule promoteRevertsOnWrongState(env e, address agreement) {
    setup(e);
    uint8 stateBefore = assert_uint8(getAgreementState(agreement));
    require stateBefore != CVL_UNDER_ATTACK(), "UNSAFE: test wrong-state revert";

    promote@withrevert(e, agreement);

    assert lastReverted,
        "promote must revert when state is not UNDER_ATTACK";
}

/// @notice Invariant 9: cancelPromotion reverts if state is not PROMOTION_REQUESTED
rule cancelPromotionRevertsOnWrongState(env e, address agreement) {
    setup(e);
    uint8 stateBefore = assert_uint8(getAgreementState(agreement));
    require stateBefore != CVL_PROMOTION_REQUESTED(), "UNSAFE: test wrong-state revert";

    cancelPromotion@withrevert(e, agreement);

    assert lastReverted,
        "cancelPromotion must revert when state is not PROMOTION_REQUESTED";
}

/// @notice Invariant 10: markCorrupted reverts if state is not UNDER_ATTACK or PROMOTION_REQUESTED
rule markCorruptedRevertsOnWrongState(env e, address agreement) {
    setup(e);
    uint8 stateBefore = assert_uint8(getAgreementState(agreement));
    require stateBefore != CVL_UNDER_ATTACK()
        && stateBefore != CVL_PROMOTION_REQUESTED(),
        "UNSAFE: test wrong-state revert";

    markCorrupted@withrevert(e, agreement);

    assert lastReverted,
        "markCorrupted must revert when state is not UNDER_ATTACK or PROMOTION_REQUESTED";
}

/// @notice Invariant 11: approveAttack reverts if state is not ATTACK_REQUESTED
rule approveAttackRevertsOnWrongState(env e, address agreement) {
    setup(e);
    uint8 stateBefore = assert_uint8(getAgreementState(agreement));
    require stateBefore != CVL_ATTACK_REQUESTED(), "UNSAFE: test wrong-state revert";

    approveAttack@withrevert(e, agreement);

    assert lastReverted,
        "approveAttack must revert when state is not ATTACK_REQUESTED";
}

/*//////////////////////////////////////////////////////////////
         ACCESS CONTROL RULES (Invariants 15-20)
//////////////////////////////////////////////////////////////*/

/// @notice Invariant 15: Only registryModerator can call DAO functions
rule onlyRegistryModeratorForApproveAttack(env e, address agreement) {
    setup(e);
    address moderator = getRegistryModerator();

    approveAttack@withrevert(e, agreement);

    assert !lastReverted => e.msg.sender == moderator,
        "approveAttack: only registryModerator";
}

rule onlyRegistryModeratorForReject(env e, address agreement, bool slashBond) {
    setup(e);
    address moderator = getRegistryModerator();

    rejectAttackRequest@withrevert(e, agreement, slashBond);

    assert !lastReverted => e.msg.sender == moderator,
        "rejectAttackRequest: only registryModerator";
}

rule onlyRegistryModeratorForInstantPromote(env e, address agreement) {
    setup(e);
    address moderator = getRegistryModerator();

    instantPromote@withrevert(e, agreement);

    assert !lastReverted => e.msg.sender == moderator,
        "instantPromote: only registryModerator";
}

rule onlyRegistryModeratorForInstantCorrupt(env e, address agreement) {
    setup(e);
    address moderator = getRegistryModerator();

    instantCorrupt@withrevert(e, agreement);

    assert !lastReverted => e.msg.sender == moderator,
        "instantCorrupt: only registryModerator";
}

/// @notice Invariant 16: Only attackModerator can call agreement-specific functions
rule onlyAttackModeratorForPromote(env e, address agreement) {
    setup(e);
    address moderator = getAttackModerator(agreement);

    promote@withrevert(e, agreement);

    assert !lastReverted => e.msg.sender == moderator,
        "promote: only attackModerator";
}

rule onlyAttackModeratorForCancelPromotion(env e, address agreement) {
    setup(e);
    address moderator = getAttackModerator(agreement);

    cancelPromotion@withrevert(e, agreement);

    assert !lastReverted => e.msg.sender == moderator,
        "cancelPromotion: only attackModerator";
}

rule onlyAttackModeratorForMarkCorrupted(env e, address agreement) {
    setup(e);
    address moderator = getAttackModerator(agreement);

    markCorrupted@withrevert(e, agreement);

    assert !lastReverted => e.msg.sender == moderator,
        "markCorrupted: only attackModerator";
}

/// @notice Invariant 17: Only owner for admin functions
rule onlyOwnerForChangeRegistryModerator(env e, address newMod) {
    setup(e);
    address currentOwner = owner();

    changeRegistryModerator@withrevert(e, newMod);

    assert !lastReverted => e.msg.sender == currentOwner,
        "changeRegistryModerator: only owner";
}

/// @notice Invariant 18: Only battleChainDeployer for registerDeployment
rule onlyBattleChainDeployerForRegister(env e, address c, address d) {
    setup(e);
    address deployer = getBattleChainDeployer();

    registerDeployment@withrevert(e, c, d);

    assert !lastReverted => e.msg.sender == deployer,
        "registerDeployment: only battleChainDeployer";
}

/// @notice Invariant 19: registryModerator never zero after init
rule registryModeratorNeverZero(env e, method f, calldataarg args)
filtered {
    f -> f.contract == currentContract
         && !openZeppelinsMethods(f)
         && !f.isView
}
{
    address modBefore = getRegistryModerator();
    require modBefore != 0, "SAFE: initialized state";

    f(e, args);

    address modAfter = getRegistryModerator();
    assert modAfter != 0,
        "registryModerator must never become zero";
}

/// @notice Invariant 20: battleChainDeployer never zero after init
rule battleChainDeployerNeverZero(env e, method f, calldataarg args)
filtered {
    f -> f.contract == currentContract
         && !openZeppelinsMethods(f)
         && !f.isView
}
{
    address depBefore = getBattleChainDeployer();
    require depBefore != 0, "SAFE: initialized state";

    f(e, args);

    address depAfter = getBattleChainDeployer();
    assert depAfter != 0,
        "battleChainDeployer must never become zero";
}

/*//////////////////////////////////////////////////////////////
     STATE VARIABLE AUTHORIZATION (Invariants 22-25)
//////////////////////////////////////////////////////////////*/

/// @notice Invariant 23: registerDeployment sets deployer exactly once
rule contractDeployerSetOnce(env e, address c, address d) {
    setup(e);
    address existingDeployer = getContractDeployer(c);

    registerDeployment@withrevert(e, c, d);

    assert existingDeployer != 0 => lastReverted,
        "Cannot re-register a contract already deployed via BattleChainDeployer";
}

/// @notice Invariant 22: s_contractToAgreement only modified by specific functions
rule contractToAgreementOnlyChangesViaExpectedFunctions(
    env e, method f, calldataarg args, address contractAddr
)
filtered {
    f -> f.contract == currentContract
         && !openZeppelinsMethods(f)
         && !f.isView
}
{
    address agreementBefore = getAgreementForContract(contractAddr);

    f(e, args);

    address agreementAfter = getAgreementForContract(contractAddr);

    assert agreementBefore != agreementAfter => (
        f.selector == sig:requestUnderAttack(address).selector
        || f.selector == sig:requestUnderAttackForUnverifiedContracts(address).selector
        || f.selector == sig:requestUnderAttackByNonAuthorized(address).selector
        || f.selector == sig:goToProduction(address).selector
        || f.selector == sig:rejectAttackRequest(address, bool).selector
        || f.selector == sig:registerContractForExistingAgreement(address).selector
        || f.selector == sig:unregisterContractForExistingAgreement(address).selector
        || f.selector == sig:syncNewContracts(address).selector
    ),
    "s_contractToAgreement changed by unexpected function";
}

/*//////////////////////////////////////////////////////////////
                    SANITY / SATISFY RULES
//////////////////////////////////////////////////////////////*/

/// @notice Sanity: promote is reachable
rule promoteSanity(env e, address agreement) {
    promote(e, agreement);
    satisfy true;
}

/// @notice Sanity: approveAttack is reachable
rule approveAttackSanity(env e, address agreement) {
    approveAttack(e, agreement);
    satisfy true;
}

/// @notice Sanity: markCorrupted is reachable
rule markCorruptedSanity(env e, address agreement) {
    markCorrupted(e, agreement);
    satisfy true;
}

/// @notice Sanity: cancelPromotion is reachable
rule cancelPromotionSanity(env e, address agreement) {
    cancelPromotion(e, agreement);
    satisfy true;
}

/// @notice Sanity: finalizeState is reachable
rule finalizeStateSanity(env e, address agreement) {
    finalizeState(e, agreement);
    satisfy true;
}
