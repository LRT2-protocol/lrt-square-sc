// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {CumulativeMerkleDrop} from "../src/merkle-drop/CumulativeMerkleDrop.sol";
import {UUPSProxy} from "../src/UUPSProxy.sol";
import {Utils, ChainConfig} from "./Utils.sol";

contract DeployNewMainnetCumulativeMerkleDrop is Utils {

    function run() public {

        vm.startBroadcast();

        ChainConfig memory config = getChainConfig(vm.toString(block.chainid));
        address cumulativeMerkleDropImpl = address(new CumulativeMerkleDrop(config.lrt2Token, config.lzEndpoint, config.oftAdapter));

        vm.stopBroadcast();
    }
}
