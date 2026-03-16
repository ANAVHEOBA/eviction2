// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


library SignatureVerification {
    
    // EIP-712 type hash for domain separator
    bytes32 private constant DOMAIN_TYPEHASH = 
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    
    // EIP-712 type hash for TreasuryAction
    bytes32 private constant TREASURY_ACTION_TYPEHASH = 
        keccak256("TreasuryAction(bytes32 proposalId,address target,uint256 value,bytes data,uint256 nonce,uint256 chainId)");

   
    function computeDomainSeparator(
        string memory name,
        string memory version,
        uint256 chainId,
        address verifyingContract
    ) internal pure returns (bytes32) {
        bytes32 nameHash = keccak256(bytes(name));
        bytes32 versionHash = keccak256(bytes(version));
        
        bytes32 result;
        bytes32 typeHash = DOMAIN_TYPEHASH;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, typeHash)
            mstore(add(ptr, 0x20), nameHash)
            mstore(add(ptr, 0x40), versionHash)
            mstore(add(ptr, 0x60), chainId)
            mstore(add(ptr, 0x80), verifyingContract)
            result := keccak256(ptr, 0xa0)
        }
        
        return result;
    }

   
    function hashTreasuryAction(
        bytes32 proposalId,
        address target,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 chainId
    ) internal pure returns (bytes32) {
        bytes32 dataHash = keccak256(data);
        
        bytes32 result;
        bytes32 typeHash = TREASURY_ACTION_TYPEHASH;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, typeHash)
            mstore(add(ptr, 0x20), proposalId)
            mstore(add(ptr, 0x40), target)
            mstore(add(ptr, 0x60), value)
            mstore(add(ptr, 0x80), dataHash)
            mstore(add(ptr, 0xa0), nonce)
            mstore(add(ptr, 0xc0), chainId)
            result := keccak256(ptr, 0xe0)
        }
        
        return result;
    }

    function toDigest(
        bytes32 domainSeparator,
        bytes32 structHash
    ) internal pure returns (bytes32) {
        bytes32 result;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, "\x19\x01")
            mstore(add(ptr, 0x02), domainSeparator)
            mstore(add(ptr, 0x22), structHash)
            result := keccak256(ptr, 0x42)
        }
        return result;
    }

    function recover(
        bytes32 digest,
        bytes calldata signature
    ) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");
        
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }
        
        // Handle v value (can be 0/1 or 27/28)
        if (v < 27) {
            v += 27;
        }
        
        require(v == 27 || v == 28, "Invalid signature v");
        
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0), "Invalid signature");
        
        return recovered;
    }

    function isValidSignatureFormat(bytes calldata signature) internal pure returns (bool) {
        return signature.length == 65;
    }
}
