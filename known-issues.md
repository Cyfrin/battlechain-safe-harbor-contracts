# Known Issues

## DAO loses control over agreements after 14-day PROMOTION_WINDOW deadline

**Affected:** `AttackRegistry::_getAgreementState`, `AttackRegistry::rejectAttackRequest`

**Description:** When an agreement is registered via `requestUnderAttack` or `requestUnderAttackForUnverifiedContracts`, a 14-day deadline is set. If the DAO does not call `approveAttack` or `rejectAttackRequest` within this window, `_getAgreementState` returns PRODUCTION (computed, not stored). All DAO functions (`rejectAttackRequest`, `instantPromote`, `instantCorrupt`) require non-PRODUCTION states and will revert. The bond becomes claimable via lazy marking in `claimBond`.

**Why this is intentional:** The 14-day auto-promotion is the anti-censorship guarantee. Protocols that register in good faith should not be held hostage by DAO inaction. The deadline forces the DAO to review within a reasonable timeframe — if they don't act, the protocol earned production status. This mirrors the 3-day promotion delay philosophy: if no one objects within the window, the transition completes.

**DAO operational requirements:** The DAO must monitor `AgreementStateChanged` events for new `ATTACK_REQUESTED` agreements and review them within 14 days. Failure to do so is an operational failure, not a protocol bug.

## Contract-to-agreement mapping can be overwritten for PRODUCTION agreements

**Affected:** `AttackRegistry::_revertIfLinkedToActiveAgreement`

**Description:** Once an agreement reaches PRODUCTION (either via normal promotion or auto-promotion after the 14-day deadline), its contracts can be re-linked to a different agreement. This means `getAgreementForContract` may return a newer agreement rather than the original one that went through battle-testing.

**Why this is acceptable:**

1. PRODUCTION contracts are inert in the AttackRegistry — `isTopLevelContractUnderAttack` returns false, and no state-changing operations target them. Re-linking only affects the `getAgreementForContract` lookup.

2. Blocking PRODUCTION re-linking would break the DAO's griefing mitigation. When an attacker grief-registers someone else's contracts via the unverified path, the DAO calls `instantPromote` to move the griefing agreement to PRODUCTION, freeing the contracts for the legitimate owner. If PRODUCTION blocked re-linking, griefed contracts would be permanently locked.

3. The unverified path requires the DAO to call `approveAttack` before contracts enter UNDER_ATTACK. The DAO is expected to reject griefing attempts during this window.

**Mitigation for off-chain consumers:** Off-chain systems that rely on `getAgreementForContract` should track `AgreementStateChanged` and `ContractRegistered` events to maintain a full history rather than relying solely on the current mapping.

## Post-registration scope expansion for unverified contracts

**Affected:** `AttackRegistry::registerContractForExistingAgreement`, `Agreement::addAccounts`

**Description:** After an agreement is registered and approved, the agreement owner can add new unverified contracts to scope via `Agreement.addAccounts`. Auto-sync links these contracts in AttackRegistry without DAO re-approval. This means `isTopLevelContractUnderAttack` returns true for the newly added contracts, and they are blocked from being registered under other agreements.

**Mitigation:**
- Every unverified contract synced post-registration emits `UnverifiedContractSynced(contractAddress, agreementAddress)`. The DAO should monitor this event.
- The DAO can call `instantPromote(agreementAddress)` to end the attack phase, which causes `isTopLevelContractUnderAttack` to return false and frees griefed contracts for re-linking.
- The bond system creates a crypto-economic disincentive — `instantPromote` slashes the bond.

## Fee-on-transfer and rebasing tokens not supported as bond token

**Affected:** `BondManager::_collectFeeAndBond`

**Description:** The bond accounting records the intended `bondAmount` in `s_reservedByToken`, not the actual amount received. Fee-on-transfer tokens would cause `s_reservedByToken` to exceed the actual balance, breaking `_withdrawFunds` and `claimBond`.

**Why this is acceptable:** The bond token is set by the contract owner (DAO multisig). The DAO is expected to use a standard ERC20. This is documented in the BondManager contract NatSpec.

## instantPromote always slashes the bond

**Affected:** `AttackRegistry::instantPromote`

**Description:** When the DAO calls `instantPromote`, the bond is always slashed regardless of which state the agreement is promoted from. This means a cooperative protocol owner who registered in good faith loses their bond if the DAO decides to skip the attack phase.

**Why this is intentional:** `instantPromote` bypasses battle-testing — the bond slash is the cost of the DAO short-circuiting the process. Without the slash, protocols could collude with the DAO to skip battle-testing and keep their bond. If the DAO wants to be lenient, they should use `approveAttack` followed by the normal `promote` path, which returns the bond.

