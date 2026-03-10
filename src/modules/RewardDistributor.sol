// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";
import {IERC20} from "../interfaces/IERC20.sol";

contract RewardDistributor is IRewardDistributor {
    
    // Merkle root for valid claims
    bytes32 private _merkleRoot;
    
    // Track claimed recipients
    mapping(address => bool) private _claimed;
    
    // Total tokens allocated for claims
    uint256 private _totalAllocated;
    
    // Total tokens claimed so far
    uint256 private _totalClaimed;
    
    // ERC20 token for rewards
    IERC20 private _rewardToken;
    
    // Recipient tracking for enumeration
    address[] private _recipients;
    mapping(address => uint256) private _recipientIndex;
    mapping(address => bool) private _recipientExists;
    
    // Claim amounts registry (address => amount eligible to claim)
    mapping(address => uint256) private _claimAmounts;
    
    // Owner/governance
    address private _owner;

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function _onlyOwner() internal view {
        require(msg.sender == _owner, "Only owner");
    }

    constructor(bytes32 initialRoot, uint256 totalAllocated, address rewardToken) {
        require(initialRoot != bytes32(0), "Invalid merkle root");
        require(totalAllocated > 0, "Invalid allocation");
        require(rewardToken != address(0), "Invalid token");
        
        _owner = msg.sender;
        _merkleRoot = initialRoot;
        _totalAllocated = totalAllocated;
        _rewardToken = IERC20(rewardToken);
    }

    function claim(
        address recipient,
        uint256 amount,
        bytes32[] calldata proof
    ) external {
        _processClaim(recipient, amount, proof);
    }

    function hasClaimed(address recipient) external view returns (bool) {
        return _claimed[recipient];
    }

    function updateMerkleRoot(bytes32 newRoot) external onlyOwner {
        require(newRoot != bytes32(0), "Invalid merkle root");
        
        bytes32 oldRoot = _merkleRoot;
        _merkleRoot = newRoot;
        
        emit MerkleRootUpdated(oldRoot, newRoot);
    }

    function getMerkleRoot() external view returns (bytes32) {
        return _merkleRoot;
    }

    function getTotalUnclaimed() external view returns (uint256) {
        return _totalAllocated - _totalClaimed;
    }

    function getTotalClaimed() external view returns (uint256) {
        return _totalClaimed;
    }

    function getTotalAllocated() external view returns (uint256) {
        return _totalAllocated;
    }

    function getRecipients(uint256 offset, uint256 limit) 
        external 
        view 
        returns (address[] memory) 
    {
        require(offset < _recipients.length, "Offset out of bounds");
        require(limit > 0, "Limit must be > 0");
        
        uint256 remaining = _recipients.length - offset;
        uint256 count = limit > remaining ? remaining : limit;
        
        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = _recipients[offset + i];
        }
        
        return result;
    }

    function getRecipientCount() external view returns (uint256) {
        return _recipients.length;
    }

    function getClaimAmount(address recipient, uint256 amount, bytes32[] calldata proof) 
        external 
        view 
        returns (uint256) 
    {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        
        // If already claimed, return the historical amount
        if (_claimed[recipient]) {
            return _claimAmounts[recipient];
        }
        
        // If not claimed, verify the proof against the merkle root
        // This validates that the recipient/amount pair is in the merkle tree
        if (_verifyProof(proof, recipient, amount)) {
            return amount;
        }
        
        // If proof is invalid or doesn't match, return 0
        return 0;
    }

    function getRewardToken() external view returns (address) {
        return address(_rewardToken);
    }

    function isRecipient(address account) external view returns (bool) {
        return _recipientExists[account];
    }

    function getRecipientByIndex(uint256 index) external view returns (address) {
        require(index < _recipients.length, "Index out of bounds");
        return _recipients[index];
    }

    function batchClaim(
        address[] calldata recipients,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external {
        require(recipients.length == amounts.length, "Recipients/amounts length mismatch");
        require(amounts.length == proofs.length, "Amounts/proofs length mismatch");
        require(recipients.length > 0, "Empty batch");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            // Call internal claim logic for each recipient
            _processClaim(recipients[i], amounts[i], proofs[i]);
        }
    }

    function _processClaim(
        address recipient,
        uint256 amount,
        bytes32[] calldata proof
    ) internal {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        
        // Prevent double claim
        if (_claimed[recipient]) {
            emit DoubleClaimAttempted(recipient);
            revert("Already claimed");
        }
        
        // Verify merkle proof
        require(_verifyProof(proof, recipient, amount), "Invalid proof");
        
        // Track recipient for enumeration (if not already tracked)
        if (!_recipientExists[recipient]) {
            _recipientIndex[recipient] = _recipients.length;
            _recipients.push(recipient);
            _recipientExists[recipient] = true;
        }
        
        // Store claim amount for later queries
        _claimAmounts[recipient] = amount;
        
        // Mark as claimed BEFORE transfer (CEI pattern)
        _claimed[recipient] = true;
        _totalClaimed += amount;
        
        // Transfer ERC20 tokens
        require(_rewardToken.transfer(recipient, amount), "Transfer failed");
        
        emit ClaimProcessed(recipient, amount);
    }

    function withdrawUnclaimed(address recipient, uint256 amount) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        
        uint256 unclaimedAmount = _totalAllocated - _totalClaimed;
        require(amount <= unclaimedAmount, "Insufficient unclaimed tokens");
        
        _totalAllocated -= amount;
        require(_rewardToken.transfer(recipient, amount), "Withdrawal failed");
    }

    // Internal: Verify merkle proof
    function _verifyProof(
        bytes32[] calldata proof,
        address recipient,
        uint256 amount
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(recipient, amount));
        return _verify(proof, _merkleRoot, leaf);
    }

    // Internal: Merkle proof verification (standard algorithm)
    function _verify(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        
        return computedHash == root;
    }
}
