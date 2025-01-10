// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LRTSquaredDummy} from "../src/LRTSquared/LRTSquaredDummy.sol"; 

contract DeployDummyImpl is Script {
    function run() external {
        vm.startBroadcast();

        LRTSquaredDummy dummyImpl = new LRTSquaredDummy();

        vm.stopBroadcast();

        console.log("LRTSquaredDummy deployed at:", address(dummyImpl));
    }
}
