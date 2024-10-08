// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Utils, ChainConfig} from "./Utils.sol";
import {Swapper1InchV6} from "../src/Swapper1InchV6.sol";
import {LRTSquare} from "../src/LRTSquare.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract UpgradeSwapper1InchV6 is Utils {
    Swapper1InchV6 swapper;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        string memory chainId = vm.toString(block.chainid);
        ChainConfig memory config = getChainConfig(chainId);

        swapper = new Swapper1InchV6(config.swapRouter1InchV6);

        string memory deployments = readDeploymentFile();
        address lrtSquare = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "lrtSquareProxy")
        );

        LRTSquare(lrtSquare).setSwapper(address(swapper));
        vm.stopBroadcast();
    }
}