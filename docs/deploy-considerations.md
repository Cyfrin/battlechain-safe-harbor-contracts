# Deployment Considerations

## Target Chain Requirements

BattleChain Safe Harbor contracts are designed for BattleChain, a ZKsync-based L2. The following EVM features are required:

### EIP-1153: Transient Storage (Cancun)

`Agreement._validateChainsAndCheckDuplicates` uses `tstore`/`tload` opcodes for gas-efficient duplicate chain ID detection within a single transaction. Transient storage is cleared at the end of each transaction, making it ideal for temporary validation state.

**BattleChain support:** Confirmed. BattleChain supports EIP-1153 opcodes.

**If deploying to a chain without EIP-1153:** Replace the transient storage approach in `_validateChainsAndCheckDuplicates` with either:
- A regular storage mapping with explicit cleanup (higher gas cost)
- A memory-based approach using a dynamic array with nested loops (O(n^2) but no storage)

### Solidity Version

Contracts use `pragma solidity 0.8.34`. Interfaces use `^0.8.23` or `^0.8.24` (floating) for consumer compatibility.

### Proxy Pattern

Three contracts use UUPS proxies (ERC1967): `BattleChainSafeHarborRegistry`, `AttackRegistry`, `AgreementFactory`. These require:
- ERC1967 proxy support on the target chain
- A CreateX deployment (or equivalent deterministic deployer) for consistent addresses across chains

### Deployment Order

Contracts must be deployed in this order due to initialization dependencies:

1. **BattleChainSafeHarborRegistry** (proxy) — receives the pre-computed AttackRegistry proxy address at initialization (no post-deployment `setAttackRegistry` call)
2. **AgreementFactory** (proxy) — requires SafeHarborRegistry address
3. **AttackRegistry** (proxy) — requires SafeHarborRegistry, AgreementFactory, and BattleChainDeployer addresses
4. **BattleChainDeployer** — requires AttackRegistry proxy address (pre-computed via CREATE3)

Note: BattleChainDeployer and AttackRegistry have a circular dependency. BattleChainDeployer is deployed first with the pre-computed AttackRegistry proxy address, then AttackRegistry is initialized with the BattleChainDeployer address.
