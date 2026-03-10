// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


interface IAuthorizationModule {

    // Event emitted when a proposal is approved with signatures
    event ProposalApproved(bytes32 indexed proposalId, address[] signers);
    // Event emitted when a proposal approval is revoked
    event ApprovalRevoked(bytes32 indexed proposalId);
    // Event emitted when a nonce is consumed
    event NonceUsed(address indexed signer, uint256 nonce);

    // the name of the struct the fields of the struct basically are 
    // proposalId, target address, the value of the proposal, the information of the proposal and the nonce which is the unique signer of the person making 
    // the call
    // chainId for cross-chain replay protection
    struct TreasuryAction {
    bytes32 proposalId;  
    address target;      
    uint256 value;       
    bytes data;          
    uint256 nonce;       
    uint256 chainId;     
    }

    
    // This ensures signatures cannot be replayed across domains, forks, or chains
    function domainSeparator() external view returns (bytes32);

    // Verify a single signature
    // now to verify a signature the fields being taken in are the action and the signature 
    // and the response is whether it was successful or not 
    // Treasury action contains all the data of that request then
    // and the address of the person that signed
    // and the signature is the signature a proof that someone signed on all the data
    function verifySignature(
        TreasuryAction calldata action,
        address signer,
        bytes calldata signature
    ) external view returns (bool);

    // Approve a proposal with multiple signatures
    // the data that has all the fields from the struct then
    // the list of signatures for multisig that has a bytes data type and stored in call data cause it cheaper
    function approveProposal(
        TreasuryAction calldata action,
        address[] calldata signers,
        bytes[] calldata signatures
    ) external;

    
    // check if a proposal has been approved or not and shows a successful response true or false in the response
    function isApproved(bytes32 proposalId) external view returns (bool);

    
    // now takes the signer address as the input and returns the nonce of the person who signed it and the data type is uint256
    function getNonce(address signer) external view returns (uint256);

   
    // mark a particular nonce that it has been used already 
    // takes the input of the person signing it 
    // and the nonce and it has a data type of uint256 and it visibilty is external
    function markNonceUsed(address signer, uint256 nonce) external;

   
    // Takes the proposalId as the input and revokes all approvals for that proposal
    function revokeApproval(bytes32 proposalId) external;


}