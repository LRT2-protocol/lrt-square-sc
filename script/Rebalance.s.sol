// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IKING} from "../src/interfaces/IKING.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract RebalanceKING is Utils {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        string memory deployments = readDeploymentFile();
        IKING king = IKING(stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "kingProxy")
        ));

        address swapper = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "swapper")
        );

        ChainConfig memory config = getChainConfig(vm.toString(block.chainid));
        bytes memory quote = getQuoteOneInch(
            vm.toString(block.chainid),
            swapper,
            address(king),
            config.eigen,
            WETH,
            1e18
        );

        king.rebalance(
            config.eigen,
            WETH,
            1e18,
            1,
            quote
        );

        vm.stopBroadcast();
    }
}
