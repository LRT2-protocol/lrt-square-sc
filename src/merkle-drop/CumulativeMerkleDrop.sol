// SPDX-License-Identifier: MIT

// MIT License

// © 2021, 1inch. All rights reserved.

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

pragma solidity ^0.8.24;

import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICumulativeMerkleDrop } from "../interfaces/ICumulativeMerkleDrop.sol";
import {ReentrancyGuardTransient} from "../utils/ReentrancyGuardTransient.sol";
import {OAppUpgradeable, Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/OAppUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {ClaimMessageCodec} from "./ClaimMessageCodec.sol";
// Taken from https://github.com/1inch/merkle-distribution/blob/master/contracts/CumulativeMerkleDrop.sol
contract CumulativeMerkleDrop is  
    ICumulativeMerkleDrop, 
    Initializable,
    UUPSUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardTransient,
    OAppUpgradeable
{
    using SafeERC20 for IERC20;
    using OptionsBuilder for bytes;
    // using MerkleProof for bytes32[];

    struct ChainInfo {
        uint16 chainEid;
        uint128 singleMessageGasLimit;
        uint128 batchMessageGasLimit;
    }

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant CHAIN_UPDATER_ADMIN_ROLE = keccak256("CHAIN_UPDATER_ADMIN_ROLE");
    // solhint-disable-next-line immutable-vars-naming
    address public immutable override token;

    bytes32 public override merkleRoot;
    mapping(address => uint256) public cumulativeClaimed;

    /// @notice Maps user addresses to their claim chain (default 0 represents mainnet)
    mapping(address => uint16) public claimChain;

    mapping(uint16 => ChainInfo) public chainInfo;

    error InvalidChain();

    event ClaimChainUpdated(address indexed account, uint16 newChain);
    event ClaimChainUpdatedBatched(uint16 newChain);

    constructor(address _token, address _endpoint) OAppUpgradeable(_endpoint) {
        token = _token;
        _disableInitializers();
    }

    function initialize(uint48 _accessControlDelay, address _owner, address _pauser) external initializer {
        __AccessControlDefaultAdminRules_init_unchained(_accessControlDelay, _owner);
        _grantRole(PAUSER_ROLE, _pauser);
    }

    function setMerkleRoot(bytes32 merkleRoot_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit MerkelRootUpdated(merkleRoot, merkleRoot_);
        merkleRoot = merkleRoot_;
    }

    function claim(
        address account,
        uint256 cumulativeAmount,
        bytes32 expectedMerkleRoot,
        bytes32[] calldata merkleProof
    ) external whenNotPaused nonReentrant {
        if (merkleRoot != expectedMerkleRoot) revert MerkleRootWasUpdated();

        // Verify the claim chain
        if (claimChain[account] != getChainId()) revert InvalidChain();

        // Verify the merkle proof
        if (!verify(account, cumulativeAmount, expectedMerkleRoot, merkleProof)) revert InvalidProof();

        // Mark it claimed
        uint256 preclaimed = cumulativeClaimed[account];
        if (preclaimed >= cumulativeAmount) revert NothingToClaim();
        cumulativeClaimed[account] = cumulativeAmount;

        // Send the token
        unchecked {
            uint256 amount = cumulativeAmount - preclaimed;
            IERC20(token).safeTransfer(account, amount);
            emit Claimed(account, amount);
        }
    }

    function setClaimChain(uint16 newChain) external payable {
        if (newChain == getChainId()) revert InvalidChain();

        claimChain[msg.sender] = newChain;

        ChainInfo memory info = chainInfo[newChain];

        uint256 userAmountClaimed = cumulativeClaimed[msg.sender];

        bytes memory message = ClaimMessageCodec.encodeSingle(msg.sender, userAmountClaimed);

        _lzSend(
            info.chainEid, 
            message, 
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(info.singleMessageGasLimit, 0),
            msg.sender, 
            bytes("")
        );

        emit ClaimChainUpdated(msg.sender, newChain);
    }

    function batchSetClaimChain(address[] calldata accounts, uint16 newChain) external payable onlyRole(CHAIN_UPDATER_ADMIN_ROLE) {
        uint256[] memory amounts = new uint256[](accounts.length);

        for (uint256 i = 0; i < accounts.length; i++) {
            claimChain[accounts[i]] = newChain;
            amounts[i] = cumulativeClaimed[accounts[i]];
        }

        bytes memory message = ClaimMessageCodec.encodeBatch(accounts, amounts);

        ChainInfo memory info = chainInfo[newChain];

        uint128 dynamicGasLimit = (info.batchMessageGasLimit * uint128(accounts.length)) + info.singleMessageGasLimit;

        _lzSend(
            info.chainEid, 
            message, 
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(dynamicGasLimit, 0),
            msg.sender,
            bytes("")
        );

        emit ClaimChainUpdatedBatched(newChain);
    }

    function setChainToEid(uint16 chain, uint16 eid, uint128 singleMessageGasLimit, uint128 batchMessageGasLimit) external onlyRole(CHAIN_UPDATER_ADMIN_ROLE) {
        chainInfo[chain] = ChainInfo({
            chainEid: eid,
            singleMessageGasLimit: singleMessageGasLimit,
            batchMessageGasLimit: batchMessageGasLimit
        });
    }

    function verify(
        address account, 
        uint256 cumulativeAmount, 
        bytes32 expectedMerkleRoot, 
        bytes32[] calldata merkleProof
    ) public pure returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(account, cumulativeAmount));
        return _verifyAsm(merkleProof, expectedMerkleRoot, leaf);
    }

    function getChainId() public view returns (uint16) {
        uint16 currentChain = uint16(block.chainid);
        if (currentChain == 1) {
            return 0;
        } 
        return currentChain;
    }

    function pause() external whenNotPaused onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external whenPaused onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        uint8 messageType = ClaimMessageCodec.decodeType(_message);

        if (messageType == ClaimMessageCodec.TYPE_SINGLE) {
            (address user, uint256 amount) = ClaimMessageCodec.decodeSingle(_message);
            
            claimChain[user] = getChainId();
            cumulativeClaimed[user] = amount;
        } else if (messageType == ClaimMessageCodec.TYPE_BATCH) {
            (address[] memory users, uint256[] memory amounts) = ClaimMessageCodec.decodeBatch(_message);
            for (uint256 i = 0; i < users.length; i++) {
                claimChain[users[i]] = getChainId();
                cumulativeClaimed[users[i]] = amounts[i];
            }
        }
    }

    function _verifyAsm(bytes32[] calldata proof, bytes32 root, bytes32 leaf) private pure returns (bool valid) {
        /// @solidity memory-safe-assembly
        assembly {  // solhint-disable-line no-inline-assembly
            let ptr := proof.offset

            for { let end := add(ptr, mul(0x20, proof.length)) } lt(ptr, end) { ptr := add(ptr, 0x20) } {
                let node := calldataload(ptr)

                switch lt(leaf, node)
                case 1 {
                    mstore(0x00, leaf)
                    mstore(0x20, node)
                }
                default {
                    mstore(0x00, node)
                    mstore(0x20, leaf)
                }

                leaf := keccak256(0x00, 0x40)
            }

            valid := eq(root, leaf)
        }
    }

    /**
     * @dev using the `AccessControlDefaultAdminRulesUpgradeable` owner() implementation
     */
    function owner() public view override(AccessControlDefaultAdminRulesUpgradeable, OwnableUpgradeable) returns (address) {
        return defaultAdmin();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
