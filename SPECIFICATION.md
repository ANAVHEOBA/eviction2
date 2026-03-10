# ARES Protocol Specification

This document provides a formal description of the ARES Protocol treasury lifecycle, including the proposal process, authorization mechanisms, and execution guarantees.

## Role-Based Access Control (RBAC)

The protocol uses a custom RBAC system to enforce the Principle of Least Privilege.

| Role | Responsibility |
| :--- | :--- |
| **ADMIN_ROLE** | Manage role assignments, set execution caps, and update protocol parameters. |
| **PROPOSER_ROLE** | Create new treasury proposals. |
| **EXECUTOR_ROLE** | Trigger the execution of queued transactions after the timelock expires. |
| **GOVERNANCE_ROLE** | Update the Merkle root for reward distributions. |

## Proposal Lifecycle

A proposal must progress through each stage without skipping security checks.

### 1. Proposal Creation
- **Action:** `ProposalManager.createProposal(target, value, data)`
- **Permission:** Requires `PROPOSER_ROLE`.
- **Validation:** 
    - Checks `GovernanceProtection` for per-address proposal limits.
    - Generates a unique `proposalId`.
- **State Transition:** `PENDING`

### 2. Commit Phase
- **Action:** `ProposalManager.commitProposal(proposalId)`
- **Purpose:** Locks proposal parameters to prevent front-running.
- **State Transition:** `COMMITTED`

### 3. Approval Requirement
- **Action:** `ProposalManager.markApprovalRequired(proposalId)`
- **Purpose:** Signals readiness for cryptographic authorization.
- **State Transition:** `APPROVAL_REQUIRED`

### 4. Cryptographic Authorization
- **Action:** `AuthorizationModule.approveProposal(action, signers, signatures)`
- **Validation:** 
    - Verifies EIP-712 structured signatures.
    - Enforces nonce-based replay protection.
- **State Transition:** `APPROVED` (Internally tracked)

### 5. Queueing for Execution
- **Action:** `TimelockQueue.queueTransaction(...)`
- **Validation:** 
    - Verifies that `isApproved(proposalId)` is true.
    - Enforces the minimum timelock delay (3 days).
- **State Transition:** `QUEUED`

### 6. Final Execution
- **Action:** `TimelockQueue.executeTransaction(...)`
- **Permission:** Requires `EXECUTOR_ROLE`.
- **Validation:** 
    - Verifies `block.timestamp >= executeAfter`.
    - Enforces reentrancy protection.
    - Marks as `executed` before external call (CEI pattern).
- **State Transition:** `EXECUTED`

### 7. Cancellation
- **Action:** `ProposalManager.cancelProposal(proposalId)`
- **Permissions:** Original proposer OR an account with `ADMIN_ROLE`.
- **State Transition:** `CANCELLED`

## Module Responsibilities

- **AccessControl:** Centralized permission management.
- **AuthorizationModule:** Cryptographic root of trust. Handles signatures and nonces.
- **GovernanceProtection:** Economic policy enforcement.
- **ProposalManager:** Orchestration of the proposal state machine.
- **TimelockQueue:** Execution safety and time-delay enforcement.
- **RewardDistributor:** Scalable Merkle-based distributions.
