// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


interface IGovernanceProtection {
    
    // Event for when proposal limit is exceeded
    event ProposalLimitExceeded(address indexed proposer, uint256 requestedValue, uint256 allowedValue);
    //  Event for when execution cap is exceeded
    event ExecutionCapExceeded(uint256 requestedValue, uint256 maxExecutable);

    // this takes in the proposer(address), and the value(uint256) and checks if the user can still propose up to that amount 
    // and returns true or false(sucessful or failure)
    //  Clarification - reverts if proposer exceeds limit (doesn't just return false)
    function checkProposalLimitsThatCanBeRequested(address proposer, uint256 value) external view returns (bool);

    // now this takes in the proposer address and checks if the user can still vote in the overall system
    //  Renamed to checkVotingPowerAvailable for clarity
    function checkVotingPowerIfItStillAvailable(address proposer) external view returns (bool);

    // now this takes in the value and ensures that the max that can be proposed and when it done it returns true or false (success or fail)
    //  Clarification - reverts if execution cap is exceeded
    function enforceExecutionCap(uint256 value) external view returns (bool);

    //  Get the current proposal limit for a proposer
    // Returns how much more they can propose
    function getRemainingProposalLimit(address proposer) external view returns (uint256);

    //  Get the global execution cap (max per single execution)
    function getExecutionCap() external view returns (uint256);

   
    // this takes the address of the user as the input and prevent instataneous loan without collateral in the system
    function snapshotVotingPower(address proposer) external;
}