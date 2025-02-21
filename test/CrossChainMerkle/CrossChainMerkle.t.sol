// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {CumulativeMerkleDrop} from "../../src/merkle-drop/CumulativeMerkleDrop.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Test} from "forge-std/Test.sol";

contract CrossChainMerkle is Test {
    address lrt2 = 0x8F08B70456eb22f6109F57b8fafE862ED28E6040;
    address lzEndpoint = 0x1a44076050125825900e736c501f859c50fE728c;
    address kingProtocolOwner = 0xA000244b4a36D57Ea1ECB39b5F02f255e4C8cd52;
    address cumulativeMerkle = 0x6Db24Ee656843E3fE03eb8762a54D86186bA6B64;

    address user = 0xFB505Aa37508B641CE4D8f066867Db3B3F66185D;

    CumulativeMerkleDrop cumulativeMerkleDrop;

    bytes32[] proof;

    function setUp() public {
        // create a fork at block 21896190
        vm.createSelectFork("https://eth-pokt.nodies.app", 21896190);
        cumulativeMerkleDrop = CumulativeMerkleDrop(payable(cumulativeMerkle));

        vm.startPrank(kingProtocolOwner);

        address cumulativeMerkleDropImpl = address(new CumulativeMerkleDrop(lrt2, lzEndpoint));

        CumulativeMerkleDrop(payable(cumulativeMerkle)).upgradeToAndCall(cumulativeMerkleDropImpl, "");

        cumulativeMerkleDrop.addChain(30184, 300_000, 300_000, toBytes32(cumulativeMerkle));

        vm.stopPrank();

        // Initialize proof array
        proof = new bytes32[](19);
        proof[0] = 0xc6d06a2b06ac1745bc57320f3ad3c26572848774a6109b7e12ca47906e9cb040;
        proof[1] = 0xf306078c23a4b457450e4b82730f8bc5f640ffec951a53c540421ba2d8242eeb;
        proof[2] = 0x46d275cf5f79cab92f374dcc95a51e0c09a13160b34b476da8a8516c58173485;
        proof[3] = 0x9d0980a5fc5a93311fc2e1a30a6f26893492d6ea59e4f448a8aa63bf04cddf59;
        proof[4] = 0xb3acfbf9bb69730e424a0554f64ee2c92af4f62c773323eb00a4b5fdde8d8b11;
        proof[5] = 0xd1590b98a940875552fbf3971ca2eb06074aa603ac9e62d8e43b78d546c0f204;
        proof[6] = 0xc0b9bd84bf2109d9224216927c1a78ab01d008dc975a812f541a594a99d0f8a5;
        proof[7] = 0x529b2904a8454406f9edca560bb696fed13da45217871054932de9ef8cbd9b77;
        proof[8] = 0xf3287b26906d49b33bbe4df11f7eb5949efd2b417bd8eb5e96ba53f01f2d7f24;
        proof[9] = 0x161e072814ce2b6b52abe568b670a8d29e03790ea0d550dd406919d63eb0b4dc;
        proof[10] = 0x46b1af59d8a58bc786c92c140ab9fa8b6f43fd94068fa4a6a551e4ea311d1b35;
        proof[11] = 0xe0ea80ae4f0ca3419614a34d471657e47428ade807046bf471ecdde5afac9e8f;
        proof[12] = 0x2376f0cd72ac97afbdfce877cb9b601d0bcf3fdcf63f3efe56400eb35f15ba28;
        proof[13] = 0xb912a7e51a6dbf0dfe6a405a1a18e137e10e2ca776f32f652809c4e14e865692;
        proof[14] = 0x01050afec693223ba29ea79104b302560bdff1f784497bb64a8ca258824b108f;
        proof[15] = 0x1703880ad551e70dd18c57b27b0da73d1d0f5e8b56c00e91de5d140840236a39;
        proof[16] = 0x053a2be67e9f4d1520e7706a7ccb335ca0569568bb2f0ff35f57fb7e2a30fb36;
        proof[17] = 0x4021b4ea34d7624d13c74451edafd9cddf83127fc9515084a0e4d1accf844e43;
        proof[18] = 0x6deded95694c7596062008d823b1a70053585c30cb144b7a35e4c132ea274633;
    }

    function test_defaultClaim() public {
        vm.startPrank(user);

        cumulativeMerkleDrop.claim(user, 46986201288251449522, 0x1871f7e6db1a66587ef1024b17102d75bfa72d8eb4dfe4d2249a3e19c8511827, proof);
    }

    function test_switchChain() public {
        vm.startPrank(user);

        MessagingFee memory msgFee = cumulativeMerkleDrop.quoteSetclaimEid(30184);

        cumulativeMerkleDrop.setclaimEid{value: msgFee.nativeFee}(30184, msgFee);

        vm.expectRevert(CumulativeMerkleDrop.InvalidChain.selector);
        cumulativeMerkleDrop.claim(user, 46986201288251449522, 0x1871f7e6db1a66587ef1024b17102d75bfa72d8eb4dfe4d2249a3e19c8511827, proof);

        vm.stopPrank();
    }

    function toBytes32(address addressValue) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addressValue)));
    }
}
