// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IProposalManager {

    // an event for proposal created
    event ProposalCreated(bytes32 indexed proposalId, address proposer);
    // and event for proposal that was committed
    event ProposalCommitted(bytes32 indexed proposalId);
    // Event for when proposal is approved by the person that was authorized
    event ProposalApprovalRequired(bytes32 indexed proposalId);
    // an event for proposal that was queued
    event ProposalQueued(bytes32 indexed proposalId);
    // an event for proposal that was cancelled
    event ProposalCancelled(bytes32 indexed proposalId);
    // Event for when proposal execution fails
    event ProposalExecutionFailed(bytes32 indexed proposalId, string reason); 
    
    // the first function to create a proposol
    // the input are target(the address) the value of the proposl(uint) and the description(bytes) that convertes to bytes
    // and it then returns the proposalId of the like a unique id for each proposal
    function createProposal(
        address target,
        uint256 value,
        bytes calldata data
    ) external returns (bytes32 proposalId);
    

    // to mark the proposal as ready for review and it takes in the unique proposalId
    // to mark it for review
    function commitProposal(bytes32 proposalId) external;

    // Mark proposal as requiring cryptographic approval (called by governance)
  
    function markApprovalRequired(bytes32 proposalId) external;

    // Check if a proposal has been approved by authorization module
    // Must return true before queueProposal() can be called
    function isApproved(bytes32 proposalId) external view returns (bool);


    // letter has been approved and it then put in a waiting line before it then get sent
    // state changes from commited to queued 
    function queueProposal(bytes32 proposalId) external;
    
    // function to cancel the proposal and it takes in the id of the prpopoal
    function cancelProposal(bytes32 proposalId) external;
    

    // now this takes in the unique id of the proposal to get the address of the proposal
    // address of the person that receiving the proposal and the value 
    // and the details of the proposal
    // the date of the proposal
    // the current state of the proposal 
    // commit, queue, cancel
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
        );
}