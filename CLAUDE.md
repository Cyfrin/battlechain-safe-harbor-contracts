# BattleChain Safe Harbor

## Overview

This repo contains the Safe Harbor contracts for BattleChain - a pre-mainnet, post-testnet environment with real funds (incentivized testnet) that encourages ethical hackers and AI bots to stress test protocols before mainnet launch.

## Architecture

### Core Contracts

1. **BattleChainSafeHarborRegistry.sol** - Maps protocol addresses to their Agreement contracts
2. **Agreement.sol** - Per-protocol contract containing bounty terms, contact details, and scope
3. **AgreementFactory.sol** - Factory for creating Agreement contracts with CREATE2
4. **AttackRegistry.sol** - Tracks contract attack/production status (NOT_DEPLOYED → ATTACK_REQUESTED → UNDER_ATTACK → PROMOTION_REQUESTED → PRODUCTION, or CORRUPTED)

The README's "Mechanisms" and "Known Issues" sections explain the problem BattleChain solves and how the attack/production lifecycle works.