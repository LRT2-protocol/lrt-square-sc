// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Governable} from "../src/governance/Governable.sol";
import {LRTSquaredCore} from "../src/LRTSquared/LRTSquaredCore.sol";
import {LRTSquaredAdmin} from "../src/LRTSquared/LRTSquaredAdmin.sol";
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

        address lrtSquaredCoreImpl = address(new LRTSquaredCore());
        address lrtSquaredAdminImpl = address(new LRTSquaredAdmin());

        LRTSquaredCore(address(lrtSquared)).upgradeToAndCall(lrtSquaredCoreImpl, "");
        LRTSquaredCore(address(lrtSquared)).setAdminImpl(lrtSquaredAdminImpl);

        vm.stopBroadcast();
    }
}
