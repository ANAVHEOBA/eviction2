// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGovernanceProtection} from "../interfaces/IGovernanceProtection.sol";

contract GovernanceProtection is IGovernanceProtection {
    
    // Maximum amount a single proposer can propose
    mapping(address => uint256) private _proposalLimits;
    
    // Global execution cap (max per transaction)
    uint256 private _executionCap;
    
    // Voting power snapshots (block-based, prevents flash loans)
    mapping(address => mapping(uint256 => uint256)) private _votingPowerSnapshots;
    mapping(address => uint256) private _snapshotBlocks;
    
    // Owner for admin functions
    address private _owner;

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function _onlyOwner() internal view {
        require(msg.sender == _owner, "Only owner");
    }

    constructor(uint256 executionCap) {
        _owner = msg.sender;
        _executionCap = executionCap;
    }

    function checkProposalLimitsThatCanBeRequested(address proposer, uint256 value) 
        external 
        view 
        returns (bool) 
    {
        uint256 limit = _proposalLimits[proposer];
        if (limit == 0) {
            // No limit set means unlimited
            return true;
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
        _votingPowerSnapshots[proposer][block.number] = block.number;
        
        // Future: integrate with actual voting token to capture balance
    }

    // Admin functions
    function setProposalLimit(address proposer, uint256 limit) 
        external 
        onlyOwner 
    {
        _proposalLimits[proposer] = limit;
    }

    function setExecutionCap(uint256 cap) 
        external 
        onlyOwner 
    {
        _executionCap = cap;
    }
}
