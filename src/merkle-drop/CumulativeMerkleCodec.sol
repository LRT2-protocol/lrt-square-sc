// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library CumulativeMerkleCodec {
    // TODO: take inspiration from the OFTComposeMsgCodec for ways to improve this
    uint8 constant TYPE_SINGLE = 1;
    uint8 constant TYPE_BATCH = 2;
    uint8 constant TYPE_MERKLE_ROOT = 3;
    
    struct claimMessage {
        address addr;
        uint256 amount;
    }
    
    struct BatchMessage {
        claimMessage[] messages;
    }
    
    /**
     * @dev Encodes a single message (address + uint256)
     * @param addr The address
     * @param amount The amount
     */
    function encodeSingle(address addr, uint256 amount) internal pure returns (bytes memory) {
        return abi.encode(TYPE_SINGLE, addr, amount);
    }
    
    /**
     * @dev Encodes a batch of messages (array of address + uint256 pairs)
     * @param addrs Array of addresses
     * @param amounts Array of amounts
     */
    function encodeBatch(address[] memory addrs, uint256[] memory amounts) internal pure returns (bytes memory) {
        require(addrs.length == amounts.length, "Length mismatch");
        return abi.encode(TYPE_BATCH, addrs, amounts);
    }

    /**
     * @dev Encodes a merkle root message (bytes32)
     * @param merkleRoot The merkle root
     */
    function encodeMerkleRoot(bytes32 merkleRoot) internal pure returns (bytes memory) {
        return abi.encode(TYPE_MERKLE_ROOT, merkleRoot);
    }
    
    /**
     * @dev Decodes a message based on its type
     * @param message The encoded message
     */
    function decodeType(bytes memory message) internal pure returns (uint8 messageType) {
        return abi.decode(message, (uint8));
    }

    /**
     * @dev Decodes a single message
     * @param message The encoded message
     */
    function decodeSingle(bytes memory message) internal pure returns (address addr, uint256 amount) {
        (,addr, amount) = abi.decode(message, (uint8, address, uint256));
    }

    /**
     * @dev Decodes a batch of messages
     * @param message The encoded message
     */ 
    function decodeBatch(bytes memory message) internal pure returns (address[] memory addrs, uint256[] memory amounts) {
        (,addrs, amounts) = abi.decode(message, (uint8, address[], uint256[]));
    }

    /**
     * @dev Decodes a merkle root message
     * @param message The encoded message
     */
    function decodeMerkleRoot(bytes memory message) internal pure returns (bytes32 merkleRoot) {
        (,merkleRoot) = abi.decode(message, (uint8, bytes32));
    }
}
