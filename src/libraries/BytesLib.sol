// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title BytesLib
 * @dev Library for bytes manipulation utilities
 */
library BytesLib {
    
 
    function slice(
        bytes memory data,
        uint256 start,
        uint256 length
    ) internal pure returns (bytes memory) {
        require(start + length <= data.length, "Slice out of bounds");
        
        bytes memory result = new bytes(length);
        
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        
        return result;
    }

    function toBytes32(bytes memory data) internal pure returns (bytes32) {
        require(data.length >= 32, "Data too short");
        
        bytes32 result;
        assembly {
            result := mload(add(data, 0x20))
        }
        return result;
    }

  
    function concat(bytes memory a, bytes memory b) internal pure returns (bytes memory) {
        bytes memory result = new bytes(a.length + b.length);
        
        uint256 offset = 0;
        for (uint256 i = 0; i < a.length; i++) {
            result[offset] = a[i];
            offset++;
        }
        for (uint256 i = 0; i < b.length; i++) {
            result[offset] = b[i];
            offset++;
        }
        
        return result;
    }

 
    function startsWith(bytes memory data, bytes memory prefix) internal pure returns (bool) {
        if (data.length < prefix.length) return false;
        
        for (uint256 i = 0; i < prefix.length; i++) {
            if (data[i] != prefix[i]) return false;
        }
        
        return true;
    }

    function length(bytes memory data) internal pure returns (uint256) {
        return data.length;
    }
}
