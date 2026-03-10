// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IProposalManager} from "../interfaces/IProposerManager.sol";
import {IAuthorizationModule} from "../interfaces/IAuthorizationModule.sol";
import {IGovernanceProtection} from "../interfaces/IGovernanceProtection.sol";

contract ProposalManager is IProposalManager {
    
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
    
    // References to other modules
    IAuthorizationModule private _authModule;
    IGovernanceProtection private _govProtection;
    
    // Owner
    address private _owner;
    
    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function _onlyOwner() internal view {
        require(msg.sender == _owner, "Only owner");
    }

    constructor(address authModule, address govProtection) {
        require(authModule != address(0), "Invalid auth module");
        require(govProtection != address(0), "Invalid gov protection");
        
        _owner = msg.sender;
        _authModule = IAuthorizationModule(authModule);
        _govProtection = IGovernanceProtection(govProtection);
    }

    function createProposal(
        address target,
        uint256 value,
        bytes calldata data
    ) external returns (bytes32 proposalId) {
        require(target != address(0), "Invalid target");
        require(data.length > 0, "Empty proposal data");
        
        // Check governance limits
        require(_govProtection.checkProposalLimitsThatCanBeRequested(msg.sender, value), 
            "Proposal limit exceeded");
        
        // Generate unique proposalId
        proposalId = keccak256(abi.encodePacked(
            msg.sender,
            target,
            value,
            data,
            block.timestamp,
            block.number
        ));
        
        // Ensure unique proposal
        require(_proposals[proposalId].createdAt == 0, "Proposal already exists");
        
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
        
        // Move to committed state
        proposal.state = STATE_COMMITTED;
        emit ProposalCommitted(proposalId);
    }

    function markApprovalRequired(bytes32 proposalId) external {
        ProposalData storage proposal = _proposals[proposalId];
        require(proposal.createdAt != 0, "Proposal not found");
        require(proposal.state == STATE_COMMITTED, "Proposal not committed");
        
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
        
        // Move to queued state
        proposal.state = STATE_QUEUED;
        emit ProposalQueued(proposalId);
    }

    function cancelProposal(bytes32 proposalId) external {
        ProposalData storage proposal = _proposals[proposalId];
        require(proposal.createdAt != 0, "Proposal not found");
        require(msg.sender == proposal.proposer || msg.sender == _owner, "Unauthorized");
        
        // Can only cancel if not already queued/executed
        require(proposal.state != STATE_QUEUED, "Cannot cancel queued proposal");
        require(proposal.state != STATE_CANCELLED, "Already cancelled");
        
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
}
