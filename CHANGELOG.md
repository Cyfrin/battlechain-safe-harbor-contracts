# Changelog

## [5.0.0] - 2026-06-11

### Added

- **Two-step upgrade flow in `Upgrade.s.sol`** — `deployImplementations()` (broadcast as the deployer) deploys version-keyed CREATE3 implementations for Registry, AgreementFactory, and AttackRegistry and logs the per-proxy `upgradeToAndCall` calldata; `upgradeProxies(address,address,address)` (broadcast as the owner) points the proxies at them. Replaces the registry-only `run(address)`.
- **Payment & Bond System (`BondManager`)** — Non-refundable fee + refundable bond collected on `requestUnderAttack` and `requestUnderAttackForUnverifiedContracts`. Fees go directly to treasury. Bonds are held in the registry and tracked per-token via `s_reservedByToken`. Bond outcomes: claimable on soft reject / markCorrupted / promote to PRODUCTION; slashed on hard reject / instantPromote / instantCorrupt. Pull-based claims via `claimBond` with lazy marking for time-based auto-promotions.
- **`BondManager` abstract contract** — All bond/fee logic: `_collectFeeAndBond`, `_markBondClaimable`, `_slashBond`, `claimBond`, `_withdrawFunds`. Inherited by AttackRegistry.
- **`BondDeposit` struct** in `IAttackRegistry` — Per-agreement deposit record with token snapshot, fee/bond amounts, and claimable/claimed/slashed flags.
- **`AttackRegistry.withdrawFunds(token, recipient)`** — Owner-only. Withdraws all non-reserved balance for a token. For bond tokens, only slashed amounts are withdrawable.
- **Bond configuration setters** — `setBondToken`, `setTreasury`, `setFeeAmount`, `setVerifiedBondAmount`, `setUnverifiedBondAmount` (all owner-only).
- **Bond getters** — `getBondToken`, `getTreasury`, `getFeeAmount`, `getVerifiedBondAmount`, `getUnverifiedBondAmount`, `getBondDeposit`, `getReservedByToken`.
- **`BondForfeited` event** — Emitted when a re-registration overwrites an unclaimed bond deposit.
- **`BondManager__BondNotYetClaimable` error** — Distinct from `NoBondDeposit` for better UX.
- **BattleChain scope cap (200)** — Cap on BattleChain scope addresses (enforced as a literal in `Agreement._addToBattleChainScope`) to prevent gas DoS on `rejectAttackRequest` and `_clearBattleChainScope`.
- **`renounceOwnership` disabled** on AttackRegistry, BattleChainSafeHarborRegistry, and AgreementFactory via custom revert errors.
- **`known-issues.md`** — Documents all accepted design decisions and known risks.
- **`.env.example`** — Template for deployment environment variables.
- **Justfile deploy targets** — `deploy-safe-harbor`, `deploy-attack-registry` with BattleChain flags (`--skip-simulation -g 200`), auto-verification, and `--sender` from `.env`. Account and sender are overridable as positional args.
- **Treasury in `AttackRegistry.initialize`** — Treasury address is now a required parameter, set at initialization time rather than via a separate `setTreasury` call.
- **Treasury in `HelperConfig`** — Added `treasury` field to `NetworkConfig` struct.
- **`BattleChainSafeHarborRegistry.initialize` accepts `attackRegistry`** — Pre-computed AttackRegistry proxy address is passed at init, eliminating the post-deployment `setAttackRegistry` call.
- **`Agreement._syncRegisterContract` / `_syncUnregisterContract`** — Now checks `attackRegistryAddr.code.length == 0` instead of `address(0)`, gracefully skipping when the AttackRegistry is pre-computed but not yet deployed.

### Changed

