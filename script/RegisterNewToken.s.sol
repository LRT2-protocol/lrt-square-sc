// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquare, Governable} from "../src/LRTSquare.sol";
import {PriceProvider} from "../src/PriceProvider.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Utils} from "./Utils.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract RegisterNewToken is Utils {
    address token = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    PriceProvider.Config config = PriceProvider.Config({
        oracle: 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6,
        priceFunctionCalldata: hex"",
        isChainlinkType: true, 
        oraclePriceDecimals: 8,
        maxStaleness: 10 days,
        dataType: PriceProvider.ReturnType.Int256,
        isBaseTokenEth: false
    });
    
    PriceProvider priceProvider;
    LRTSquare lrtSquare;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address[] memory tokens = new address[](1);
        tokens[0] = token;
        PriceProvider.Config[] memory configs = new PriceProvider.Config[](1);
        configs[0] = config;

        string memory deployments = readDeploymentFile();
        lrtSquare = LRTSquare(stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "lrtSquareProxy")
        ));

        priceProvider = PriceProvider(stdJson.readAddress(
            deployments,
            string.concat(".", "addresses", ".", "priceProviderProxy")
        ));

        priceProvider.setTokenConfig(tokens, configs);
        lrtSquare.registerToken(token, HUNDRED_PERCENT_LIMIT);

        vm.stopBroadcast();
    }
}
