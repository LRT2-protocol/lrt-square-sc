// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {CumulativeMerkleDrop} from "../src/merkle-drop/CumulativeMerkleDrop.sol";
import {UUPSProxy} from "../src/UUPSProxy.sol";
import {Utils, ChainConfig} from "./Utils.sol";

contract DeployCumulativeMerkleDrop is Utils {
    uint48 accessControlDelay = 120;
    address lrt2 = 0x8F08B70456eb22f6109F57b8fafE862ED28E6040;
    address lzEndpoint = address(1);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        ChainConfig memory config = getChainConfig(vm.toString(block.chainid));

        address cumulativeMerkleDropImpl = address(new CumulativeMerkleDrop(lrt2, lzEndpoint));
        CumulativeMerkleDrop cumulativeMerkleDrop = CumulativeMerkleDrop(address(
            new UUPSProxy(
                cumulativeMerkleDropImpl,
                abi.encodeWithSelector(
                    CumulativeMerkleDrop.initialize.selector,
                    accessControlDelay,
                    config.cumulativeDropOwner, 
                    config.cumulativeDropPauser
                )
            )
        ));

        vm.stopBroadcast();
    }
}
