// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ITimelockQueue} from "../interfaces/ITimelockQueue.sol";
import {IProposalManager} from "../interfaces/IProposerManager.sol";
import {AccessControl} from "./AccessControl.sol";

contract TimelockQueue is ITimelockQueue, AccessControl {
    
    // Queue storage
    mapping(bytes32 => QueuedTransaction) private _queue;
    
    // List of queued proposal IDs for enumeration
    bytes32[] private _queuedProposals;
    
    // SECURITY FIX: Queue size limit to prevent unbounded growth
    uint256 private constant MAX_QUEUED_TRANSACTIONS = 100;
    uint256 private _activeQueuedCount; // Track non-executed/non-cancelled transactions
    
    // Reference to proposal manager
    IProposalManager private _proposalManager;
    
    // Global minimum delay (can be overridden per transaction)
    uint256 private _minDelay;
    
    // Reentrancy guard
    uint256 private _locked = 1;

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() internal {
        require(_locked == 1, "No reentrancy");
        _locked = 2;
    }

    function _nonReentrantAfter() internal {
        _locked = 1;
    }

    constructor(address proposalManager, uint256 minDelay) {
        require(proposalManager != address(0), "Invalid proposal manager");
        require(minDelay > 0, "Invalid min delay");
        // SECURITY FIX: Validate that proposal manager is a contract
        require(_isContract(proposalManager), "Proposal manager must be a contract");
        
        _proposalManager = IProposalManager(proposalManager);
        _minDelay = minDelay;
        
        // Grant EXECUTOR_ROLE to the deployer by default
        _grantRole(EXECUTOR_ROLE, msg.sender);
    }
    
  
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function queueTransaction(
        bytes32 proposalId,
        address target,
        uint256 value,
        bytes calldata data,
        uint256 minDelay
    ) external {
        require(target != address(0), "Invalid target");
        require(minDelay >= _minDelay, "Delay too short");
        
        // SECURITY FIX: Prevent queue spam DoS
        require(_activeQueuedCount < MAX_QUEUED_TRANSACTIONS, "Queue is full");
        
        // Verify proposal exists and is approved
        (address proposer, address storedTarget, uint256 storedValue, , , ) = 
            _proposalManager.getProposal(proposalId);
        
        require(proposer != address(0), "Proposal not found");
        require(_proposalManager.isApproved(proposalId), "Proposal not approved");
        require(storedTarget == target && storedValue == value, "Data mismatch");
        
        // Ensure not already queued
        require(_queue[proposalId].queuedAt == 0, "Already queued");
        
        // Calculate execution time
        uint256 executeAfter = block.timestamp + minDelay;
        
        // Queue transaction
        _queue[proposalId] = QueuedTransaction({
            proposalId: proposalId,
            target: target,
            value: value,
            data: data,
            queuedAt: block.timestamp,
            executeAfter: executeAfter,
            executed: false,
            cancelled: false
        });
        
        _queuedProposals.push(proposalId);
        _activeQueuedCount++; // SECURITY FIX: Track active queue size
        emit TransactionThatWasQueued(proposalId);
    }

    function executeTransaction(
        bytes32 proposalId,
        address target,
        uint256 value,
        bytes calldata data
    ) external nonReentrant hasRole(EXECUTOR_ROLE) {
        QueuedTransaction storage txn = _queue[proposalId];
        
        // Verify transaction exists
        require(txn.queuedAt != 0, "Transaction not queued");
        
        // Verify not already executed
        require(!txn.executed, "Already executed");
        
        // Verify not cancelled
        require(!txn.cancelled, "Transaction cancelled");
        
        // CRITICAL FIX: Verify ALL parameters match including data
        require(txn.target == target && txn.value == value, "Target/value mismatch");
        require(keccak256(txn.data) == keccak256(data), "Data mismatch");
        
        // CRITICAL: Enforce time delay
        if (block.timestamp < txn.executeAfter) {
            emit ExecutionDelayNotMet(proposalId, txn.executeAfter, block.timestamp);
            revert("Execution delay not met");
        }
        
        // Mark as executed before external call (prevent reentrancy)
        txn.executed = true;
        
        // SECURITY FIX: Decrement active queue count
        if (_activeQueuedCount > 0) {
            _activeQueuedCount--;
        }
        
        // Execute the transaction
        (bool success, bytes memory result) = target.call{value: value}(data);
        
        if (!success) {
            // Decode error message if available
            if (result.length > 0) {
                assembly {
                    let returndata_size := mload(result)
                    revert(add(32, result), returndata_size)
                }
            }
            revert("Execution failed");
        }
        
        emit TransactionThatWasExecuted(proposalId);
    }

    function cancelTransaction(bytes32 proposalId) external hasRole(ADMIN_ROLE) {
        QueuedTransaction storage txn = _queue[proposalId];
        require(txn.queuedAt != 0, "Transaction not queued");
        require(!txn.executed, "Already executed");
        require(!txn.cancelled, "Already cancelled");
        
        txn.cancelled = true;
        
        // SECURITY FIX: Decrement active queue count
        if (_activeQueuedCount > 0) {
            _activeQueuedCount--;
        }
        
        emit TransactionThatWasCancelled(proposalId);
    }

    function getQueuedTransaction(bytes32 proposalId)
        external
        view
        returns (
            address target,
            uint256 value,
            bytes memory data,
            uint256 queuedAt,
            uint256 executeAfter,
            bool executed,
            bool cancelled
        )
    {
        QueuedTransaction storage txn = _queue[proposalId];
        require(txn.queuedAt != 0, "Transaction not queued");
        
        return (
            txn.target,
            txn.value,
            txn.data,
            txn.queuedAt,
            txn.executeAfter,
            txn.executed,
            txn.cancelled
        );
    }

    function getMinDelay() external view returns (uint256) {
        return _minDelay;
    }

    function canExecute(bytes32 proposalId) external view returns (bool) {
        QueuedTransaction storage txn = _queue[proposalId];
        if (txn.queuedAt == 0 || txn.executed || txn.cancelled) {
            return false;
        }
        return block.timestamp >= txn.executeAfter;
    }

    function getQueuedCount() external view returns (uint256) {
        return _queuedProposals.length;
    }

    // Admin: Update global min delay
    function setMinDelay(uint256 newDelay) external hasRole(ADMIN_ROLE) {
        require(newDelay > 0, "Invalid delay");
        // SECURITY FIX: Add maximum delay cap to prevent DoS
        require(newDelay <= 365 days, "Delay too long");
        _minDelay = newDelay;
    }
}
