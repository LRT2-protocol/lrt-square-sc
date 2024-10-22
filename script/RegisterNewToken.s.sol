// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ILRTSquared} from "../src/interfaces/ILRTSquared.sol";
import {PriceProvider} from "../src/PriceProvider.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Utils} from "./Utils.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract RegisterNewToken is Utils {
    address token = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;
    PriceProvider.Config config = PriceProvider.Config({
        oracle: 0x19678515847d8DE85034dAD0390e09c3048d31cd,
        priceFunctionCalldata: hex"",
        isChainlinkType: true, 
        oraclePriceDecimals: 8,
        maxStaleness: 2 days,
        dataType: PriceProvider.ReturnType.Int256,
        isBaseTokenEth: false
    });
    
    PriceProvider priceProvider = PriceProvider(0x2B90103cdc9Bba6c0dBCAaF961F0B5b1920F19E3);
    ILRTSquared lrtSquared = ILRTSquared(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address[] memory tokens = new address[](1);
        tokens[0] = token;
        PriceProvider.Config[] memory configs = new PriceProvider.Config[](1);
        configs[0] = config;

        priceProvider.setTokenConfig(tokens, configs);
        lrtSquared.registerToken(token, HUNDRED_PERCENT_LIMIT);

        vm.stopBroadcast();
    }
}