## No timeout on UNDER_ATTACK state

**Affected:** `AttackRegistry::_getAgreementState`

**Description:** Once the DAO calls `approveAttack`, an agreement remains in UNDER_ATTACK indefinitely until the attack moderator calls `promote` or `markCorrupted`, or the DAO calls `instantPromote`/`instantCorrupt`. There is no automatic expiration.

**Why this is intentional:** BattleChain is designed for stress testing. Some protocols may want permanent or long-running attack phases. An arbitrary timeout would force protocols to re-register.

**Griefing mitigation:** If an agreement owner keeps contracts in UNDER_ATTACK to block other protocols, the DAO can call `instantPromote` to end the attack phase.

## Terminal states are final

**Affected:** `AttackRegistry::_getAgreementState`

**Description:** Once an agreement reaches PRODUCTION or CORRUPTED, it cannot be changed — even by the DAO. `instantCorrupt` does not allow marking a PRODUCTION agreement as corrupted.

**Why this is intentional:** If an attack is discovered during the 3-day promotion delay, the attack moderator can call `markCorrupted` directly from `PROMOTION_REQUESTED`, or `cancelPromotion` first to return to `UNDER_ATTACK`. Both sequences land at `CORRUPTED` and zero `promotionRequestedTimestamp`. The promotion delay exists specifically to give time to act.

**Note on `promotionRequestedTimestamp` semantics:** the field is cleared on every explicit terminal transition (`cancelPromotion`, `markCorrupted`, `instantCorrupt`, `instantPromote`, `finalizeState`). A non-zero value does not strictly mean "promotion still pending" — it can also persist between when `PROMOTION_DELAY` elapses (`_getAgreementState` computes `PRODUCTION`) and when `finalizeState` materializes that transition in storage. It only means "`promote()` was called and no explicit terminal transition has cleared it yet". Off-chain consumers reading the raw struct must combine this field with the `promoted`/`corrupted` flags and `_getAgreementState` to determine the agreement's actual condition.

## _authorizeUpgrade performs no implementation validation

**Affected:** `BattleChainSafeHarborRegistry`, `AttackRegistry`, `AgreementFactory`

**Description:** All three UUPS contracts have empty `_authorizeUpgrade` bodies with only `onlyOwner`. OZ's UUPS infrastructure calls `proxiableUUID()` on the new implementation (preventing upgrades to non-UUPS contracts), but there is no timelock, version check, or additional governance gate.

**Accepted risk:** The owner is a trusted multisig. A timelock or governance delay for upgrades is a future improvement.

## Gas DoS with large BattleChain scope arrays

**Affected:** `Agreement._clearBattleChainScope`, `AttackRegistry.rejectAttackRequest`

**Description:** Both functions iterate all scope addresses with external calls. Could exceed block gas limits with very large scope arrays.

**Practical limit:** Agreements should keep BattleChain scope to a reasonable size (hundreds, not thousands). `instantPromote` and `instantCorrupt` are gas-safe alternatives — neither iterates contracts.

## Case-sensitive and prefix-sensitive account storage

**Affected:** `Agreement` account management (`_findAccountIndex`, `_parseAddress`)

**Description:** `_parseAddress` accepts addresses with or without the `0x` prefix and is case-insensitive — both `"0xAbCd..."` and `"abcd..."` parse to the same native address. However, `s_accounts` stores the original string as-is, and `_findAccountIndex` uses case-sensitive string hash comparison. This means:

- An account added as `"0xabcd..."` cannot be found/removed with `"abcd..."` (different string hashes)
- An account added as `"0xABCD..."` cannot be found/removed with `"0xabcd..."` (different casing)
- The BattleChain scope cache (`s_battleChainScopeExists`) deduplicates by native address correctly, but `s_accounts` may have inconsistent entries

**Mitigation:** Agreement owners must use the exact same string format (prefix and casing) for adding and removing accounts. Lowercase with `0x` prefix is recommended for EVM addresses. This is a self-inflicted issue.

## `AgreementStateChanged(PRODUCTION)` may be emitted after `ContractRegistered` for re-link

**Affected:** `AttackRegistry._revertIfLinkedToActiveAgreement`, `AttackRegistry.finalizeState`, `_getAgreementState`

**Description:** `_getAgreementState` computes `PRODUCTION` for two time-based transitions without writing to storage:
- 14-day deadline auto-promote (no DAO action on `ATTACK_REQUESTED`)
- 3-day promotion-delay completion (after `promote()` is called)

