// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {CumulativeMerkleDrop, ICumulativeMerkleDrop} from "../../src/merkle-drop/CumulativeMerkleDrop.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {MessagingFee, Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Test} from "forge-std/Test.sol";
import {CumulativeMerkleCodec} from "../../src/merkle-drop/CumulativeMerkleCodec.sol";
import {console} from "forge-std/console.sol";

contract CrossChainMerkle is Test {
    address lrt2 = 0x8F08B70456eb22f6109F57b8fafE862ED28E6040;
    address lzEndpoint = 0x1a44076050125825900e736c501f859c50fE728c;
    address oftAdapter = 0x4c8A4521F2431b0aC003829ac4e6dBC4Ed97707d;
    address kingProtocolOwner = 0xA000244b4a36D57Ea1ECB39b5F02f255e4C8cd52;
    address cumulativeMerkle = 0x6Db24Ee656843E3fE03eb8762a54D86186bA6B64;

    address user1 = 0xFB505Aa37508B641CE4D8f066867Db3B3F66185D;
    uint256 user1CumulativeAmount = 46986201288251449522;
    address user2 = 0xCB4269C7156C9C18a3ec88353C48000f79eD1359;
    uint256 user2CumulativeAmount = 25768231672529417;

    bytes32 currentMerkleRoot = 0x1871f7e6db1a66587ef1024b17102d75bfa72d8eb4dfe4d2249a3e19c8511827;
    uint256 currentBlock = 21896150;

    CumulativeMerkleDrop cumulativeMerkleDrop;

    bytes32[] proof1;
    bytes32[] proof2;

    function setUp() public {
        // create a fork at block 21896150
        vm.createSelectFork("https://eth-mainnet.public.blastapi.io", currentBlock);
        cumulativeMerkleDrop = CumulativeMerkleDrop(payable(cumulativeMerkle));

        vm.startPrank(kingProtocolOwner);

        address cumulativeMerkleDropImpl = address(new CumulativeMerkleDrop(lrt2, lzEndpoint, oftAdapter));

        CumulativeMerkleDrop(payable(cumulativeMerkle)).upgradeToAndCall(cumulativeMerkleDropImpl, "");

        cumulativeMerkleDrop.initializeLayerZero(100);

        cumulativeMerkleDrop.addChain(30335, 300_000, toBytes32(cumulativeMerkle));

        IMessageLibManager(lzEndpoint).setConfig(
            cumulativeMerkle, 
            0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1, // sendLib 
            getDVNConfig()
        );

        vm.stopPrank();

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
        cumulativeMerkleDrop.setClaimEid{value: msgFee.nativeFee}(30335, msgFee);

        vm.prank(kingProtocolOwner);
        cumulativeMerkleDrop.setUserChainSwitchingEnabled(true);

        vm.prank(user1);
        cumulativeMerkleDrop.setClaimEid{value: msgFee.nativeFee}(30335, msgFee);

        vm.expectRevert(CumulativeMerkleDrop.InvalidChain.selector);
        cumulativeMerkleDrop.claim(user1, user1CumulativeAmount, currentMerkleRoot, proof1);
    }

    function test_BatchSwitchChain() public {
        startHoax(kingProtocolOwner);
        address(cumulativeMerkleDrop).call{value: 1 ether}("");

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        cumulativeMerkleDrop.batchSetClaimEid(users, 30335);

        vm.expectRevert(CumulativeMerkleDrop.InvalidChain.selector);
        cumulativeMerkleDrop.claim(user1, user1CumulativeAmount, currentMerkleRoot, proof1);
        vm.expectRevert(CumulativeMerkleDrop.InvalidChain.selector);
        cumulativeMerkleDrop.claim(user2, user2CumulativeAmount, currentMerkleRoot, proof2);

        cumulativeMerkleDrop.setMaxBatchSize(1);

        vm.expectRevert(CumulativeMerkleDrop.MaxBatchSizeExceeded.selector);
        cumulativeMerkleDrop.batchSetClaimEid(users, 30335);
        vm.stopPrank();
    }

    function test_ReceiveChainSwitch() public {
        test_SwitchChain();

        bytes memory message = CumulativeMerkleCodec.encodeSingle(user1, cumulativeMerkleDrop.cumulativeClaimed(user1));
        vm.prank(lzEndpoint);
        Origin memory origin = Origin({srcEid: 30335, sender: toBytes32(cumulativeMerkle), nonce: 1});
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

        vm.prank(lzEndpoint);
        Origin memory origin = Origin({srcEid: 30335, sender: toBytes32(cumulativeMerkle), nonce: 1});
        cumulativeMerkleDrop.lzReceive(
            origin,
            bytes32(0x0),
            message,
            address(0),
            abi.encode(1)
        );

        test_DefaultClaim();
    }

    function test_PropagateMerkleRoot() public {
        startHoax(kingProtocolOwner);

        address(cumulativeMerkleDrop).call{value: 0.0000001 ether}("");
        vm.expectRevert(CumulativeMerkleDrop.InsufficientBalanceForMessageFee.selector);
        cumulativeMerkleDrop.propagateMerkleRoot();

        address(cumulativeMerkleDrop).call{value: 1 ether}("");
        cumulativeMerkleDrop.propagateMerkleRoot();

        vm.stopPrank();
        // random merkle root
        bytes32 newMerkleRoot = 0x7465737400000000000000000000000000000000000000000000000000000000;
        bytes memory message = CumulativeMerkleCodec.encodeMerkleRoot(newMerkleRoot);
        vm.prank(lzEndpoint);
        Origin memory origin = Origin({srcEid: 30335, sender: toBytes32(cumulativeMerkle), nonce: 1});
        cumulativeMerkleDrop.lzReceive(
            origin,
            bytes32(0x0),
            message,
            address(0),
            abi.encode(1)
        );

        assertEq(cumulativeMerkleDrop.merkleRoot(), newMerkleRoot);

        vm.expectRevert(ICumulativeMerkleDrop.MerkleRootWasUpdated.selector);
        cumulativeMerkleDrop.claim(user1, user1CumulativeAmount, currentMerkleRoot, proof1);

        // propagate merkle root to multiple peers
        vm.startPrank(kingProtocolOwner);
        cumulativeMerkleDrop.addChain(30184, 300_000, toBytes32(cumulativeMerkle));

        vm.expectEmit(true, true, true, true);
        emit CumulativeMerkleDrop.MerkleRootPropagated(30335, newMerkleRoot);
        vm.expectEmit(true, true, true, true);
        emit CumulativeMerkleDrop.MerkleRootPropagated(30184, newMerkleRoot);
        cumulativeMerkleDrop.propagateMerkleRoot();

        // test peer removal
        cumulativeMerkleDrop.removeChain(30184);

        vm.expectEmit(true, true, true, true);
        emit CumulativeMerkleDrop.MerkleRootPropagated(30335, newMerkleRoot);
        cumulativeMerkleDrop.propagateMerkleRoot();
    }

    function test_TopUpPeer() public {
        startHoax(kingProtocolOwner);
        address(cumulativeMerkleDrop).call{value: 1 ether}("");

        cumulativeMerkleDrop.topUpPeer(30335, 10 ether);
    }

    address swellLZEndpoint = 0xcb566e3B6934Fa77258d68ea18E931fa75e1aaAa;
    address swellKingToken = 0xc2606AADe4bdd978a4fa5a6edb3b66657acEe6F8;

    function test_L2Flow() public {
        vm.createSelectFork("https://swell-mainnet.alt.technology");

        startHoax(kingProtocolOwner);

        address swellCumulativeMerkleDropImpl = address(new CumulativeMerkleDrop(swellKingToken, swellLZEndpoint, oftAdapter));
        CumulativeMerkleDrop swellCumulativeMerkleDrop = CumulativeMerkleDrop(payable(address(
            new UUPSProxy(
                swellCumulativeMerkleDropImpl,
                abi.encodeWithSelector(
                    CumulativeMerkleDrop.initialize.selector,
                    120,
                    kingProtocolOwner, 
                    kingProtocolOwner
                )
            )
        )));
        swellCumulativeMerkleDrop.initializeLayerZero(100);
        swellCumulativeMerkleDrop.addChain(30101, 300_000, toBytes32(cumulativeMerkle));

        deal(swellKingToken, address(swellCumulativeMerkleDrop), 1000 ether);
        payable(swellCumulativeMerkleDrop).transfer(1 ether);

        bytes memory message = CumulativeMerkleCodec.encodeMerkleRoot(currentMerkleRoot);
        vm.startPrank(swellLZEndpoint);
        Origin memory origin = Origin({srcEid: 30101, sender: toBytes32(cumulativeMerkle), nonce: 1});
        swellCumulativeMerkleDrop.lzReceive(origin, bytes32(0x0), message,address(0), abi.encode(1));

        // claim chain should be defaulted to mainnet
        vm.expectRevert(CumulativeMerkleDrop.InvalidChain.selector);
        swellCumulativeMerkleDrop.claim(user1, user1CumulativeAmount, currentMerkleRoot, proof1);


        message = CumulativeMerkleCodec.encodeSingle(user1, 45536101163397729586);
        origin = Origin({srcEid: 30101, sender: toBytes32(cumulativeMerkle), nonce: 1});
        swellCumulativeMerkleDrop.lzReceive( origin, bytes32(0x0), message, address(0), abi.encode(1));

        swellCumulativeMerkleDrop.claim(user1, user1CumulativeAmount, currentMerkleRoot, proof1);

        startHoax(kingProtocolOwner);

        swellCumulativeMerkleDrop.topUpPeer(30101, 10 ether);
    }

    function toBytes32(address addressValue) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addressValue)));
    }

    // Set a base config
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