- **`AttackRegistry.rejectAttackRequest(address, bool slashBond)`** — Breaking signature change. Second parameter controls soft reject (bond claimable) vs hard reject (bond slashed).
- **`AttackRegistry.instantPromote`** — Now slashes bond (DAO intervention = bond slashed). Documented as intentional in NatSpec.
- **`AttackRegistry.instantCorrupt`** — Now slashes bond.
- **`AttackRegistry.markCorrupted`** — Now marks bond claimable (normal lifecycle).
- **`AttackRegistry.finalizeState`** — Now marks bond claimable when materializing PRODUCTION.
- **`AttackRegistry.authorizeAgreementOwner`** — Now rejects `address(0)` as `newOwner`.
- **`AttackRegistry.transferAttackModerator`** — Now reverts in terminal states (PRODUCTION, CORRUPTED).
- **`Agreement._isBattleChainId`** — Cached BattleChain CAIP-2 hash as `immutable bytes32` for gas savings.
- **`Agreement._addToBattleChainScope`** — Rejects `address(0)` and enforces the 200-address BattleChain scope cap.
- **Storage gaps** — Increased to `uint256[200]` on AttackRegistry and BondManager for upgrade headroom.
- **Event ordering** — All events now emit before their corresponding storage writes (event-before-storage pattern).
- **CEI compliance** — `_withdrawFunds` uses `SafeTransferLib.safeTransferETH` instead of raw `call()`. All functions follow checks-effects-interactions.

### Fixed

- **Unclaimed bond permanently locked on re-registration (H-01)** — `_collectFeeAndBond` now forfeits any existing unclaimed bond (decrementing `s_reservedByToken`) before overwriting, preventing accounting inflation.
- **CEI violation in `requestUnderAttackForUnverifiedContracts` (M-01)** — Swapped `_collectFeeAndBond` and `_registerAgreement` to follow effects-before-interactions.
- **Double-slash `s_reservedByToken` underflow** — `_slashBond` now guards with `if (deposit.slashed) return` to prevent double-decrement.
- **`authorizeAgreementOwner` allows `address(0)` (L-2)** — Added zero-address check, preventing permanent authorization lockout.
- **`_parseAddress` accepts `address(0)` (I-4)** — `_addToBattleChainScope` now rejects `address(0)`, preventing corruption of `s_contractToAgreement` sentinel value.
- **Test CAIP-2 hardcoding** — All tests now read BattleChain CAIP-2 chain ID from `HelperConfig` instead of hardcoding `"eip155:626"`. Tests pass on both local anvil and fork mode.

## [4.0.7] - 2026-03-24

### Added

- **Auto-sync of Agreement scope changes with AttackRegistry** — When `addAccounts`, `removeAccounts`, `addOrSetChains`, or `removeChains` modify BattleChain scope, the `s_contractToAgreement` reverse index in AttackRegistry is updated in the same transaction. This ensures `isTopLevelContractUnderAttack()` returns correct results for newly added contracts.
- **`AttackRegistry.registerContractForExistingAgreement(address)`** — Called by Agreement contracts when BattleChain scope expands. Validates factory origin, deduplicates, checks BattleChainDeployer authorization. Silently skips for unregistered or terminal (PRODUCTION/CORRUPTED) agreements.
- **`AttackRegistry.unregisterContractForExistingAgreement(address)`** — Called by Agreement contracts when BattleChain scope shrinks. Idempotent — silently skips if contract isn't linked to the calling agreement.
- **`AttackRegistry.syncNewContracts(address)`** — Permissionless manual fallback for pre-existing agreements that were created before auto-sync. Anyone can call; scope is controlled by the agreement owner, and BattleChainDeployer contracts still require authorized owner match.
- **`BattleChainSafeHarborRegistry.setAttackRegistry(address)`** / `getAttackRegistry()` — Owner-only setter and public getter for the AttackRegistry address. Called post-deployment since AttackRegistry depends on SafeHarborRegistry (deployment order constraint).
- **`AttackRegistry__ContractAlreadyLinked(address, address)`** error — Replaces the previous misuse of `AttackRegistry__InvalidState` when a contract is linked to another active agreement. Includes both the contract address and the existing agreement address.
- **`AttackRegistry__AgreementNotRegistered(address)`** error — Used by `syncNewContracts` when the agreement hasn't been registered.
- **`AttackRegistry__NoNewContracts(address)`** error — Used by `syncNewContracts` when all contracts are already synced.
- **`ContractsSynced(address, uint256)`** event — Emitted by `syncNewContracts` with the agreement address and count of newly synced contracts.
- **`ContractUnregistered(address, address)`** event — Emitted when a contract is removed from the reverse index.
- **`AttackRegistrySet(address)`** event on `BattleChainSafeHarborRegistry`.
- **`UnverifiedContractSynced(address, address)`** event — Emitted when an unverified contract (not deployed via BattleChainDeployer) is synced post-registration. Enables DAO monitoring for scope expansion abuse.
- **`AttackRegistry.requestUnderAttackForUnverifiedContracts(address)`** — Renamed from `requestUnderAttackByNonAuthorized` with consistent "unverified" terminology. "Unverified" means the contract's ownership cannot be proven on-chain (no BattleChainDeployer provenance chain).
- **`src/Version.sol`** — Single source of truth for contract version (`BATTLECHAIN_SAFE_HARBOR_VERSION = "4.0.0"`). All contracts and deploy script entropy derive from this file.
- **`AttackRegistry.instantCorrupt(address)`** — DAO-only function to mark an agreement as corrupted when the attack moderator is unresponsive or compromised.
- **`AttackRegistry.finalizeState(address)`** — Permissionless function that persists computed PRODUCTION state to storage. Call before upgrades to ensure time-based state transitions survive changes to `_getAgreementState` logic.
- **`AttackRegistry__ContractAlreadyRegistered(address)`** error — Used by `registerDeployment` to prevent overwriting existing deployer/authorization records.
- **`Agreement__InvalidAddressCharacter()`** error — Distinct error for invalid hex characters in `_parseAddress`, replacing the misleading reuse of `Agreement__InvalidAddressLength`.
- **`docs/deploy-considerations.md`** — Deployment requirements including EIP-1153 support, proxy pattern, and deployment order.
- **Storage gaps** (`uint256[N] __gap`) on all three upgradeable contracts for future upgrade safety.

