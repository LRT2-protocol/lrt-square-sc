// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {CumulativeMerkleDrop, ICumulativeMerkleDrop} from "../../src/merkle-drop/CumulativeMerkleDrop.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {MessagingFee, Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Test} from "forge-std/Test.sol";
import {CumulativeMerkleCodec} from "../../src/merkle-drop/CumulativeMerkleCodec.sol";
import "../../script/Utils.sol";
import "../../utils/GnosisHelpers.sol";
contract CrossChainMerkle is Test, Utils, GnosisHelpers {

    address user1 = 0x056590F16D5b314a132BbCFb1283fEc5D5C6E670;
    uint256 user1CumulativeAmount = 3797650514112974628;
    address user2 = 0xbCfdB384881C8429D7F7Ab53d6c63366Ea2F5b7C;
    uint256 user2CumulativeAmount = 3216935016743284;

    bytes32 currentMerkleRoot = 0x5a923cef80009ecf1ce45f9a68449481f0240c14a7926f9b57da70b5dbcd9f7f;
    uint256 currentBlock = 22117242;

    CumulativeMerkleDrop cumulativeMerkleDrop;

    bytes32[] proof1;
    bytes32[] proof2;

    ChainConfig mainnetConfig;
    ChainConfig swellConfig;
    function setUp() public {
        mainnetConfig = getChainConfig("1");
        swellConfig = getChainConfig("1923");

        vm.createSelectFork("https://eth-mainnet.public.blastapi.io", currentBlock);

        executeGnosisTransactionBundle("./output/MainnetMerkleUpgradeTransactions.json", mainnetConfig.owner);

        cumulativeMerkleDrop = CumulativeMerkleDrop(payable(mainnetConfig.cumulativeMerkleDrop));

        vm.prank(OPERATING_ADMIN_ADDRESS);
        IMessageLibManager(mainnetConfig.lzEndpoint).setConfig(
            mainnetConfig.cumulativeMerkleDrop, 
            mainnetConfig.sendLib, // sendLib 
            getDVNConfig()
        );

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/test/CrossChainMerkle/TestMerkleData.json");
        string memory json = vm.readFile(path);
        bytes memory proofData = vm.parseJson(json, ".Proof1");
        proof1 = abi.decode(proofData, (bytes32[]));

        bytes memory proofData2 = vm.parseJson(json, ".Proof2");
        proof2 = abi.decode(proofData2, (bytes32[]));

    }

    function test_DefaultClaim() public {
        cumulativeMerkleDrop.claim(user1, user1CumulativeAmount, currentMerkleRoot, proof1);
        cumulativeMerkleDrop.claim(user2, user2CumulativeAmount, currentMerkleRoot, proof2);
    }
    
    function test_SwitchChain() public {
        MessagingFee memory msgFee = cumulativeMerkleDrop.quoteSetClaimEid(30335);
        
        vm.expectRevert(CumulativeMerkleDrop.UserChainSwitchingDisabled.selector);
        vm.prank(user1);
        cumulativeMerkleDrop.updateClaimEid{value: msgFee.nativeFee}(30335, msgFee);

        vm.prank(mainnetConfig.owner);
        cumulativeMerkleDrop.setUserChainSwitchingEnabled(true);

        vm.prank(user1);
        cumulativeMerkleDrop.updateClaimEid{value: msgFee.nativeFee}(30335, msgFee);

        vm.expectRevert(CumulativeMerkleDrop.InvalidChain.selector);
        cumulativeMerkleDrop.claim(user1, user1CumulativeAmount, currentMerkleRoot, proof1);
    }

    function test_BatchSwitchChain() public {
        startHoax(OPERATING_ADMIN_ADDRESS);
        address(cumulativeMerkleDrop).call{value: 1 ether}("");

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        cumulativeMerkleDrop.batchUpdateClaimEid(users, 30335);

        vm.expectRevert(CumulativeMerkleDrop.InvalidChain.selector);
        cumulativeMerkleDrop.claim(user1, user1CumulativeAmount, currentMerkleRoot, proof1);
        vm.expectRevert(CumulativeMerkleDrop.InvalidChain.selector);
        cumulativeMerkleDrop.claim(user2, user2CumulativeAmount, currentMerkleRoot, proof2);

        vm.stopPrank();
    }

    function test_SweepETH() public {
        test_BatchSwitchChain();

        address receiver = address(vm.addr(1));
        uint256 balanceBefore = address(receiver).balance;
        vm.prank(OPERATING_ADMIN_ADDRESS);
        cumulativeMerkleDrop.sweepETH(payable(receiver), 0.9 ether);

        assertEq(receiver.balance, balanceBefore + 0.9 ether);
    }

    function test_ReceiveChainSwitch() public {
        test_SwitchChain();

        bytes memory message = CumulativeMerkleCodec.encodeSingle(user1, cumulativeMerkleDrop.cumulativeClaimed(user1));
        vm.prank(mainnetConfig.lzEndpoint);
        Origin memory origin = Origin({srcEid: 30335, sender: toBytes32(swellConfig.cumulativeMerkleDrop), nonce: 1});
        cumulativeMerkleDrop.lzReceive( origin, bytes32(0x0), message, address(0), abi.encode(1));

        test_DefaultClaim();
    }

    function test_ReceiveChainSwitchBatch() public {
        test_BatchSwitchChain();

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = cumulativeMerkleDrop.cumulativeClaimed(user1);
        amounts[1] = cumulativeMerkleDrop.cumulativeClaimed(user2);

        bytes memory message = CumulativeMerkleCodec.encodeBatch(users, amounts);

        vm.prank(mainnetConfig.lzEndpoint);
        Origin memory origin = Origin({srcEid: 30335, sender: toBytes32(swellConfig.cumulativeMerkleDrop), nonce: 1});
        cumulativeMerkleDrop.lzReceive(
            origin,
            bytes32(0x0),
            message,
            address(0),
            abi.encode(1)
        );

        test_DefaultClaim();
    }

    function test_BroadcastMerkleRoot() public {
        startHoax(mainnetConfig.owner);

        // random merkle root
        bytes32 newMerkleRoot = 0x7465737400000000000000000000000000000000000000000000000000000000;

        address(cumulativeMerkleDrop).call{value: 0.0000001 ether}("");
        vm.expectRevert(CumulativeMerkleDrop.InsufficientBalanceForMessageFee.selector);
        cumulativeMerkleDrop.setAndBroadcastMerkleRoot(newMerkleRoot);

        address(cumulativeMerkleDrop).call{value: 1 ether}("");
        cumulativeMerkleDrop.setAndBroadcastMerkleRoot(newMerkleRoot);

        vm.stopPrank();

        bytes memory message = CumulativeMerkleCodec.encodeMerkleRoot(newMerkleRoot);
        vm.prank(mainnetConfig.lzEndpoint);
        Origin memory origin = Origin({srcEid: 30335, sender: toBytes32(swellConfig.cumulativeMerkleDrop), nonce: 1});
        cumulativeMerkleDrop.lzReceive( origin, bytes32(0x0), message, address(0), abi.encode(1));

        assertEq(cumulativeMerkleDrop.merkleRoot(), newMerkleRoot);

        vm.expectRevert(ICumulativeMerkleDrop.MerkleRootWasUpdated.selector);
        cumulativeMerkleDrop.claim(user1, user1CumulativeAmount, currentMerkleRoot, proof1);

        // broadcast merkle root to multiple peers
        vm.startPrank(mainnetConfig.owner);
        cumulativeMerkleDrop.addChain(30184, 300_000, toBytes32(swellConfig.cumulativeMerkleDrop));

        vm.expectEmit(true, true, true, true);
        emit CumulativeMerkleDrop.MerkleRootBroadcasted(30335, newMerkleRoot);
        vm.expectEmit(true, true, true, true);
        emit CumulativeMerkleDrop.MerkleRootBroadcasted(30184, newMerkleRoot);
        cumulativeMerkleDrop.setAndBroadcastMerkleRoot(newMerkleRoot);

        // test peer removal
        cumulativeMerkleDrop.removeChain(30184);

        vm.expectEmit(true, true, true, true);
        emit CumulativeMerkleDrop.MerkleRootBroadcasted(30335, newMerkleRoot);
        cumulativeMerkleDrop.setAndBroadcastMerkleRoot(newMerkleRoot);
    }

    function test_TopUpPeer() public {
        startHoax(OPERATING_ADMIN_ADDRESS);
        address(cumulativeMerkleDrop).call{value: 1 ether}("");

        cumulativeMerkleDrop.topUpPeer(30335, 10 ether);
    }


    function test_L2Flow() public {
        vm.createSelectFork("https://swell-mainnet.alt.technology");

        startHoax(swellConfig.owner);

        // test against the deployed contract
        CumulativeMerkleDrop swellCumulativeMerkleDrop = CumulativeMerkleDrop(payable(swellConfig.cumulativeMerkleDrop));

        deal(swellConfig.lrt2Token, address(swellCumulativeMerkleDrop), 1000 ether);
        address(swellCumulativeMerkleDrop).call{value: 1 ether}("");

        bytes memory message = CumulativeMerkleCodec.encodeMerkleRoot(currentMerkleRoot);
        vm.startPrank(swellConfig.lzEndpoint);
        Origin memory origin = Origin({srcEid: 30101, sender: toBytes32(mainnetConfig.cumulativeMerkleDrop), nonce: 1});
        swellCumulativeMerkleDrop.lzReceive(origin, bytes32(0x0), message,address(0), abi.encode(1));

        // claim chain should be defaulted to mainnet
        vm.expectRevert(CumulativeMerkleDrop.InvalidChain.selector);
        swellCumulativeMerkleDrop.claim(user1, user1CumulativeAmount, currentMerkleRoot, proof1);

        message = CumulativeMerkleCodec.encodeSingle(user1, 2797650514112974628);
        origin = Origin({srcEid: 30101, sender: toBytes32(mainnetConfig.cumulativeMerkleDrop), nonce: 1});
        swellCumulativeMerkleDrop.lzReceive( origin, bytes32(0x0), message, address(0), abi.encode(1));

        swellCumulativeMerkleDrop.claim(user1, user1CumulativeAmount, currentMerkleRoot, proof1);

        startHoax(OPERATING_ADMIN_ADDRESS);

        swellCumulativeMerkleDrop.topUpPeer(30101, 10 ether);

        swellCumulativeMerkleDrop.setAndBroadcastMerkleRoot(currentMerkleRoot);
    }

    // Set a base mainnetConfig
    function getDVNConfig() internal pure returns (SetConfigParam[] memory) {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b; // LZ DVN

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 15,
            requiredDVNCount: 1,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(30335, 2, abi.encode(ulnConfig));

        return params;
    }
}
