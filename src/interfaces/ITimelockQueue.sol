// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;



interface ITimelockQueue {

    
    event TransactionThatWasQueued(bytes32 indexed proposalId);
    event TransactionThatWasExecuted(bytes32 indexed proposalId);
    event TransactionThatWasCancelled(bytes32 indexed proposalId);
    // Event for when execution is attempted too early
    event ExecutionDelayNotMet(bytes32 indexed proposalId, uint256 executeAfter, uint256 currentTime);


    // the name of the struct is QueuedTransaction 
    // the fields here that were used are proposalId, the target address(that the token that being interacted with), 
    //the value of the proposal, the description of the proposal that was encoded to bytes format 
    // the time when it was queued
    // the time that when it was put on queue took place
    // and the time that it was executed
    // and the time that it was cancelled
    struct QueuedTransaction {
    bytes32 proposalId;    
    address target;        
    uint256 value;         
    bytes data;            
    uint256 queuedAt;      
    uint256 executeAfter;  
    bool executed;         
    bool cancelled;        
}

    
    // to queue a particular transaction it takes in some input
    // the proposalId, the token address and it named as target and the value of that token, the description that was encoded in bytes and the 
    // the minDelay it will take in queue like how long it will take in queue whether it 3 days or more
    // Only queues approved proposals (requires isApproved() from IProposalManager)
    function queueTransaction(
        bytes32 proposalId,
        address target,
        uint256 value,
        bytes calldata data,
        uint256 minDelay
    ) external;

   
    // after the the transaction has been queued it then takes in an input 
    // the input are the proposalId which has a datatype of proposalId, and the token address, the value , the information which was 
    // encoded in bytes
    function executeTransaction(
        bytes32 proposalId,
        address target,
        uint256 value,
        bytes calldata data
    ) external;

    // Cancel a queued transaction before execution
    // cancel a transaction in queue by taking in the input of the transaction
    function cancelTransaction(bytes32 proposalId) external;

    
    // returns the details of every proposalId that was queued by taking the input
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
        );

    
    // returns the minDelay for all transactions that was queued which can be set it can be 3 days or more
    function getMinDelay() external view returns (uint256);

    // Check if enough time has passed to execute a queued transaction
    // Returns true if block.timestamp >= executeAfter
    function canExecute(bytes32 proposalId) external view returns (bool);

    //  Get count of queued transactions
    function getQueuedCount() external view returns (uint256);

}