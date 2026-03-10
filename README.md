# ARES Protocol Treasury System

A secure, modular treasury execution system designed to manage $500M+ in protocol assets with defense-in-depth architecture.

## Overview

ARES Protocol implements a multi-layered treasury system that prevents common DeFi attack vectors including governance takeovers, signature replay, flash loan manipulation, and timelock bypass attacks.

## Architecture

The system consists of 6 core components:

1. **AccessControl** - Custom, granular Role-Based Access Control (RBAC)
2. **AuthorizationModule** - EIP-712 signature verification with replay protection
3. **GovernanceProtection** - Economic attack mitigation (limits, caps, snapshots)
4. **ProposalManager** - Proposal lifecycle orchestration
5. **TimelockQueue** - Time-delayed execution with reentrancy protection
6. **RewardDistributor** - Merkle-based token distribution

## Key Features

-  **Custom RBAC:** Granular permissions (Admin, Proposer, Executor, Governance)
-  **EIP-712 signatures:** Structured data hashing with domain separation
-  **Nonce protection:** Replay protection (same-chain and cross-chain)
-  **Timelock execution:** Mandatory delays on all treasury operations
-  **Reentrancy guards:** Dual-layer protection (Mutex + CEI pattern)
-  **Merkle rewards:** Scalable token distribution (O(log n) gas)
-  **Flash loan defense:** Block-based historical voting snapshots
-  **Economic limits:** Per-address proposal limits and execution caps
-  **Linear lifecycle:** Multi-stage proposal flow with commit phase

## Project Structure

```
src/
├── core/                    # Core protocol modules
│   ├── AccessControl.sol        # RBAC implementation
│   ├── AuthorizationModule.sol  # Sig verification
│   ├── ProposalManager.sol      # State machine
│   └── TimelockQueue.sol        # Execution engine
├── interfaces/              # Contract interfaces
├── libraries/               # Utility libraries
└── modules/                 # Supporting modules
    ├── GovernanceProtection.sol # Economic guards
    └── RewardDistributor.sol    # Scalable claims
```
