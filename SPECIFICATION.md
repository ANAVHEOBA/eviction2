# ARES Protocol Specification

This document provides a formal description of the ARES Protocol treasury lifecycle, including the proposal process, authorization mechanisms, and execution guarantees.

## Proposal Lifecycle

The ARES Protocol enforces a strict state-machine for all treasury operations. A proposal must progress through each stage without skipping security checks.

### 1. Proposal Creation
- **Action:** `ProposalManager.createProposal(target, value, data)`
- **Validation:** 
    - Checks `GovernanceProtection` for per-address proposal limits.
    - Generates a unique `proposalId` using `keccak256` hash of parameters, timestamp, and block number.
- **State Transition:** `PENDING`

### 2. Commit Phase
- **Action:** `ProposalManager.commitProposal(proposalId)`
- **Purpose:** Prevents front-running of proposal parameters. Once committed, the proposal details are locked and cannot be altered.
- **State Transition:** `COMMITTED`

### 3. Approval Requirement
- **Action:** `ProposalManager.markApprovalRequired(proposalId)`
- **Purpose:** Signals that the proposal is ready for cryptographic authorization.
- **State Transition:** `APPROVAL_REQUIRED`

### 4. Cryptographic Authorization
- **Action:** `AuthorizationModule.approveProposal(action, signers, signatures)`
- **Validation:** 
    - Verifies EIP-712 structured signatures.
    - Enforces nonce-based replay protection.
    - Validates `chainId` and `verifyingContract` domain separation.
- **State Transition:** `APPROVED` (Internally tracked in `AuthorizationModule`)

### 5. Queueing for Execution
- **Action:** `ProposalManager.queueProposal(proposalId)` followed by `TimelockQueue.queueTransaction(...)`
- **Validation:** 
    - Verifies that `isApproved(proposalId)` is true in the `AuthorizationModule`.
    - Enforces the minimum timelock delay (default: 3 days).
- **State Transition:** `QUEUED`

### 6. Final Execution
- **Action:** `TimelockQueue.executeTransaction(...)`
- **Validation:** 
    - Verifies `block.timestamp >= executeAfter`.
    - Enforces reentrancy protection.
    - Marks transaction as `executed` before external call (CEI pattern).
- **State Transition:** `EXECUTED`

### 7. Cancellation
- **Action:** `ProposalManager.cancelProposal(proposalId)`
- **Permissions:** Can only be called by the original proposer or the system owner.
- **Constraint:** Cannot cancel once a proposal has reached the `QUEUED` state in the timelock.
- **State Transition:** `CANCELLED`

## Module Responsibilities

- **AuthorizationModule:** Cryptographic root of trust. Handles signatures and nonces.
- **GovernanceProtection:** Policy enforcement. Handles limits, caps, and flash-loan snapshots.
- **ProposalManager:** Orchestration. Manages the state machine and module coordination.
- **TimelockQueue:** Execution safety. Enforces delays and reentrancy guards.
- **RewardDistributor:** Scaling. Manages independent Merkle-based distributions.
