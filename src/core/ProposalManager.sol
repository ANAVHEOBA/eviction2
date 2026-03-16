// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IProposalManager} from "../interfaces/IProposerManager.sol";
import {IAuthorizationModule} from "../interfaces/IAuthorizationModule.sol";
import {IGovernanceProtection} from "../interfaces/IGovernanceProtection.sol";
import {AccessControl} from "./AccessControl.sol";

contract ProposalManager is IProposalManager, AccessControl {
    
    // Proposal states
    uint8 private constant STATE_PENDING = 0;
    uint8 private constant STATE_COMMITTED = 1;
    uint8 private constant STATE_APPROVAL_REQUIRED = 2;
    uint8 private constant STATE_QUEUED = 3;
    uint8 private constant STATE_CANCELLED = 4;
    
    // Proposal storage
    struct ProposalData {
        address proposer;
        address target;
        uint256 value;
        bytes data;
        uint256 createdAt;
        uint8 state;
        bool approved;
    }
    
    mapping(bytes32 => ProposalData) private _proposals;
    
    // SECURITY FIX: Rate limiting for proposal spam prevention
    mapping(address => uint256) private _proposalCount;
    mapping(address => uint256) private _lastProposalTime;
    uint256 private _proposalCooldown; // Configurable cooldown period
    uint256 private constant MAX_PROPOSALS_PER_PROPOSER = 100; // Max active proposals per address
    
    // References to other modules
    IAuthorizationModule private _authModule;
    IGovernanceProtection private _govProtection;

    constructor(address authModule, address govProtection) {
        require(authModule != address(0), "Invalid auth module");
        require(govProtection != address(0), "Invalid gov protection");
        // SECURITY FIX: Validate that addresses are contracts, not EOAs
        require(_isContract(authModule), "Auth module must be a contract");
        require(_isContract(govProtection), "Gov protection must be a contract");
        
        _authModule = IAuthorizationModule(authModule);
        _govProtection = IGovernanceProtection(govProtection);
        
        // SECURITY FIX: Set default cooldown (can be changed by admin)
        _proposalCooldown = 1 minutes; // Default 1 minute cooldown
        
        // Deployer gets admin role via AccessControl constructor
        // We can also grant PROPOSER_ROLE to the deployer by default
        _grantRole(PROPOSER_ROLE, msg.sender);
    }
    
  
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function createProposal(
        address target,
        uint256 value,
        bytes calldata data
    ) external hasRole(PROPOSER_ROLE) returns (bytes32 proposalId) {
        require(target != address(0), "Invalid target");
        require(data.length > 0, "Empty proposal data");
        // SECURITY FIX: Prevent massive data griefing attacks
        require(data.length <= 10000, "Proposal data too large"); // 10KB max
        
        // SECURITY FIX: Rate limiting to prevent spam
        require(block.timestamp >= _lastProposalTime[msg.sender] + _proposalCooldown, "Proposal cooldown active");
        require(_proposalCount[msg.sender] < MAX_PROPOSALS_PER_PROPOSER, "Too many active proposals");
        
        // Check governance limits
        require(_govProtection.checkProposalLimitsThatCanBeRequested(msg.sender, value), 
            "Proposal limit exceeded");
        
        // CRITICAL FIX: Also enforce global execution cap
        require(_govProtection.enforceExecutionCap(value), "Exceeds execution cap");
        
        // Generate unique proposalId with secure entropy
        // SECURITY FIX: Removed gasleft() to prevent gas manipulation attacks
        // Note: block.difficulty is aliased to PREVRANDAO in post-merge Ethereum
        proposalId = keccak256(abi.encodePacked(
            msg.sender,
            target,
            value,
            data,
            block.timestamp,
            block.number,
            block.difficulty, // Aliased to PREVRANDAO post-merge
            _proposalCount[msg.sender] // Use proposal count as additional entropy
        ));
        
        // Ensure unique proposal
        require(_proposals[proposalId].createdAt == 0, "Proposal already exists");
        
        // SECURITY FIX: Update rate limiting state
        _proposalCount[msg.sender]++;
        _lastProposalTime[msg.sender] = block.timestamp;
        
        // Store proposal
        _proposals[proposalId] = ProposalData({
            proposer: msg.sender,
            target: target,
            value: value,
            data: data,
            createdAt: block.timestamp,
            state: STATE_PENDING,
            approved: false
        });
        
        emit ProposalCreated(proposalId, msg.sender);
        return proposalId;
    }

    function commitProposal(bytes32 proposalId) external {
        ProposalData storage proposal = _proposals[proposalId];
        require(proposal.createdAt != 0, "Proposal not found");
        require(proposal.state == STATE_PENDING, "Invalid proposal state");
        // SECURITY FIX: Only proposer or admin can commit
        require(msg.sender == proposal.proposer || hasRoleStatus(ADMIN_ROLE, msg.sender), "Unauthorized");
        
        // Move to committed state
        proposal.state = STATE_COMMITTED;
        emit ProposalCommitted(proposalId);
    }

    function markApprovalRequired(bytes32 proposalId) external {
        ProposalData storage proposal = _proposals[proposalId];
        require(proposal.createdAt != 0, "Proposal not found");
        require(proposal.state == STATE_COMMITTED, "Proposal not committed");
        // SECURITY FIX: Only proposer or admin can mark for approval
        require(msg.sender == proposal.proposer || hasRoleStatus(ADMIN_ROLE, msg.sender), "Unauthorized");
        
        // Move to approval required state
        proposal.state = STATE_APPROVAL_REQUIRED;
        emit ProposalApprovalRequired(proposalId);
    }

    function isApproved(bytes32 proposalId) external view returns (bool) {
        return _proposals[proposalId].approved;
    }

    function queueProposal(bytes32 proposalId) external {
        ProposalData storage proposal = _proposals[proposalId];
        require(proposal.createdAt != 0, "Proposal not found");
        require(proposal.state == STATE_APPROVAL_REQUIRED, "Proposal not ready for queuing");
        
        // Check that proposal is approved by authorization module
        require(_authModule.isApproved(proposalId), "Proposal not approved");
        
        // Mark as approved in storage
        proposal.approved = true;
        
        // SECURITY FIX: Decrement proposal count when queued (no longer "active" in manager)
        if (_proposalCount[proposal.proposer] > 0) {
            _proposalCount[proposal.proposer]--;
        }
        
        // Move to queued state
        proposal.state = STATE_QUEUED;
        emit ProposalQueued(proposalId);
    }

    function cancelProposal(bytes32 proposalId) external {
        ProposalData storage proposal = _proposals[proposalId];
        require(proposal.createdAt != 0, "Proposal not found");
        require(msg.sender == proposal.proposer || hasRoleStatus(ADMIN_ROLE, msg.sender), "Unauthorized");
        
        // Can only cancel if not already queued/executed
        require(proposal.state != STATE_QUEUED, "Cannot cancel queued proposal");
        require(proposal.state != STATE_CANCELLED, "Already cancelled");
        
        // SECURITY FIX: Decrement proposal count when cancelled
        if (_proposalCount[proposal.proposer] > 0) {
            _proposalCount[proposal.proposer]--;
        }
        
        proposal.state = STATE_CANCELLED;
        emit ProposalCancelled(proposalId);
    }

    function getProposal(bytes32 proposalId)
        external
        view
        returns (
            address proposer,
            address target,
            uint256 value,
            bytes memory data,
            uint256 createdAt,
            uint8 state
        )
    {
        ProposalData storage proposal = _proposals[proposalId];
        require(proposal.createdAt != 0, "Proposal not found");
        
        return (
            proposal.proposer,
            proposal.target,
            proposal.value,
            proposal.data,
            proposal.createdAt,
            proposal.state
        );
    }
    
  
    function setProposalCooldown(uint256 cooldown) external hasRole(ADMIN_ROLE) {
        require(cooldown <= 1 hours, "Cooldown too long");
        uint256 oldCooldown = _proposalCooldown;
        _proposalCooldown = cooldown;
        emit ProposalCooldownUpdated(oldCooldown, cooldown);
    }
    

    function getProposalCooldown() external view returns (uint256) {
        return _proposalCooldown;
    }
    
    
    function getProposalCount(address proposer) external view returns (uint256) {
        return _proposalCount[proposer];
    }
}
