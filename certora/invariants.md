# Protocol Invariants

## AttackRegistry — State Machine

1. CORRUPTED is a terminal state: once `corrupted` is true, no function can set it back to false
2. PRODUCTION is a terminal state: once `promoted` is true, no function can set it back to false
3. An agreement in CORRUPTED state cannot also be in PRODUCTION state (`promoted` and `corrupted` cannot both be true simultaneously)
4. CORRUPTED takes precedence over PRODUCTION: if both flags were hypothetically set, `_getAgreementState` returns CORRUPTED
5. Valid state transitions from ATTACK_REQUESTED are only: UNDER_ATTACK (via `approveAttack`), NOT_DEPLOYED (via `rejectAttackRequest`), PRODUCTION (via `instantPromote` or 14-day deadline auto-promotion)
6. Valid state transitions from UNDER_ATTACK are only: PROMOTION_REQUESTED (via `promote`), CORRUPTED (via `markCorrupted` or `instantCorrupt`), PRODUCTION (via `instantPromote`)
7. Valid state transitions from PROMOTION_REQUESTED are only: UNDER_ATTACK (via `cancelPromotion`), PRODUCTION (via 3-day delay auto-promotion or `instantPromote`), CORRUPTED (via `markCorrupted` or `instantCorrupt`)
8. `promote` can only be called when agreement is in UNDER_ATTACK state
9. `cancelPromotion` can only be called when agreement is in PROMOTION_REQUESTED state
10. `markCorrupted` can only be called when agreement is in UNDER_ATTACK or PROMOTION_REQUESTED state
11. `approveAttack` can only be called when agreement is in ATTACK_REQUESTED state

## AttackRegistry — Monotonicity & Immutability

12. The `isRegistered` flag, once set to true, is never set back to false (except via `rejectAttackRequest` which deletes the entire struct)
13. The `attackRequested` flag, once set to true, never reverts to false for a registered agreement (struct deletion is the only exception)
14. The `deadlineTimestamp` is immutable after initial registration — no function modifies it

## AttackRegistry — Access Control

15. Only the `registryModerator` can call `approveAttack`, `rejectAttackRequest`, `instantPromote`, and `instantCorrupt`
16. Only the `attackModerator` for a specific agreement can call `promote`, `cancelPromotion`, `markCorrupted`, and `transferAttackModerator` for that agreement
17. Only the contract owner can call `changeRegistryModerator`, `setSafeHarborRegistry`, `setAgreementFactory`, `setBattleChainDeployer`, and bond configuration setters
18. Only the `battleChainDeployer` can call `registerDeployment`
19. `s_registryModerator` is never zero after initialization (all setters reject zero address)
20. `s_battleChainDeployer` is never zero after initialization (all setters reject zero address)

## AttackRegistry — Contract-Agreement Linking

21. A contract linked to an agreement in an active state (ATTACK_REQUESTED, UNDER_ATTACK, PROMOTION_REQUESTED) cannot be re-linked to a different agreement
22. `s_contractToAgreement[addr]` is only modified by `requestUnderAttack`, `requestUnderAttackForUnverifiedContracts`, `requestUnderAttackByNonAuthorized`, `goToProduction`, `rejectAttackRequest`, `registerContractForExistingAgreement`, `unregisterContractForExistingAgreement`, or `syncNewContracts`
23. `registerDeployment` sets `s_contractDeployer[addr]` exactly once — a contract already registered via BattleChainDeployer cannot be re-registered

## AttackRegistry — State Variable Authorization

24. `s_agreementInfo[addr].attackModerator` can only change via `transferAttackModerator` or initial registration
25. `s_agreementInfo[addr].promotionRequestedTimestamp` can only change via `promote` (set) or `cancelPromotion` (cleared to 0)

## BondManager — Bond Accounting

26. `s_reservedByToken[token]` equals the sum of `bondAmount` across all agreements whose bond uses that token and whose bond is neither claimed nor slashed nor forfeited — not formally verified (requires unbounded sum over all agreements)
27. `BondDeposit.claimed` and `BondDeposit.slashed` are mutually exclusive: a bond cannot be both claimed and slashed
28. `claimBond` requires `msg.sender == deposit.depositor` — only the original depositor can claim
29. `_slashBond` is idempotent: calling it twice on the same agreement does not double-decrement `s_reservedByToken`
30. `_markBondClaimable` is idempotent: calling it twice does not corrupt state
31. `_withdrawFunds` can never withdraw more than `balance - s_reservedByToken[token]` for ERC20 tokens
32. After `claimBond` succeeds, `deposit.claimed` is true and subsequent claims revert
33. A bond that has been slashed cannot later be claimed (and vice versa)

## Agreement — Commitment Window

34. `s_cantChangeUntil` can only increase, never decrease (monotonic)
35. During commitment window (`block.timestamp < s_cantChangeUntil`): `bountyPercentage` can only increase or stay the same
36. During commitment window: `bountyCapUsd` can only increase or stay the same
37. During commitment window: `aggregateBountyCapUsd` can only increase or stay the same
38. During commitment window: `identity` requirements can only become less strict (lower enum value) or stay the same
39. During commitment window: `retainable` cannot change from true to false
40. During commitment window: chains cannot be removed and existing chains cannot be replaced
41. During commitment window: accounts cannot be removed from any chain
42. During commitment window: agreement URI cannot be changed

## Agreement — Bounty Validation

43. `bountyPercentage` is always <= 100
44. `aggregateBountyCapUsd` and `retainable` cannot both be non-zero/true simultaneously
45. If `aggregateBountyCapUsd > 0`, then `aggregateBountyCapUsd >= bountyCapUsd`

## Agreement — Scope Integrity

46. `s_battleChainScopeAddresses` length never exceeds the BattleChain scope cap (200)
47. Every address in `s_battleChainScopeAddresses` has `s_battleChainScopeExists[addr] == true`

## AgreementFactory — Factory Integrity

48. Once `s_isAgreement[addr]` is set to true, it is never set back to false (monotonic boolean)
49. The factory `create` function always sets `s_isAgreement[addr] = true` for the created address

## BattleChainSafeHarborRegistry — Access Control

50. Only the owner can call `setValidChains`, `setInvalidChains`, `setAgreementFactory`, and `setAttackRegistry`
51. `s_agreementFactory` is never zero after initialization (setter rejects zero address)
52. `s_attackRegistry` is never zero after being set (setter rejects zero address)
