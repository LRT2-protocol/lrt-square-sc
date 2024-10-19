// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquared, Governable} from "../src/LRTSquared.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract RebalanceLRTSquared is Utils {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        string memory deployments = readDeploymentFile();
        LRTSquared lrtSquared = LRTSquared(stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "lrtSquaredProxy")
        ));

        address swapper = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "swapper")
        );

        ChainConfig memory config = getChainConfig(vm.toString(block.chainid));
        bytes memory quote = getQuoteOneInch(
            vm.toString(block.chainid),
            swapper,
            address(lrtSquared),
            config.eigen,
            WETH,
            1e18
        );

        lrtSquared.rebalance(
            config.eigen,
            WETH,
            1e18,
            1,
            quote
        );

        vm.stopBroadcast();
    }
}