### Changed

- **`AttackRegistry.requestUnderAttackByNonAuthorized`** — Kept as backwards-compatible alias that delegates to `requestUnderAttackForUnverifiedContracts`.
- **`AttackRegistry.registerDeployment`** — Now reverts if the contract address was already registered, preventing silent overwrite of deployer/authorization records. Emits `AgreementOwnerAuthorized` for the initial deployer authorization.
- **`AttackRegistry._validateAndLinkContract`** — Extracted shared logic for ownership validation, contract linking, and `UnverifiedContractSynced` emission. Used by both `registerContractForExistingAgreement` and `syncNewContracts`.
- **`Agreement`** — Now uses `Ownable2Step` instead of `Ownable` for two-step ownership transfers.
- **`BattleChainSafeHarborRegistry`** — Uses `@openzeppelin/contracts-upgradeable` import for `UUPSUpgradeable` (consistent with other contracts). `initialize` now validates `owner != address(0)`.

- **`AttackRegistry._revertIfLinkedToActiveAgreement(address)`** — New internal helper used by `_validateAndPrepareAgreement`, `registerContractForExistingAgreement`, and `syncNewContracts`. Allows re-linking contracts from terminal agreements (PRODUCTION, CORRUPTED) — previously, a contract linked to any agreement was permanently locked.
- **`Agreement._addToBattleChainScope`** — Now calls `_syncRegisterContract` after adding to cache.
- **`Agreement._removeFromBattleChainScope`** — Now calls `_syncUnregisterContract` after removing from cache.
- **`Agreement._clearBattleChainScope`** — Now calls `_syncUnregisterContract` for each address before clearing.
- **`Agreement._syncRegisterContract` / `_syncUnregisterContract`** — Internal helpers that call AttackRegistry. Skip during constructor (`address(this).code.length == 0`) since the factory hasn't marked the agreement yet. Skip if `getAttackRegistry()` returns `address(0)`.
- **`Agreement._getAttackRegistry`** — Uses try/catch for backward compatibility with SafeHarborRegistry instances that haven't been upgraded.

### Fixed

- **Stale `s_contractToAgreement` after `addAccounts`** — Previously, adding new BattleChain contracts to a registered agreement did not update the AttackRegistry reverse index, causing `isTopLevelContractUnderAttack()` to return false for those contracts.
- **Stale `s_contractToAgreement` after scope removal** — Previously, removing contracts from an agreement's scope left the reverse mapping intact, meaning `isTopLevelContractUnderAttack()` could return true for contracts no longer covered by safe harbor.
- **Permanently locked contracts** — Contracts linked to a terminal agreement (PRODUCTION/CORRUPTED) could never be claimed by a new agreement. Now only contracts linked to active agreements (ATTACK_REQUESTED, UNDER_ATTACK, PROMOTION_REQUESTED) are blocked.
