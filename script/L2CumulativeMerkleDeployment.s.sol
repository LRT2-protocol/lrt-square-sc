// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {CumulativeMerkleDrop} from "../src/merkle-drop/CumulativeMerkleDrop.sol";
import {UUPSProxy} from "../src/UUPSProxy.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {ICreate3Deployer} from "../interfaces/ICreate3Deployer.sol";

contract DeployCumulativeMerkleDrop is Utils {
    uint48 accessControlDelay = 120;

    ICreate3Deployer private CREATE3 = ICreate3Deployer(L2_CREATE3_DEPLOYER);

    function run() public {
        vm.startBroadcast();

        ChainConfig memory config = getChainConfig(vm.toString(block.chainid));

        bytes memory implCreationCode = abi.encodePacked(type(CumulativeMerkleDrop).creationCode, abi.encode(config.lrt2Token, config.lzEndpoint, config.oftAdapter));
        address cumulativeMerkleDropImpl = CREATE3.deployCreate3(keccak256("CumulativeMerkleDropImpl"), implCreationCode);

        bytes memory proxyCreationCode = abi.encodePacked(
            type(UUPSProxy).creationCode, 
            abi.encode(cumulativeMerkleDropImpl, 
            abi.encodeWithSelector(CumulativeMerkleDrop.initialize.selector, 
            accessControlDelay, 
            msg.sender, 
            msg.sender
            ))
        );
        address cumulativeMerkleDrop = CREATE3.deployCreate3(keccak256("CumulativeMerkleDrop"), proxyCreationCode);

        CumulativeMerkleDrop(payable(cumulativeMerkleDrop)).initializeLayerZero(200_000);

        vm.stopBroadcast();
    }
}
