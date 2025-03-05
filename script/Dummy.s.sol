// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {console} from "forge-std/console.sol";
import {LRTSquaredDummy} from "../src/LRTSquared/LRTSquaredDummy.sol";

contract DeployDummyImpl is Script, Utils {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        LRTSquaredDummy dummyImpl = new LRTSquaredDummy();

        console.log("LRTSquaredDummy deployed at:", address(dummyImpl));

        vm.stopBroadcast();
    }
}
