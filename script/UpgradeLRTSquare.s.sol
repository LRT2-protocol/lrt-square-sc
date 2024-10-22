// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquared, Governable} from "../src/LRTSquared.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Utils} from "./Utils.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract UpgradeLRTSquared is Utils {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        string memory deployments = readDeploymentFile();
        address lrtSquared = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "lrtSquaredProxy")
        );

        address newImpl = address(new LRTSquared());

        UUPSUpgradeable(lrtSquared).upgradeToAndCall(newImpl, "");

        vm.stopBroadcast();
    }
}
