// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Governable} from "../src/governance/Governable.sol";
import {KINGCore} from "../src/KING/KINGCore.sol";
import {KINGAdmin} from "../src/KING/KINGAdmin.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Utils} from "./Utils.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract UpgradeKING is Utils {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        string memory deployments = readDeploymentFile();
        address king = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "kingProxy")
        );

        address kingCoreImpl = address(new KINGCore());
        address kingAdminImpl = address(new KINGAdmin());

        KINGCore(address(king)).upgradeToAndCall(kingCoreImpl, "");
        KINGCore(address(king)).setAdminImpl(kingAdminImpl);

        vm.stopBroadcast();
    }
}