`_revertIfLinkedToActiveAgreement` consults the computed state, so a contract linked to such an agreement can be re-linked to a new one *before* `finalizeState` writes `info.promoted = true` and emits `AgreementStateChanged(agreement, PRODUCTION)`. If `finalizeState` is called later, the events appear out of order:

```
ContractRegistered(X, agreementB)
... (later) ...
AgreementStateChanged(agreementA, PRODUCTION)
```

An off-chain indexer reconstructing "which agreement governed contract X at production time" purely from the event stream may incorrectly conclude that X was re-linked while agreementA was still active.

**Why this is acceptable:** The on-chain logic is correct — `_getAgreementState` reads the time-based transition, so all state-changing paths see the right value. The bug is purely event-ordering hygiene for off-chain consumers, and a code fix (materializing the state in `_revertIfLinkedToActiveAgreement`) would require changing the function's `view` qualifier and cascading through `_validateAndPrepareAgreement`. The current size budget for `AgreementFactory` (which embeds `Agreement`'s creation bytecode) doesn't have headroom for the change.

**Operational guidance:**
- **Off-chain indexers**: reconcile "which agreement governs contract X" via direct state reads (`getAgreementForContract`, `getAgreementInfo`, `getAgreementState`) rather than pure event-stream reconstruction. Treat the computed-PRODUCTION transitions (deadline auto-promote, promotion-delay completion) as occurring at the time the deadline elapses, not at the time `finalizeState` is called.
- **Operators**: if clean event ordering is required (e.g., for compliance archives), call `finalizeState` for an agreement immediately after its terminal state is reachable, and before allowing any re-link of its contracts.

## `setAgreementFactory` orphans legacy agreements

**Affected:** `AttackRegistry.setAgreementFactory`, `registerContractForExistingAgreement`, `unregisterContractForExistingAgreement`, `syncNewContracts`

**Description:** The factory check in the AttackRegistry's sync functions consults `s_agreementFactory.isAgreementContract(...)`. If the owner replaces the factory pointer with a brand-new factory contract via `setAgreementFactory`, agreements created by the previous factory are not present in the new factory's `s_isAgreement` mapping. As a result, their scope-sync calls (`addAccounts`, `removeAccounts`, `addOrSetChains`, `removeChains`, and direct calls to `syncNewContracts`) revert with `AttackRegistry__InvalidAgreement`. Legacy agreements become read-only with respect to BattleChain scope sync.

