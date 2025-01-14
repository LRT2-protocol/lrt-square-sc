// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ILRTSquared} from "../../src/interfaces/ILRTSquared.sol";
import {PriceProvider} from "../../src/PriceProvider.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Utils} from "../Utils.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";

interface IWeETH {
    function getEETHByWeETH(
        uint256 _weETHAmount
    ) external view returns (uint256);
}

contract AddPriceConfigWbtcWeETH is Utils, GnosisHelpers {
    address weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address weETHOracle = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address wbtcEthOracle = 0xdeb288F737066589598e9214E782fa5A8eD689e8;

    PriceProvider.Config weETHConfig = PriceProvider.Config({
        oracle: weETHOracle,
        priceFunctionCalldata: abi.encodeWithSelector(
            IWeETH.getEETHByWeETH.selector,
            1 ether
        ),
        isChainlinkType: false,
        oraclePriceDecimals: 18,
        maxStaleness: 0,
        dataType: PriceProvider.ReturnType.Uint256,
        isBaseTokenEth: true
    });

    PriceProvider.Config wbtcConfig = PriceProvider.Config({
        oracle: wbtcEthOracle,
        priceFunctionCalldata: hex"",
        isChainlinkType: true,
        oraclePriceDecimals: IAggregatorV3(wbtcEthOracle).decimals(),
        maxStaleness: 1 days,
        dataType: PriceProvider.ReturnType.Int256,
        isBaseTokenEth: true
    });
    
    PriceProvider priceProvider = PriceProvider(0x2B90103cdc9Bba6c0dBCAaF961F0B5b1920F19E3);
    ILRTSquared lrtSquared = ILRTSquared(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);

    function run() public {
        address[] memory tokens = new address[](2);
        tokens[0] = weETH;
        tokens[1] = wbtc;

        PriceProvider.Config[] memory configs = new PriceProvider.Config[](2);
        configs[0] = weETHConfig;
        configs[1] = wbtcConfig;

        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));
        string memory addTokenConfig = iToHex(abi.encodeWithSignature("setTokenConfig(address[],(address,bytes,bool,uint8,uint24,uint8,bool)[])", tokens, configs));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(address(priceProvider)), addTokenConfig, true)));

        vm.createDir("./output", true);
        string memory path = "./output/AddPriceConfigBtcWeEth.json";

        vm.writeFile(path, gnosisTx);
        executeGnosisTransactionBundle(path, lrtSquared.governor());

        priceProvider.getPriceInEth(wbtc);
        priceProvider.getPriceInEth(weETH);
    }
}
