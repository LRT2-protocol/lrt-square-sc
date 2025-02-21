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
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
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
        uint128 singleMessageGasLimit;
        uint128 batchMessageGasLimit;
    }

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant CHAIN_UPDATER_ADMIN_ROLE = keccak256("CHAIN_UPDATER_ADMIN_ROLE");
    // solhint-disable-next-line immutable-vars-naming
    address public immutable override token;

    bytes32 public override merkleRoot;
    mapping(address => uint256) public cumulativeClaimed;

    /// @notice Maps user addresses to their designated claim chain eid
    /// @dev Default 0 value represent to mainnet
    mapping(address => uint32) public claimEid;
    /// @notice Maps chain id to chain info
    mapping(uint32 => ChainInfo) public chainInfo;

    error InvalidChain();

    event claimEidUpdated(address indexed account, uint32 newChain);
    event claimEidUpdatedBatched(uint32 newChain);

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
        if (block.chainid == 1) {
            if (claimEid[account] != 0) revert InvalidChain();
        } else {
            if (claimEid[account] != endpoint.eid()) revert InvalidChain();
        }

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

    function quoteSetclaimEid(uint32 dstEid) external view returns (MessagingFee memory msgFee) {
        bytes memory message = ClaimMessageCodec.encodeSingle(msg.sender, cumulativeClaimed[msg.sender]);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(chainInfo[dstEid].singleMessageGasLimit, 0);

        return _quote(dstEid, message, options, false);
    }

    function quoteBatchSetclaimEid(uint32 dstEid, address[] memory accounts, uint256[] memory amounts) external view returns (MessagingFee memory msgFee) {
        bytes memory message = ClaimMessageCodec.encodeBatch(accounts, amounts);
        uint128 dynamicGasLimit = (chainInfo[dstEid].batchMessageGasLimit * uint128(accounts.length)) + chainInfo[dstEid].singleMessageGasLimit;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(dynamicGasLimit, 0);

        return _quote(dstEid, message, options, false);
    }

    function setclaimEid(uint32 dstEid, MessagingFee memory msgFee) external payable {
        if (dstEid == endpoint.eid()) revert InvalidChain();

        claimEid[msg.sender] = dstEid;
        bytes memory message = ClaimMessageCodec.encodeSingle(msg.sender, cumulativeClaimed[msg.sender]);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(chainInfo[dstEid].singleMessageGasLimit, 0);

        _lzSend(dstEid, message, options, msgFee, msg.sender);

        emit claimEidUpdated(msg.sender, dstEid);
    }

    function batchSetclaimEid(address[] calldata accounts, uint32 dstEid, MessagingFee memory msgFee) external payable onlyRole(CHAIN_UPDATER_ADMIN_ROLE) {
        uint256[] memory amounts = new uint256[](accounts.length);

        for (uint256 i = 0; i < accounts.length; i++) {
            claimEid[accounts[i]] = dstEid;
            amounts[i] = cumulativeClaimed[accounts[i]];
        }

        bytes memory message = ClaimMessageCodec.encodeBatch(accounts, amounts);
        uint128 dynamicGasLimit = (chainInfo[dstEid].batchMessageGasLimit * uint128(accounts.length)) + chainInfo[dstEid].singleMessageGasLimit;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(dynamicGasLimit, 0);

        _lzSend(dstEid, message, options, msgFee, msg.sender);

        emit claimEidUpdatedBatched(dstEid);
    }

    function addChain(uint32 eid, uint128 singleMessageGasLimit, uint128 batchMessageGasLimit, bytes32 peer) external onlyRole(DEFAULT_ADMIN_ROLE) {

        setPeer(eid, peer);
        
        chainInfo[eid] = ChainInfo({
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

        uint32 newClaimEid = endpoint.eid();
        if(block.chainid == 1) {
            newClaimEid = 0;
        }

        if (messageType == ClaimMessageCodec.TYPE_SINGLE) {
            (address user, uint256 amount) = ClaimMessageCodec.decodeSingle(_message);
            
            claimEid[user] = newClaimEid;
            cumulativeClaimed[user] = amount;
        } else if (messageType == ClaimMessageCodec.TYPE_BATCH) {
            (address[] memory users, uint256[] memory amounts) = ClaimMessageCodec.decodeBatch(_message);

            for (uint256 i = 0; i < users.length; i++) {
                claimEid[users[i]] = newClaimEid;
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
