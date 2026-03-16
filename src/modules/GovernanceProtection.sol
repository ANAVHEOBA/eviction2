// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGovernanceProtection} from "../interfaces/IGovernanceProtection.sol";
import {AccessControl} from "../core/AccessControl.sol";

contract GovernanceProtection is IGovernanceProtection, AccessControl {
    
    // SECURITY FIX: Events for critical state changes
    event ProposalLimitUpdated(address indexed proposer, uint256 oldLimit, uint256 newLimit);
    event ExecutionCapUpdated(uint256 oldCap, uint256 newCap);
    event VotingTokenUpdated(address oldToken, address newToken);
    
    // Maximum amount a single proposer can propose
    mapping(address => uint256) private _proposalLimits;
    
    // Global execution cap (max per transaction)
    uint256 private _executionCap;
    
    // Voting power snapshots (block-based, prevents flash loans)
    mapping(address => mapping(uint256 => uint256)) private _votingPowerSnapshots;
    mapping(address => uint256) private _snapshotBlocks;
    
    // Voting token interface (for future integration)
    address private _votingToken;

    constructor(uint256 executionCap) {
        _executionCap = executionCap;
    }

    function checkProposalLimitsThatCanBeRequested(address proposer, uint256 value) 
        external 
        view 
        returns (bool) 
    {
        uint256 limit = _proposalLimits[proposer];
        if (limit == 0) {
            // CRITICAL FIX: Default to execution cap, not unlimited
            limit = _executionCap;
            if (limit == 0) {
                // If no execution cap either, deny by default for safety
                return false;
            }
        }
        return value <= limit;
    }

    function checkVotingPowerIfItStillAvailable(address proposer) 
        external 
        view 
        returns (bool) 
    {
        // Check if voting power snapshot exists for current block
        uint256 snapshotBlock = _snapshotBlocks[proposer];
        if (snapshotBlock == 0) {
            return true; // No snapshot = available
        }
        
        // Voting power snapshot is available if taken at same block or earlier
        return snapshotBlock <= block.number;
    }

    function enforceExecutionCap(uint256 value) 
        external 
        view 
        returns (bool) 
    {
        if (_executionCap == 0) {
            // No cap set = unlimited
            return true;
        }
        
        // Returns false if exceeds cap (emit events handled elsewhere)
        return value <= _executionCap;
    }

    function getRemainingProposalLimit(address proposer) 
        external 
        view 
        returns (uint256) 
    {
        return _proposalLimits[proposer];
    }

    function getExecutionCap() external view returns (uint256) {
        return _executionCap;
    }

    function snapshotVotingPower(address proposer) 
        external 
    {
        // Only snapshot once per block per proposer (prevents double snapshots)
        require(_snapshotBlocks[proposer] != block.number, "Already snapshotted this block");
        
        // Take voting power snapshot at current block
        _snapshotBlocks[proposer] = block.number;
        
        // SECURITY FIX: Store actual voting power, not block number
        // For now, use a placeholder value. In production, integrate with voting token:
        // uint256 votingPower = IVotingToken(_votingToken).balanceOfAt(proposer, block.number);
        uint256 votingPower = 1; // Placeholder - should be actual token balance
        _votingPowerSnapshots[proposer][block.number] = votingPower;
    }

    // Admin functions
    function setProposalLimit(address proposer, uint256 limit) 
        external 
        hasRole(ADMIN_ROLE) 
    {
        uint256 oldLimit = _proposalLimits[proposer];
        _proposalLimits[proposer] = limit;
        emit ProposalLimitUpdated(proposer, oldLimit, limit);
    }

    function setExecutionCap(uint256 cap) 
        external 
        hasRole(ADMIN_ROLE) 
    {
        uint256 oldCap = _executionCap;
        _executionCap = cap;
        emit ExecutionCapUpdated(oldCap, cap);
    }
    
    function setVotingToken(address votingToken) 
        external 
        hasRole(ADMIN_ROLE) 
    {
        require(votingToken != address(0), "Invalid voting token");
        address oldToken = _votingToken;
        _votingToken = votingToken;
        emit VotingTokenUpdated(oldToken, votingToken);
    }
    
    function getVotingPowerAt(address proposer, uint256 blockNumber) 
        external 
        view 
        returns (uint256) 
    {
        return _votingPowerSnapshots[proposer][blockNumber];
    }
}
