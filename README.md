# BattleChain Safe Harbor

This repository contains the Safe Harbor and Attack Registry contracts for BattleChain - a pre-mainnet, post-testnet environment with real funds (incentivized testnet) that encourages ethical hackers, AI bots, and experimental DeFi advocates to stress test protocols before mainnet launch.

This project is inspired by the [SEAL Safe Harbor project](https://github.com/security-alliance/safe-harbor). All contracts and legal documents are brand new and different from the SEAL Safe Harbor project.

# Table of Contents
- [BattleChain Safe Harbor](#battlechain-safe-harbor)
- [Table of Contents](#table-of-contents)
  - [Mechanisms](#mechanisms)
  - [Contract States](#contract-states)
  - [Architecture](#architecture)
    - [Core Contracts](#core-contracts)
      - [1. BattleChainSafeHarborRegistry (`src/BattleChainSafeHarborRegistry.sol`)](#1-battlechainsafeharborregistry-srcbattlechainsafeharborregistrysol)
      - [2. Agreement (`src/Agreement.sol`)](#2-agreement-srcagreementsol)
      - [3. AgreementFactory (`src/AgreementFactory.sol`)](#3-agreementfactory-srcagreementfactorysol)
      - [4. AttackRegistry (`src/AttackRegistry.sol`) + BondManager (`src/BondManager.sol`)](#4-attackregistry-srcattackregistrysol--bondmanager-srcbondmanagersol)
      - [5. BattleChainDeployer (`src/BattleChainDeployer.sol`)](#5-battlechaindeployer-srcbattlechaindeployersol)
    - [Roles](#roles)
  - [Example Flows](#example-flows)
    - [Flow 1: Happy Path - Deploy via BattleChainDeployer → Attack Mode → Production](#flow-1-happy-path---deploy-via-battlechaindeployer--attack-mode--production)
    - [Flow 2: Attack Succeeds - Deploy → Attack Mode → Corrupted](#flow-2-attack-succeeds---deploy--attack-mode--corrupted)
    - [Flow 3: Skip Attack Mode - Deploy → Go Directly to Production](#flow-3-skip-attack-mode---deploy--go-directly-to-production)
    - [Flow 4: External Deployment - Request Rejected](#flow-4-external-deployment---request-rejected)
  - [Key Functions](#key-functions)
    - [For Protocols (Deploying)](#for-protocols-deploying)
    - [For Protocols (Attack Management)](#for-protocols-attack-management)
    - [For DAO/Registry Moderator](#for-daoregistry-moderator)
    - [Bond Management](#bond-management)
    - [DAO Monitoring: Unverified Contract Scope Expansion](#dao-monitoring-unverified-contract-scope-expansion)
    - [For Ethical Hackers](#for-ethical-hackers)
  - [Key Differences from SEAL Safe Harbor](#key-differences-from-seal-safe-harbor)
  - [Known Issues](#known-issues)
  - [Future Work](#future-work)
  - [Development](#development)
    - [Prerequisites](#prerequisites)
    - [Clone the Repository](#clone-the-repository)
    - [Build](#build)
    - [Test](#test)
    - [Formatting \& Linting](#formatting--linting)
    - [Deploy](#deploy)
  - [Acknowledgements](#acknowledgements)
- [Deployments](#deployments)
  - [Mainnet v5.0.0](#mainnet-v500)
  - [Testnet v5.0.0](#testnet-v500)

## Mechanisms

When a protocol launches a contract, it can submit to the L2 DAO to become a "hackable" or "Attackable mode" contract:

- **Attackable mode** = open season for ethical hacking
- **Production mode** = protected, same as mainnet

All contracts with the "Attackable" flag are covered by a [safe harbor agreement](https://frameworks.securityalliance.org/safe-harbor/overview), which gives ethical hackers the confidence to attack them. The entire contract is considered under attack during this stage.

- Ethical hackers send recovered funds to the safe harbor and receive a bounty per the agreement's terms (percentage and USD caps are set per-agreement, not system-wide)
- A project can choose to "promote" a contract from "Attackable" to "Production" by calling the `promote` function on the AttackRegistry contract

## Contract States

Agreements go through the following states (defined in `IAttackRegistry.ContractState`):

```
                                    ┌──────────────┐
                                    │   CORRUPTED  │ (terminal - attack succeeded)
                                    └──────────────┘
                                           ▲
                                           │ markCorrupted()
                                           │
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ NOT_DEPLOYED │───►│   ATTACK     │───►│    UNDER     │───►│  PROMOTION   │───►│  PRODUCTION  │
│              │    │  REQUESTED   │    │    ATTACK    │    │  REQUESTED   │    │  (terminal)  │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
       │                   │                                        │
       │                   │ rejectAttackRequest(,bool)             │ cancelPromotion()
       │                   ▼                                        ▼
       │            ┌──────────────┐                         ┌──────────────┐
       │            │ NOT_DEPLOYED │                         │    UNDER     │
       │            │  (rejected)  │                         │    ATTACK    │
       │            └──────────────┘                         └──────────────┘
       │
       │    (Contracts deployed via BattleChainDeployer)
       ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│    NEW       │───►│   ATTACK     │───►│    UNDER     │───►│  PRODUCTION  │
│  DEPLOYMENT  │    │  REQUESTED   │    │    ATTACK    │    │              │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
       │                   │                   │
       │                   │                   │ instantPromote() (DAO)
       │                   │                   ▼
       │                   │            ┌──────────────┐
       │                   └───────────►│  PRODUCTION  │
       │                                │ (DAO skips)  │
       │                                └──────────────┘
       │                                       ▲
       │         goToProduction()              │
       └───────────────────────────────────────┘
           (protocol skips attack entirely)
```

| State                 | Description                                                                                                                                                | Attackable? |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| `NOT_DEPLOYED`        | Default state for any unregistered agreement (regardless of whether the underlying contracts were deployed via `BattleChainDeployer` or externally)        | No          |
| `NEW_DEPLOYMENT`      | Reserved. Unreachable via public APIs — every registration path sets `attackRequested = true` or `promoted = true`. Kept in the enum to avoid an ABI break | No          |
| `ATTACK_REQUESTED`    | Protocol requested attack mode, awaiting DAO approval                                                                                                      | No          |
| `UNDER_ATTACK`        | DAO approved, open season for ethical hacking                                                                                                              | **Yes**     |
| `PROMOTION_REQUESTED` | Protocol requested promotion, 3-day delay                                                                                                                  | **Yes**     |
| `PRODUCTION`          | Terminal state - protected, same as mainnet                                                                                                                | No          |
| `CORRUPTED`           | Terminal state - attack succeeded, contract compromised                                                                                                    | No          |

**Important constants:**
- `PROMOTION_WINDOW`: 14 days - auto-promotes to PRODUCTION if DAO doesn't act
- `PROMOTION_DELAY`: 3 days - delay between requesting promotion and becoming production
- `MIN_COMMITMENT`: 7 days - minimum commitment window required for safe harbor agreements

**Other limits:**
- An agreement's BattleChain scope is capped at 200 addresses (enforced in `Agreement.sol`; not a named constant)

## Architecture

### Core Contracts

```
┌───────────────────────────────────────────────────────────────────────────────────────────┐
│                              BattleChain Safe Harbor System                               │
├───────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                           │
│  ┌──────────────────────┐      ┌──────────────────────┐      ┌────────────────────────┐  │
│  │  BattleChainSafe     │      │   AgreementFactory   │      │     AttackRegistry     │  │
│  │  HarborRegistry      │◄─────│                      │─────►│                        │  │
│  │                      │      │  Creates Agreement   │      │  Tracks agreement-level│  │
│  │  - Valid chains      │      │  contracts via       │      │  attack states         │  │
│  │  - Protocol lookup   │      │  CREATE2             │      │                        │  │
│  │  - Agreement factory │      │                      │      │                        │  │
│  └──────────────────────┘      └──────────────────────┘      └────────────────────────┘  │
│           ▲                              │                            ▲                  │
│           │                              ▼                            │                  │
│           │                    ┌──────────────────────┐               │                  │
│           │                    │     Agreement        │───────────────┘                  │
│           └────────────────────│                      │                                  │
│                                │  - Bounty terms      │                                  │
│                                │  - Contact details   │      ┌────────────────────────┐  │
│                                │  - Chain scopes      │      │  BattleChainDeployer   │  │
│                                │  - Commitment window │      │                        │  │
│                                └──────────────────────┘      │  Extends CreateX       │  │
│                                                              │  Auto-registers with   │  │
│                                                              │  AttackRegistry        │  │
│                                                              └────────────────────────┘  │
│                                                                                           │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

#### 1. BattleChainSafeHarborRegistry (`src/BattleChainSafeHarborRegistry.sol`)

The central registry that:
- Maps protocol addresses to their Agreement contracts
- Maintains a list of valid CAIP-2 chain IDs
- Allows protocols to adopt safe harbor agreements
- Upgradeable via UUPS proxy pattern

#### 2. Agreement (`src/Agreement.sol`)

Per-protocol contract containing:
- **Protocol name** and contact details
- **Bounty terms**: percentage (0-100), individual USD cap, optional aggregate USD cap, `retainable` flag, identity requirements, and diligence requirements
- **Chain scopes**: CAIP-2 chain IDs with account addresses and asset recovery addresses
- **Commitment window**: Terms cannot be changed unfavorably during this period
- **BattleChain scope cache**: Native addresses for efficient AttackRegistry integration

Key features:
- Owner can modify terms (subject to commitment window restrictions)
- Maintains a cache of BattleChain addresses for O(1) scope lookups
- Supports multiple chains with different recovery addresses

#### 3. AgreementFactory (`src/AgreementFactory.sol`)

Factory for creating Agreement contracts:
- Uses CREATE2 for deterministic addresses (salt includes `msg.sender` and `chainid`)
- Tracks all agreements created for validation by AttackRegistry
- Upgradeable via UUPS proxy pattern

#### 4. AttackRegistry (`src/AttackRegistry.sol`) + BondManager (`src/BondManager.sol`)

Tracks the attack/production status at the **agreement level** (not individual contracts):
- Receives deployment notifications from BattleChainDeployer
- Manages state transitions for entire agreements
- Supports two paths: `requestUnderAttack` (for BattleChainDeployer-deployed contracts) and `requestUnderAttackForUnverifiedContracts` (for unverified contracts without on-chain ownership proof)
- Auto-syncs scope changes from Agreement contracts via `registerContractForExistingAgreement` / `unregisterContractForExistingAgreement`
- DAO (registry moderator) approves attack requests, can reject (soft/hard) them, and instant-promote
- Attack moderator can mark agreements as `CORRUPTED` after successful attacks
- **Bond system** (via `BondManager`): collects a non-refundable fee (sent to treasury) + refundable bond on attack requests. Bond is claimable on normal lifecycle outcomes (promote, markCorrupted, soft reject) and slashed on DAO intervention (instantPromote, instantCorrupt, hard reject). Unverified requests require a larger bond.
- Upgradeable via UUPS proxy pattern

#### 5. BattleChainDeployer (`src/BattleChainDeployer.sol`)

Extends CreateX to auto-register deployments with AttackRegistry:
- Inherits all CreateX deployment functions (CREATE, CREATE2, CREATE3)
- Automatically calls `registerDeployment` on AttackRegistry after each deployment
- Deployer is initially authorized to request attack mode
- Deployer can transfer authority via `authorizeAgreementOwner`

### Roles

| Role                   | Description                           | Permissions                                           |
| ---------------------- | ------------------------------------- | ----------------------------------------------------- |
| **Owner**              | Contract owner (typically a multisig) | Upgrade contracts, change moderator, set valid chains |
| **Registry Moderator** | DAO/governance                        | Approve attacks, instant promote, bulk operations     |
| **Attack Moderator**   | Per-contract deployer                 | Request attack mode, promote, transfer moderation     |
| **Authorized Adopter** | Delegated by Attack Moderator         | Can adopt contracts into an agreement                 |
| **Agreement Owner**    | Owner of an Agreement contract        | Modify agreement terms, extend commitment             |

## Example Flows

### Flow 1: Happy Path - Deploy via BattleChainDeployer → Attack Mode → Production

This is the recommended flow for protocols that want full BattleChain protection:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Deploy via     │────►│ Authorize       │────►│    Create       │────►│    Request      │
│ BattleChain     │     │ Agreement Owner │     │   Agreement     │     │  Under Attack   │
│   Deployer      │     │ (if different)  │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘     └─────────────────┘
        │                                                                        │
        │ registerDeployment()                                                   │
        │ (auto: deployer = authorized)                                          ▼
        ▼                                                               ┌─────────────────┐
┌─────────────────┐                                                     │  ATTACK_        │
│  NOT_DEPLOYED   │                                                     │  REQUESTED      │
│  (no agreement) │                                                     │                 │
└─────────────────┘                                                     └─────────────────┘
                                                                                 │
                                                                                 │ DAO calls approveAttack()
                                                                                 ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   PRODUCTION    │◄────│   3 days pass   │◄────│    promote()    │◄────│  UNDER_ATTACK   │
│   (terminal)    │     │                 │     │                 │     │  (attackable!)  │
└─────────────────┘     └─────────────────┘     └─────────────────┘     └─────────────────┘
```

**Steps:**
1. Protocol deploys contracts via `BattleChainDeployer.deployCreate3()` (or other deploy methods)
2. If deployer != agreement owner, deployer calls `authorizeAgreementOwner(contract, agreementOwner)` for each contract
3. Protocol creates a Safe Harbor Agreement via `AgreementFactory.create()`
4. Agreement owner calls `AttackRegistry.requestUnderAttack(agreementAddress)`
5. DAO reviews and calls `approveAttack(agreementAddress)`
6. Agreement enters **UNDER_ATTACK** mode - open season for ethical hacking!
7. Once satisfied, protocol calls `promote(agreementAddress)` to begin 3-day delay
8. After 3 days, agreement becomes **PRODUCTION** (terminal)

---

### Flow 2: Attack Succeeds - Deploy → Attack Mode → Corrupted

When an ethical hacker successfully exploits a vulnerability:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Deploy via     │────►│    Create       │────►│    Request &    │────►│  UNDER_ATTACK   │
│ BattleChain     │     │   Agreement     │     │    Approve      │     │  (attackable!)  │
│   Deployer      │     │                 │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘     └─────────────────┘
                                                                                 │
                                                                                 │ Ethical hacker
                                                                                 │ exploits vulnerability
                                                                                 ▼
                                                                        ┌─────────────────┐
                                                                        │ Attack Moderator│
                                                                        │ calls           │
                                                                        │ markCorrupted() │
                                                                        └─────────────────┘
                                                                                 │
                                                                                 ▼
                                                                        ┌─────────────────┐
                                                                        │   CORRUPTED     │
                                                                        │   (terminal)    │
                                                                        └─────────────────┘
```

**Steps:**
1-6. Same as Flow 1 through UNDER_ATTACK
7. Ethical hacker finds and exploits a vulnerability
8. Hacker sends recovered funds to safe harbor address (per agreement terms)
9. Attack moderator calls `markCorrupted(agreementAddress)`
10. Agreement enters **CORRUPTED** state (terminal) - protocol should not deploy these contracts elsewhere

---

### Flow 3: Skip Attack Mode - Deploy → Go Directly to Production

For protocols that don't want the attack phase (no DAO approval needed):

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Deploy via     │────►│ Authorize       │────►│    Create       │────►│ goToProduction()│
│ BattleChain     │     │ Agreement Owner │     │   Agreement     │     │                 │
│   Deployer      │     │ (if different)  │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘     └─────────────────┘
                                                                                 │
                                                                                 │ (instant, no delay)
                                                                                 ▼
                                                                        ┌─────────────────┐
                                                                        │   PRODUCTION    │
                                                                        │   (terminal)    │
                                                                        └─────────────────┘
```

**Steps:**
1. Protocol deploys contracts via BattleChainDeployer
2. If deployer != agreement owner, authorize the agreement owner
3. Create a Safe Harbor Agreement
4. Agreement owner calls `goToProduction(agreementAddress)`
5. Agreement immediately enters **PRODUCTION** (terminal) - no attack phase, no DAO approval needed

**Note:** The DAO can also call `instantPromote()` from ATTACK_REQUESTED state to achieve a similar result after a protocol has requested attack mode.

---

### Flow 4: External Deployment - Request Rejected

For contracts NOT deployed via BattleChainDeployer (extra scrutiny required):

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Deploy via     │────►│    Create       │────►│    Request      │────►│  ATTACK_        │
│  external       │     │   Agreement     │     │  Under Attack   │     │  REQUESTED      │
│  deployer       │     │                 │     │  ForUnverified  │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘     └─────────────────┘
        │                                                                        │
        │ (no registration)                                                      │ DAO performs
        │                                                                        │ extra due diligence
        ▼                                                                        ▼
┌─────────────────┐                                                     ┌─────────────────┐
│  NOT_DEPLOYED   │◄────────────────────────────────────────────────────│ DAO calls       │
│                 │                                                     │ rejectAttack()  │
└─────────────────┘                                                     └─────────────────┘
```

**Steps:**
1. Protocol deploys contracts via their own method (not BattleChainDeployer)
2. Protocol creates a Safe Harbor Agreement
3. Agreement owner calls `requestUnderAttackForUnverifiedContracts(agreementAddress)`
4. DAO performs extra due diligence (unverified contracts — no on-chain ownership proof)
5. DAO finds issues and calls `rejectAttackRequest(agreementAddress)`
6. Agreement returns to **NOT_DEPLOYED** state - contracts can be re-added to a new agreement

**Note:** If the DAO approves instead, the flow continues like Flow 1 from UNDER_ATTACK onwards.

## Key Functions

### For Protocols (Deploying)

```solidity
// Deploy contracts via BattleChainDeployer (recommended)
BattleChainDeployer.deployCreate3(bytes32 salt, bytes memory initCode) returns (address)
BattleChainDeployer.deployCreate2(bytes32 salt, bytes memory initCode) returns (address)
BattleChainDeployer.deployCreate(bytes memory initCode) returns (address)
// ... and all other CreateX methods

// Authorize agreement owner for a contract (if deployer != agreement owner)
AttackRegistry.authorizeAgreementOwner(address contractAddress, address newOwner)

// Create a safe harbor agreement
AgreementFactory.create(AgreementDetails details, address owner, bytes32 salt) returns (address)
```

### For Protocols (Attack Management)

```solidity
// Request attack mode for contracts deployed via BattleChainDeployer
AttackRegistry.requestUnderAttack(address agreementAddress)

// Request attack mode for unverified contracts (extra DAO scrutiny)
AttackRegistry.requestUnderAttackForUnverifiedContracts(address agreementAddress)

// Skip attack mode entirely and go directly to production (no delay, no DAO approval)
AttackRegistry.goToProduction(address agreementAddress)

// Request promotion to production (3-day delay)
AttackRegistry.promote(address agreementAddress)

// Cancel a pending promotion (returns to UNDER_ATTACK)
AttackRegistry.cancelPromotion(address agreementAddress)

// Mark as corrupted after successful attack
AttackRegistry.markCorrupted(address agreementAddress)
```

### For DAO/Registry Moderator

```solidity
// Approve an agreement to enter attack mode
AttackRegistry.approveAttack(address agreementAddress)

// Reject an attack request (soft reject returns bond, hard reject slashes it)
AttackRegistry.rejectAttackRequest(address agreementAddress, bool slashBond)

// Instantly promote to production (skips attack phase, slashes bond)
AttackRegistry.instantPromote(address agreementAddress)

// Mark as corrupted when attack moderator is unresponsive (slashes bond)
AttackRegistry.instantCorrupt(address agreementAddress)
```

### Bond Management

```solidity
// Claim bond back after a claimable outcome (depositor only)
AttackRegistry.claimBond(address agreementAddress)

// Withdraw slashed bonds or stray tokens (owner only)
AttackRegistry.withdrawFunds(address token, address recipient) returns (uint256)

// Configure bond system (owner only)
AttackRegistry.setBondToken(address token)      // address(0) disables payments
AttackRegistry.setFeeAmount(uint256 amount)
AttackRegistry.setVerifiedBondAmount(uint256 amount)
AttackRegistry.setUnverifiedBondAmount(uint256 amount)
```

### DAO Monitoring: Unverified Contract Scope Expansion

When an agreement owner adds an **unverified contract** (not deployed via BattleChainDeployer) to their scope after the agreement is already registered, the AttackRegistry emits:

```solidity
event UnverifiedContractSynced(address indexed contractAddress, address indexed agreementAddress);
```

This event enables the DAO to monitor for potential abuse. "Unverified" means the contract has no on-chain ownership proof — there is no BattleChainDeployer provenance chain (`s_contractDeployer` → `s_authorizedOwner`).

**Why this matters:** An agreement owner could add contracts they don't control to their scope, causing `isTopLevelContractUnderAttack` to return `true` for those contracts and blocking them from being registered under other agreements.

**DAO response:** Call `instantPromote(agreementAddress)` to immediately move the agreement to PRODUCTION. This:
- Sets `isTopLevelContractUnderAttack` to `false` for all contracts in the agreement
- Frees griefed contracts so they can be registered under their rightful agreements
- Permanently ends the agreement's attack phase

Contracts deployed via BattleChainDeployer are not affected — they have on-chain authorization checks that prevent this type of abuse.

### For Ethical Hackers

**The Binding Agreement is the source of truth, and the resolution algorithm in `documents/seal-agreement-modified.md` (Section 2.3(b)(6) "Binding Agreement") is the specification.** Helpers below implement that algorithm for convenience — they are not themselves authoritative. If a helper's output disagrees with the algorithm applied to on-chain state and `ContractRegistered` event history, the algorithm controls.

Before conducting an Eligible Stress Test Exploit, resolve the Binding Agreement for each target contract via one of the helpers below — *not* via `BattleChainSafeHarborRegistry.getAgreement(adopter)`. The two registries can diverge; the AttackRegistry is dispositive per the legal agreement.

**Block explorer API (resolves top-level and child contracts):**

```
GET https://block-explorer-api.battlechain.com/battlechain/agreement/by-contract/{contractAddress}
GET https://block-explorer-api.testnet.battlechain.com/battlechain/agreement/by-contract/{contractAddress}
```

The API consults `AttackRegistry.getAgreementForContract` for top-level resolution and walks the deployer chain to the immediate parent for child resolution, evaluating `ChildContractScope` against the Cutoff Time. It returns the agreement(s) covering the contract along with their states. Where the linkage history yields more than one candidate, the most recently linked agreement is the Binding Agreement.

**Foundry helper (from `battlechain-lib`):**

```solidity
// Returns true if any agreement covering the contract is in
// UNDER_ATTACK or PROMOTION_REQUESTED state. Requires --ffi.
BCQuery.isAttackable(address contractAddress) returns (bool)
```

**Verification flow:**

```solidity
// 1. Resolve via the block explorer API or BCQuery to get the Binding Agreement
//    (handles top-level + child contracts uniformly).
// 2. Verify the contract is currently attackable:
require(BCQuery.isAttackable(contractAddress));
// 3. Read operative terms from the Binding Agreement returned by the resolver.
BountyTerms terms = IAgreement(bindingAgreement).getBountyTerms();
```

**On-chain primitives (used by the resolver, lower-level reads):**

```solidity
// True if the top-level agreement is in UNDER_ATTACK or PROMOTION_REQUESTED
AttackRegistry.isTopLevelContractUnderAttack(address contractAddress) returns (bool)

// Agreement linked to a top-level contract (zero if not top-level — for full
// top-level + child resolution, use the block explorer API or BCQuery)
AttackRegistry.getAgreementForContract(address contractAddress) returns (address)

// Detailed state of an agreement
AttackRegistry.getAgreementState(address agreementAddress) returns (ContractState)

// Full agreement info
AttackRegistry.getAgreementInfo(address agreementAddress) returns (AgreementInfo)

// Read terms from the Binding Agreement (use the address returned by the
// resolver — NOT the address from BattleChainSafeHarborRegistry.getAgreement)
Agreement.getBountyTerms() returns (BountyTerms)
Agreement.isContractInScope(address contractAddress) returns (bool)
```

> **Note:** `BattleChainSafeHarborRegistry.getAgreement(adopter)` returns the agreement the protocol adopted via `adoptSafeHarbor`. This is informational only — it can differ from the Binding Agreement, in which case the Binding Agreement controls. Do not rely on `BattleChainSafeHarborRegistry.getAgreement` to read bounty terms.

## Key Differences from SEAL Safe Harbor

- BattleChain agreements have Commitment Windows to prevent unfavorable changes
- AttackRegistry tracks contract states with DAO moderation
- Most contracts are behind UUPS proxies for upgradeability
- Obviously, we have the opt-in attack mode which SEAL does not have

## Known Issues

See [known-issues.md](./known-issues.md) for documented design decisions, accepted risks, and their mitigations.

## Future Work

- **Recovery Arbiter contract and factory (WIP)**: A contract that can govern the payouts of recovered funds, so that whitehats don't have to trust protocols to honor their agreements. This is currently blocked by having Chainlink price feeds. In order to make sure the caps and floors are respected, the value of the recovered assets must be known at the time of payout.
- **Oracle based bounty enforcement**: Currently, the bounty amounts are not enforced on-chain. We can use oracles to fetch the value of recovered assets at the time of payout to ensure compliance with the agreement terms.
- **DAO Governance**: DAOs suck, so we plan to have a DAC (decentralized autonomous corporation) where different roles are voted for (specifically, contract promoters and registry mods). This is a longer term goal.
- `createDefaultAgreement` or `deployAndAdopt`: A way to quickly do everything at once might be nice? Like a one-stop function to deploy an agreement, adopt it, and request under attack... But EIP-7702 might be enough...?

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Git

### Clone the Repository

```bash
git clone https://github.com/Cyfrin/battlechain-safe-harbor-contracts
cd battlechain-safe-harbor-contracts
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Formatting & Linting

```bash
forge fmt
forge lint
```

### Deploy

Deployment uses [just](https://github.com/casey/just) targets with Foundry's encrypted keystore for private key management.

**Setup:**

1. Copy `.env.example` to `.env` and fill in your deployer address:

```bash
cp .env.example .env
```

2. Import your deployer key into Foundry's encrypted keystore (or use a hardware wallet):

```bash
cast wallet import battlechain-testnet-deployer --interactive
```

**Deploy commands:**

```bash
# Step 1: Deploy SafeHarborRegistry + AgreementFactory
just deploy-safe-harbor

# Step 2: Deploy AttackRegistry + BattleChainDeployer (pass addresses from step 1)
just deploy-attack-registry <registry_proxy> <factory_proxy>

# Deploy mock registry moderator (testnet only)
just deploy-mock-moderator <attack_registry>

# Verify a contract
just verify <address> <path:ContractName>
```

All deploy targets include BattleChain-specific flags (`--skip-simulation -g 200`) and auto-verify on the block explorer. The `--sender` and `--account` can be overridden as positional args (see justfile).

**Scripts:**

- `script/Deploy.s.sol` - Deploy BattleChainSafeHarborRegistry and AgreementFactory
- `script/DeployAttackRegistry.s.sol` - Deploy AttackRegistry and BattleChainDeployer
- `script/HelperConfig.s.sol` - Network-specific configuration

## Acknowledgements

- [SEAL Safe Harbor project](https://github.com/security-alliance/safe-harbor)
- [Security Alliance](https://securityalliance.org/)

# Deployments

## Mainnet v5.0.0

Chain ID: `626`

| Contract                          | Address                                                              |
| --------------------------------- | -------------------------------------------------------------------- |
| CreateX                           | `0xa397f06F07251A3AEd53f6d3019A2a6cbd83E53e`                         |
| Registry Implementation           | `0x96d9cCEf1C2eBD19Cc4D3293Bd726c335F9523d7`                         |
| Registry Proxy                    | `0xd229f4EE1bAE432010b72a9d1bD682570F4C6eBe`                         |
| AgreementFactory Implementation   | `0xF52b4B00E6c33ED327886fc64c205a9F2DEc3623`                         |
| AgreementFactory Proxy            | `0xCdB7F5C0F708baBaabE82afE1DbA8362023AcFdd`                         |
| AttackRegistry Implementation     | `0x2d226C9f76748C3759F640Ee527Ad0D1A312fbB2`                         |
| AttackRegistry Proxy              | `0x24876e481eC7198CAC95af739Df2a852CE65A415`                         |
| BattleChainDeployer               | `0xD12765D21dDba418B8Fc0583c4716763e03Aa078`                         |
| Owner (Safe)                      | `0xfA26440c6DDc56C93A9248078e13a5eB050ADb1E`                         |
| Registry Moderator (Safe)         | `0x445d5685c4Ae71550Da0716b82B434AEA140E0c7`                         |
| Treasury (Safe)                   | `0x2B1731F5EedBa4141a66C6F81C5290BF61d3325c`                         |
| BattleChain Safe Harbor Agreement | `ipfs://bafkreienrabr3lklhbhir36tkzxzzygeeyodbwbvdgkv36hjum3glatqwq` |

## Testnet v5.0.0

Chain ID: `627`

| Contract                          | Address                                                              |
| --------------------------------- | -------------------------------------------------------------------- |
| CreateX                           | `0xf1Ebfaa992854ECcB01Ac1F60e5b5279095cca7F`                         |
| Registry Implementation           | `0x7d6fC65eA6436f1621973BcfeaAD8951853D8E35`                         |
| Registry Proxy                    | `0x07E09f67B272aec60eebBfB3D592eC649BDCFEFc`                         |
| AgreementFactory Implementation   | `0x8E940c4FE62ea1696751faA99F45F30459c6c978`                         |
| AgreementFactory Proxy            | `0xf52CEA27b9E20D03Ec48CDe4fafF8F27565646f2`                         |
| AttackRegistry Implementation     | `0x4496b7e04b4Dd94153AA0d614708d5f06fc65a13`                         |
| AttackRegistry Proxy              | `0x22134e878c409a0Eab7259d873b38e26Ca966d3C`                         |
| BattleChainDeployer               | `0x0f75289c6b883b885A1fDF9BCCABE1bbFB094077`                         |
| MockRegistryModerator             | `0x3DdA228A38b4d7438bBF5D5137c8D1090DcaF6bF`                         |
| Owner                             | `0x277D26a45Add5775F21256159F089769892CEa5B`                         |
| BattleChain Safe Harbor Agreement | `ipfs://bafkreienrabr3lklhbhir36tkzxzzygeeyodbwbvdgkv36hjum3glatqwq` |