**Why this is acceptable:** `AgreementFactory` is UUPS-upgradeable. The standard path for evolving the factory is upgrading the proxy implementation, which preserves `s_isAgreement` (and therefore the recognition of all previously-deployed agreements). `setAgreementFactory` exists only for the rare case where a brand-new factory address is required (e.g., the prior factory's proxy is unrecoverable). Operators should treat that path as destructive.

**Operational guidance:**
- Prefer upgrading the existing factory via UUPS rather than swapping to a new instance.
- If a swap is unavoidable, communicate the migration window to protocols holding legacy agreements; they will need to redeploy via the new factory and re-register.
- Front-ends and indexers should treat `AgreementFactoryChanged` as a significant event and surface affected legacy agreements.

## Re-registering an agreement forfeits prior unclaimed bonds

**Affected:** `BondManager._collectFeeAndBond`

**Description:** If the DAO soft-rejects an agreement (`rejectAttackRequest(..., slashBond=false)`), the bond is marked claimable. If the agreement owner re-registers via `requestUnderAttack` or `requestUnderAttackForUnverifiedContracts` before claiming, the prior bond is forfeited — `s_reservedByToken` is decremented and `BondForfeited` is emitted, but no token transfer back to the prior depositor happens. The forfeited tokens stay in the contract and are sweepable by the owner via `withdrawFunds`.

**Why this is intentional:** `s_agreementBond` is keyed by agreement, not by depositor. Supporting a pending-claim queue per agreement would require a second mapping and additional bytecode, which the current size budget cannot accommodate. The on-chain `BondForfeited` event makes the loss observable to monitoring systems.

**Operational guidance:** Agreement owners must call `claimBond` after a soft reject and before any re-registration. The `BondClaimable` event signals when a bond becomes claimable. Front-ends adopting this contract should warn the owner about pending claimable bonds before initiating a re-registration transaction.

## Duplicate BattleChain account additions cause `s_accounts` ↔ scope-cache drift

**Affected:** `Agreement.addAccounts`, `Agreement.removeAccounts`

**Description:** `addAccounts` does not check for duplicates on the BattleChain side (documented as a gas optimization). The BattleChain scope cache (`s_battleChainScopeExists`, `s_battleChainScopeAddresses`) dedupes by parsed native address, but `s_accounts` does not. If an owner adds the same address twice:
- `s_accounts[chain]` accumulates two entries.
- `s_battleChainScopeExists[addr]` is set once; the second add is silently a no-op for the cache.

A subsequent single `removeAccounts` call swap-and-pops one entry from `s_accounts` and clears the cache (no reference counting). The result:
- `getChainAccounts` and `getDetails` still return the address (the surviving duplicate).
- `getBattleChainScopeAddresses` and `isContractInScope` return `false` for it.

Off-chain consumers that derive scope from `getDetails` will incorrectly show the contract in scope; on-chain `isContractInScope` (and the AttackRegistry sync derived from it) correctly reports out-of-scope.

**Why this is acceptable:** Adding the same address twice is an operator error and not exercised by the canonical adoption flow. A constructor-time and `addAccounts`-time dedup check would close the gap, but `AgreementFactory`'s creation bytecode is at the EIP-170 size limit (24,574 / 24,576) and cannot accommodate the additional check. The legal text and whitehat verification flow already route through the AttackRegistry binding and `isContractInScope`, both of which reflect the cache, not `s_accounts`.

**Operational guidance:**
- Agreement owners must ensure each address appears at most once per chain in `Account[]` arrays passed to the constructor, `addOrSetChains`, or `addAccounts`.
- Off-chain consumers should treat `isContractInScope` (or `getBattleChainScopeAddresses`) as the source of truth for BattleChain scope membership, not `getChainAccounts`/`getDetails`.

## ChildContractScope is immutable once an account is added

**Affected:** `Agreement.addAccounts`, `Agreement.removeAccounts`

**Description:** There is no in-place setter for `Account.childContractScope`. Once an account is added, its scope is fixed for the lifetime of that account entry. The only path to change it is `removeAccounts` followed by re-adding with the new scope — but `removeAccounts` is blocked during the commitment window as a scope-reducing operation. As a result, even strictly favorable scope expansions (e.g., `None -> All`) cannot be performed mid-window.

**Why this is acceptable:** A dedicated `setChildContractScope` function with favorability checks would push `Agreement` (and therefore `AgreementFactory`'s creation bytecode) past the EIP-170 24,576-byte contract-size limit. The trade-off is documented and bounded — protocols wanting to upgrade scope must wait for the commitment window to expire, then call `removeAccounts` + `addAccounts`.

**Operational guidance:** Agreement owners should choose `childContractScope` carefully at agreement creation or `addAccounts` time. If unsure, prefer the most permissive scope (`All`) for whitehat-favorable defaults — it can always be tightened after the commitment window expires, and tightening outside the window is allowed.

## BattleChainSafeHarborRegistry and AttackRegistry can hold different agreements for the same protocol

**Affected:** `BattleChainSafeHarborRegistry::adoptSafeHarbor`, `AttackRegistry::getAgreementForContract`

**Description:** A protocol can deploy multiple factory-validated agreements and register different ones with each registry. `adoptSafeHarbor` accepts any address without cross-checking the AttackRegistry, and `isAgreementValid` only verifies factory provenance. A protocol could register Agreement A (generous terms) via `adoptSafeHarbor` while registering Agreement B (different terms) via `requestUnderAttack` for the same contracts. The Agreement constructor's `_syncRegisterContract` no-op (`address(this).code.length == 0`) lets both agreements include the same contract in their scope without conflict, since neither syncs with AttackRegistry until `requestUnderAttack` is called.

The same divergence can arise unintentionally: a protocol updates AttackRegistry but not `BattleChainSafeHarborRegistry`, or vice versa.

**Why this is acceptable:** The two registries serve different purposes. `BattleChainSafeHarborRegistry` is authoritative for Eligible Funds Rescue (Urgent Blackhat Exploit) coverage — the original SEAL use case. `AttackRegistry` is authoritative for Eligible Stress Test Exploit coverage on BattleChain. The legal agreement (`documents/seal-agreement-modified.md`, Section 2.3(b)(6) "Binding Agreement") makes the AttackRegistry-resolved agreement dispositive for Stress Test purposes regardless of what `BattleChainSafeHarborRegistry.getAgreement` returns.

**Mitigation:**
- Whitehats must resolve the Binding Agreement via the BattleChain block explorer API (`/battlechain/agreement/by-contract/{addr}`) or the `BCQuery` Foundry helper (`isAttackable`) — *not* via `BattleChainSafeHarborRegistry.getAgreement`. The legal text and README make this the canonical verification flow.
- An off-chain indexer can flag protocols where `BattleChainSafeHarborRegistry.getAgreement(adopter)` differs from the AttackRegistry binding for any of their scope contracts, so UIs can warn users about the divergence.
