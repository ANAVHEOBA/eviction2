# ARES Treasury: Architectural Rationale

## Core Design Philosophy
When designing a system meant to manage half a billion dollars in protocol assets, the primary objective is not just efficiency, but **resiliency**. We move away from the "all-in-one" vault pattern because it represents a single, massive point of failure. Instead, ARES implements a pipeline architecture where treasury actions must flow through multiple, isolated layers. Each layer has one job: verify a specific security property. This defense-in-depth strategy ensures that an exploit in one area cannot be leveraged to bypass the core authorization or timelock mechanisms.

## 1. Modular Separation & Granular Permissions
The system is decomposed into six specialized components. A critical architectural choice in this version is the implementation of a custom **Role-Based Access Control (RBAC)** system. We have moved away from the standard `onlyOwner` pattern to follow the **Principle of Least Privilege**.

### The Security Root: AccessControl
This custom module defines specific roles: `ADMIN_ROLE`, `PROPOSER_ROLE`, `EXECUTOR_ROLE`, and `GOVERNANCE_ROLE`. By splitting these powers, we ensure that a compromised "Proposer" key cannot be used to bypass the timelock or change protocol parameters. This granular control is essential for a system with $500M at stake, allowing for different committees (e.g., a "Risk Committee" and an "Operations Committee") to have strictly scoped powers.

### The Foundation: AuthorizationModule
The `AuthorizationModule` is our cryptographic root. Its responsibility is to verify that a quorum of signers has approved a specific `TreasuryAction`. By isolating this logic, we ensure that the complex assembly needed for EIP-712 hashing doesn't interfere with the state management in other modules. We chose EIP-712 over raw signatures because it provides "What You See Is What You Sign" (WYSIWYS) capability. When a signer interacts with a wallet, they see structured data rather than an opaque hex string, providing a critical human-layer defense against phishing.

### The Policy Layer: GovernanceProtection
This module acts as the "economic guardrails." It is independent of the proposal lifecycle. It checks execution caps and rate limits to enforce global safety policies. We implemented a "Snapshot" mechanism as a defense against flash-loan governance manipulation. Even if an attacker acquires temporary voting power, the system requires that power to be validated against a historical block height, rendering flash-loaned tokens useless for treasury actions.

### The State Machine: ProposalManager
The `ProposalManager` is the orchestrator. It manages the proposal lifecycle from `PENDING` to `QUEUED`. A critical feature here is the **Commit Phase**. We force proposers to commit their parameters early, killing front-running attacks because an attacker cannot submit a slightly modified malicious proposal in the same block. The state machine is strictly linear; once a proposal moves to `APPROVAL_REQUIRED`, its parameters are immutable, preventing "bait-and-switch" attacks.

### The Execution Guard: TimelockQueue
This is the final checkpoint. Every transaction must sit in the `TimelockQueue`, which stops reentrancy and provides a "reaction window." If a proposal is malicious but somehow passes the authorization quorum, the mandatory 3-day delay gives the community time to react. The queue uses a "Hash-as-Key" approach, ensuring a single proposal can only be queued once, preventing "replay-after-execution" attacks.

### Independent Scaling: RewardDistributor
We kept reward distribution separate. Treasury execution is slow and high-security; reward claiming needs to be fast and low-gas. By using a Merkle-based system, we can serve 10,000 contributors with a single 32-byte root update, avoiding the O(n) gas costs of iterative transfers. The Merkle tree also ensures funds remain in the contract until users claim them, meaning the protocol doesn't push tokens to potentially compromised addresses.

## 2. Security Boundaries
We've implemented strict boundaries to prevent "privilege escalation":
- **Execution isolation:** Only the `TimelockQueue` can perform external calls. The `ProposalManager` and `AuthorizationModule` are internal-state handlers. 
- **Role-based boundaries:** Different modules require different roles. For example, `RewardDistributor` root updates require `GOVERNANCE_ROLE`, while timelock execution requires `EXECUTOR_ROLE`.
- **Data Integrity:** We use a "Double-Hash" verification pattern. If even a single byte of the payload is changed between proposal and execution, the hashes will mismatch and the transaction will revert.

## 3. Trust Assumptions
1. **Quorum Integrity:** We assume a majority of signers are honest.
2. **Oracle Reliability:** We trust the Ethereum `block.timestamp`. The protocol's 3-day delay is large enough to make minor timestamp manipulation irrelevant.
3. **Role Segregation:** We assume the `ADMIN_ROLE` will be held by a different multisig than the `EXECUTOR_ROLE`, preventing a single compromised key from taking full control.

## 4. Conclusion
ARES is built to be predictable. By splitting logic into isolated modules and enforcing granular roles, we have reduced the complexity and risk of the system. This modularity makes the entire system easier to audit and harder to exploit, resulting in a system that is secure against current attack vectors and flexible enough for future upgrades.
