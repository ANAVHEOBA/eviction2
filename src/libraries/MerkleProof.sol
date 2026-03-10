// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


library MerkleProof {
    

    function verify(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        return processProof(proof, leaf) == root;
    }

    function processProof(
        bytes32[] calldata proof,
        bytes32 leaf
    ) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            computedHash = _hashPair(computedHash, proofElement);
        }
        
        return computedHash;
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        bytes32 result;
        if (a <= b) {
            assembly {
                mstore(0x00, a)
                mstore(0x20, b)
                result := keccak256(0x00, 0x40)
            }
        } else {
            assembly {
                mstore(0x00, b)
                mstore(0x20, a)
                result := keccak256(0x00, 0x40)
            }
        }
        return result;
    }

    function getLeaf(address recipient, uint256 amount) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(recipient, amount));
    }
}
