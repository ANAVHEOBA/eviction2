// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IAuthorizationModule} from "../interfaces/IAuthorizationModule.sol";

contract AuthorizationModule is IAuthorizationModule {
    
    // EIP-712 domain separator
    bytes32 private _domainSeparator;
    
    // Nonce tracking per signer
    mapping(address => uint256) private _nonces;
    
    // Approval tracking per proposalId
    mapping(bytes32 => bool) private _approvals;
    
    // Used nonces (for replay protection)
    mapping(address => mapping(uint256 => bool)) private _usedNonces;
    
    // Chain ID at deployment
    uint256 private immutable _CHAIN_ID;
    
    // EIP-712 type hash for TreasuryAction
    bytes32 private constant TREASURY_ACTION_TYPEHASH = 
        keccak256("TreasuryAction(bytes32 proposalId,address target,uint256 value,bytes data,uint256 nonce,uint256 chainId)");
    
    // EIP-712 domain type hash
    bytes32 private constant DOMAIN_TYPEHASH = 
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    constructor() {
        _CHAIN_ID = block.chainid;
        _domainSeparator = _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view returns (bytes32) {
        bytes32 nameHash = keccak256(bytes("ARES Treasury"));
        bytes32 versionHash = keccak256(bytes("1"));
        
        bytes32 result;
        bytes32 typeHash = DOMAIN_TYPEHASH;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, typeHash)
            mstore(add(ptr, 0x20), nameHash)
            mstore(add(ptr, 0x40), versionHash)
            mstore(add(ptr, 0x60), chainid())
            mstore(add(ptr, 0x80), address())
            result := keccak256(ptr, 0xa0)
        }
        
        return result;
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparator;
    }

    function verifySignature(
        TreasuryAction calldata action,
        address signer,
        bytes calldata signature
    ) external view returns (bool) {
        require(signer != address(0), "Invalid signer");
        require(signature.length == 65, "Invalid signature length");
        require(!_usedNonces[signer][action.nonce], "Nonce already used");
        
        // Reconstruct the message hash (EIP-712)
        bytes32 dataHash = keccak256(action.data);
        
        bytes32 actionHash;
        bytes32 typeHash = TREASURY_ACTION_TYPEHASH;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, typeHash)
            mstore(add(ptr, 0x20), calldataload(action))
            mstore(add(ptr, 0x40), calldataload(add(action, 0x20)))
            mstore(add(ptr, 0x60), calldataload(add(action, 0x40)))
            mstore(add(ptr, 0x80), dataHash)
            mstore(add(ptr, 0xa0), calldataload(add(action, 0x80)))
            mstore(add(ptr, 0xc0), calldataload(add(action, 0xa0)))
            actionHash := keccak256(ptr, 0xe0)
        }
        
        bytes32 digest;
        bytes32 domainSep = _domainSeparator;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, "\x19\x01")
            mstore(add(ptr, 0x02), domainSep)
            mstore(add(ptr, 0x22), actionHash)
            digest := keccak256(ptr, 0x42)
        }
        
        // Extract signature components
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        assembly {
            let ptr := signature.offset
            r := calldataload(ptr)
            s := calldataload(add(ptr, 0x20))
            v := byte(0, calldataload(add(ptr, 0x40)))
        }
        
        // Ensure valid v value
        if (v < 27) {
            v += 27;
        }
        require(v == 27 || v == 28, "Invalid signature v");
        
        // Recover signer and compare
        address recoveredSigner = ecrecover(digest, v, r, s);
        return recoveredSigner == signer;
    }

    function approveProposal(
        TreasuryAction calldata action,
        address[] calldata signers,
        bytes[] calldata signatures
    ) external {
        require(signers.length == signatures.length, "Signers and signatures length mismatch");
        require(signers.length > 0, "At least one signature required");
        
        // Verify all signatures
        for (uint256 i = 0; i < signers.length; i++) {
            require(this.verifySignature(action, signers[i], signatures[i]), "Invalid signature");
            // Mark nonce as used
            _usedNonces[signers[i]][action.nonce] = true;
            _nonces[signers[i]]++;
        }
        
        // Mark proposal as approved
        _approvals[action.proposalId] = true;
        emit ProposalApproved(action.proposalId, signers);
    }

    function isApproved(bytes32 proposalId) external view returns (bool) {
        return _approvals[proposalId];
    }

    function getNonce(address signer) external view returns (uint256) {
        return _nonces[signer];
    }

    function markNonceUsed(address signer, uint256 nonce) external {
        require(!_usedNonces[signer][nonce], "Nonce already marked");
        _usedNonces[signer][nonce] = true;
        emit NonceUsed(signer, nonce);
    }

    function revokeApproval(bytes32 proposalId) external {
        require(_approvals[proposalId], "Proposal not approved");
        _approvals[proposalId] = false;
        emit ApprovalRevoked(proposalId);
    }
}
