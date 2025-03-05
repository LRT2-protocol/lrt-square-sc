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
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICumulativeMerkleDrop} from "../interfaces/ICumulativeMerkleDrop.sol";
import {ReentrancyGuardTransient} from "../utils/ReentrancyGuardTransient.sol";
import {OAppUpgradeable, Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/OAppUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {MessagingFee, MessagingParams} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IOFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {CumulativeMerkleCodec} from "./CumulativeMerkleCodec.sol";
import {SendParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

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
    using EnumerableMap for EnumerableMap.UintToUintMap;
    // using MerkleProof for bytes32[];

    struct ChainInfo {
        uint128 singleMessageGasLimit;
    }

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // solhint-disable-next-line immutable-vars-naming
    address public immutable override token;

    bytes32 public override merkleRoot;
    mapping(address => uint256) public cumulativeClaimed;

    /// @notice Maps user addresses to their designated claim chain eid
    /// @dev We use the default 0 value to represent the mainnet eid
    /// @dev should only be accessed through the custom getter and setter
    mapping(address => uint32) private claimEid;

    /// @notice Enumerable map of peer chain eids to the gas limit required to execute a single message `TYPE_SINGLE` or `TYPE_MERKLE_ROOT`
    /// @dev Utilized to iterate over all the peers to propagate messages to the entire mesh network
    EnumerableMap.UintToUintMap private peerToGasLimit;

    address public immutable oftAdapter;
    
    uint256 public maxBatchSize;

    /// @dev Enable users ability to switch their claim chain
    bool public isUserChainSwitchingEnabled;

    error InvalidChain();
    /// @dev This contract is designed to pay the cross chain message fee. Contract needs to be funded if this error is thrown
    error InsufficientBalanceForMessageFee();
    /// @dev Enforce a max batch size to prevent messages from being sent that are too large to be executed on the destination chain
    error MaxBatchSizeExceeded();
    error UserChainSwitchingDisabled();

    event ClaimEidUpdated(address indexed account, uint32 newChain);
    event ClaimEidUpdatedBatched(uint32 newChain);
    event MerkleRootPropagated(uint32 newChain, bytes32 newMerkleRoot);
    
    constructor(address _token, address _endpoint, address _oftAdapter) OAppUpgradeable(_endpoint) {
        token = _token;
        oftAdapter = _oftAdapter;
        _disableInitializers();
    }

    function initialize(
        uint48 _accessControlDelay,
        address _owner,
        address _pauser
    ) external initializer {
        __AccessControlDefaultAdminRules_init_unchained(_accessControlDelay, _owner);
        _grantRole(PAUSER_ROLE, _pauser);
    }

    function initializeLayerZero(uint256 _maxBatchSize) external reinitializer(2) {
        __OAppCore_init_unchained(owner());
        maxBatchSize = _maxBatchSize;
    }

    function setMerkleRoot(bytes32 merkleRoot_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit MerkleRootUpdated(merkleRoot, merkleRoot_);
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
        if (endpoint.eid() != getClaimEid(account)) revert InvalidChain();

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
     *  @notice Adds a new chain to the mesh network. Can also be used to update the peer address or the gas limit for an existing peer
     */
    function addChain(uint32 eid, uint128 singleMessageGasLimit, bytes32 peer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        setPeer(eid, peer);
        peerToGasLimit.set(uint256(eid), uint256(singleMessageGasLimit));
    }

    /**
     * @notice Removes a chain from the mesh network
     */
    function removeChain(uint32 eid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        setPeer(eid, bytes32(0));
        peerToGasLimit.remove(uint256(eid));
    }

    /**
     * @notice Quotes the LayerZero fee the user will pay to send the LZ message to change their claim chain
     */
    function quoteSetClaimEid(uint32 dstEid) external view returns (MessagingFee memory msgFee) {

        return _quote(dstEid, CumulativeMerkleCodec.encodeSingle(address(0), 0), getExecutorReceiveOptions(dstEid), false);
    }

    /**
     * @notice Quotes the LayerZero fee this contract will pay to send the merkle root to a specific peer
     */
    function quotePropagateMerkleRoot(uint32 dstEid) public view returns (MessagingFee memory msgFee) {

        return _quote(dstEid, CumulativeMerkleCodec.encodeMerkleRoot(merkleRoot), getExecutorReceiveOptions(dstEid), false);
    }

    /**
     * @notice Quotes the LayerZero fee this contract will pay to send the LZ message to change the claim chain of multiple users
     * @dev Doesn't estimate the gas necessary to execute the `lzReceive` function on the destination chain
     * Once the message is delivered, the payload will need be manually executed on the destination chain
     */
    function quoteBatchSetClaimEid(uint32 dstEid, uint256 numAccounts) public view returns (MessagingFee memory msgFee) {    
        bytes memory message = CumulativeMerkleCodec.encodeBatch(new address[](numAccounts), new uint256[](numAccounts));

        return _quote(dstEid, message, getExecutorReceiveOptions(dstEid), false);
    }
    
    /**
     * @notice User function to change their claim chain
     */
    function setClaimEid(uint32 dstEid, MessagingFee memory msgFee) external payable {
        if (!isUserChainSwitchingEnabled) revert UserChainSwitchingDisabled();
        if (dstEid == endpoint.eid()) revert InvalidChain();

        // messages to change the claim chain can only be sent from the current claim chain
        if (endpoint.eid() != getClaimEid(msg.sender)) revert InvalidChain();

        setClaimEid(msg.sender, dstEid);
        bytes memory message = CumulativeMerkleCodec.encodeSingle(msg.sender, cumulativeClaimed[msg.sender]);

        _lzSend(dstEid, message, getExecutorReceiveOptions(dstEid), msgFee, msg.sender);

        emit ClaimEidUpdated(msg.sender, dstEid);
    }

    /**
     * @notice Changes the claim chain on behalf of multiple users
     * @dev Due to the complexity of estimating the gas required for this dynamic batch operation, the gas is not provided on the source chain
     * Once the message is delivered, the payload will need be manually executed on the destination chain
     */
    function batchSetClaimEid(address[] calldata accounts, uint32 dstEid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (accounts.length > maxBatchSize) revert MaxBatchSizeExceeded();

        MessagingFee memory msgFee = quoteBatchSetClaimEid(dstEid, accounts.length);
        if (address(this).balance < msgFee.nativeFee) revert InsufficientBalanceForMessageFee();

        uint256[] memory amounts = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            // messages to change the claim chain can only be sent from the current claim chain
            if (endpoint.eid() != getClaimEid(accounts[i])) revert InvalidChain();

            setClaimEid(accounts[i], dstEid);
            amounts[i] = cumulativeClaimed[accounts[i]];
        }

        bytes memory message = CumulativeMerkleCodec.encodeBatch(accounts, amounts);

        _lzSendFromContract(dstEid, message, getExecutorReceiveOptions(dstEid), msgFee);

        emit ClaimEidUpdatedBatched(dstEid);
    }

    /**
     * @notice Propagates the current merkle root to all the peers
     */
    function propagateMerkleRoot() external onlyRole(DEFAULT_ADMIN_ROLE) {

        bytes memory message = CumulativeMerkleCodec.encodeMerkleRoot(merkleRoot);
        
        // enumerate all the peers and propagate message
        uint256[] memory allPeers = peerToGasLimit.keys();
        for (uint256 i = 0; i < allPeers.length; i++) {
            uint32 dstEid = uint32(allPeers[i]);

            MessagingFee memory msgFee = quotePropagateMerkleRoot(dstEid);
            if (address(this).balance < msgFee.nativeFee) revert InsufficientBalanceForMessageFee();

            _lzSendFromContract(dstEid, message, getExecutorReceiveOptions(dstEid), msgFee);
            emit MerkleRootPropagated(dstEid, merkleRoot);
        }
    }

    /**
     * @notice Sends king tokens to the merkle drop contract on the destination chain
     */
    function topUpPeer(uint32 dstEid, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IOFT oft = IOFT(token);
        if (block.chainid == 1) { 
            oft = IOFT(oftAdapter); 
        }

        bytes32 peer = _getPeerOrRevert(dstEid);
        SendParam memory param = SendParam({
            dstEid: dstEid,
            to: peer,
            amountLD: amount,
            minAmountLD: (amount),
            extraOptions: getExecutorReceiveOptions(dstEid),
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory msgFee = oft.quoteSend(param, false);
        if (address(this).balance < msgFee.nativeFee) revert InsufficientBalanceForMessageFee();

        IERC20(token).approve(address(oft), amount);
        oft.send{value: msgFee.nativeFee}(param, msgFee, msg.sender);
    }

    /**
     * @dev The `_lzSend` requires the msg.sender to pay the fee
     * This function allows the contract to send a message without the msg.sender paying the fee
     */
    function _lzSendFromContract(
        uint32 dstEid,
        bytes memory message,
        bytes memory options,
        MessagingFee memory msgFee
    ) internal {
        endpoint.send{ value: msgFee.nativeFee }(
            MessagingParams(dstEid, _getPeerOrRevert(dstEid), message, options, msgFee.lzTokenFee > 0),
            msg.sender
        );
    }

    /**
     * @dev Implements the layerzero receive function to handle inbound messages from other chains
     */
    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        uint8 messageType = CumulativeMerkleCodec.decodeType(_message);

        uint32 newClaimEid = endpoint.eid();

        if (messageType == CumulativeMerkleCodec.TYPE_SINGLE) {
            (address user, uint256 amount) = CumulativeMerkleCodec.decodeSingle(_message);

            setClaimEid(user, newClaimEid);
            cumulativeClaimed[user] = amount;
        } else if (messageType == CumulativeMerkleCodec.TYPE_BATCH) {
            (address[] memory users, uint256[] memory amounts) = CumulativeMerkleCodec.decodeBatch(_message);

            for (uint256 i = 0; i < users.length; i++) {
                setClaimEid(users[i], newClaimEid);
                cumulativeClaimed[users[i]] = amounts[i];
            }
        } else if (messageType == CumulativeMerkleCodec.TYPE_MERKLE_ROOT) {
            bytes32 merkleRoot_ = CumulativeMerkleCodec.decodeMerkleRoot(_message);

            emit MerkleRootUpdated(merkleRoot, merkleRoot_);
            merkleRoot = merkleRoot_;
        } else {
            revert("Invalid message type");
        }
    }

    /**
     * @dev Custom getter and setter for the `claimEid` mapping where default 0 value represent the mainnet eid
     */
    function getClaimEid(address user) public view returns (uint32) {
        if (claimEid[user] == 0) {
            return 30101;
        } else {
            return claimEid[user];
        }
    }
    function setClaimEid(address user, uint32 eid) internal {
        if (eid == 30101) {
            claimEid[user] = 0;
        } else {
            claimEid[user] = eid;
        }
    }

    function setUserChainSwitchingEnabled(bool _isUserChainSwitchingEnabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isUserChainSwitchingEnabled = _isUserChainSwitchingEnabled;
    }

    function setMaxBatchSize(uint256 _maxBatchSize) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxBatchSize = _maxBatchSize;
    }

    /**
     * @dev Encodes the gas amount allocated for executing a single message on this destination chain into a LayerZero options bytes array
     */
    function getExecutorReceiveOptions(uint32 eid) public view returns (bytes memory options) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(uint128(peerToGasLimit.get(uint256(eid))), 0);
    }

    /**
     * @dev using the `AccessControlDefaultAdminRulesUpgradeable` owner() implementation
     */
    function owner() public view override(AccessControlDefaultAdminRulesUpgradeable, OwnableUpgradeable) returns (address) {
        return defaultAdmin();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    receive() external payable {}
}
