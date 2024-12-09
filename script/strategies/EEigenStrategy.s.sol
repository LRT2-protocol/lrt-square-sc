// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Utils} from "../Utils.sol";
import {EEigenStrategy} from "../../src/strategies/EEigenStrategy.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract DeployEEigenStrategy is Utils {
    EEigenStrategy strategy;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        string memory deployments = readDeploymentFile();
        address priceProvider = stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "priceProviderProxy")
        );

        vm.startBroadcast(deployerPrivateKey);

        strategy = new EEigenStrategy(priceProvider);

        vm.stopBroadcast();
    }    
}