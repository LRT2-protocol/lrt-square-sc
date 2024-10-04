// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquare, Governable} from "../src/LRTSquare.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Utils} from "./Utils.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract UpgradeLRTSquare is Utils {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        string memory deployments = readDeploymentFile();
        address lrtSquare = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "lrtSquareProxy")
        );

        address newImpl = address(new LRTSquare());

        UUPSUpgradeable(lrtSquare).upgradeToAndCall(newImpl, "");

        vm.stopBroadcast();
    }
}
