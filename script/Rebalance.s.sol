// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquare, Governable} from "../src/LRTSquare.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract RebalanceLRTSquare is Utils {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        string memory deployments = readDeploymentFile();
        LRTSquare lrtSquare = LRTSquare(stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "lrtSquareProxy")
        ));

        address swapper = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "swapper")
        );

        ChainConfig memory config = getChainConfig(vm.toString(block.chainid));
        bytes memory quote = getQuoteOneInch(
            vm.toString(block.chainid),
            swapper,
            address(lrtSquare),
            config.eigen,
            WETH,
            1e18
        );

        lrtSquare.rebalance(
            config.eigen,
            WETH,
            1e18,
            1,
            quote
        );

        vm.stopBroadcast();
    }
}
