// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquared} from "../src/LRTSquared.sol";
import {Utils} from "./Utils.sol";

contract DeployLRTSquaredImpl is Utils {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        LRTSquared newImpl = new LRTSquared();
        vm.stopBroadcast();
    }
}
