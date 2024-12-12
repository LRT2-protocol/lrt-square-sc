// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";
import {ILRTSquared} from "../../src/interfaces/ILRTSquared.sol";
import {PriceProvider} from "../../src/PriceProvider.sol";
import {BoringVaultPriceProvider} from "../../src/BoringVaultPriceProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
 
contract ForkAddToStrategies is Test, GnosisHelpers {
    address sEthFiStrategy = 0x76C57e359C0eDA0aac54d97832fb1b4451805aD8;
    address eEigenStrategy = 0x2F2342BD9fca72887f46De9522014f4cd154Cf3e;
    address boringVaultPriceProvider = 0x130e22952DD3DE2c80EBdFC2B256E344ff3A0729;
    address eEigen = 0xE77076518A813616315EaAba6cA8e595E845EeE9;
    address sEthFi = 0x86B5780b606940Eb59A062aA85a07959518c0161;
    address eigen = 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83;
    address ethFi = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;

    address lrtSquared = 0x8F08B70456eb22f6109F57b8fafE862ED28E6040;
    address priceProvider = 0x2B90103cdc9Bba6c0dBCAaF961F0B5b1920F19E3;

    uint64 HUNDRED_PERCENT_LIMIT = 1_000_000_000;

    function setUp() public {
        string memory mainnet = "https://eth-pokt.nodies.app";
        vm.createSelectFork(mainnet);
    }

    function test_AddToStrategies() public {
        string memory gnosisTx = _getGnosisHeader(vm.toString(block.chainid));

        address[] memory tokens = new address[](2);
        tokens[0] = eEigen;
        tokens[1] = sEthFi;

        PriceProvider.Config[] memory priceProviderConfig = new PriceProvider.Config[](2);
        priceProviderConfig[0] = PriceProvider.Config({
            oracle: address(boringVaultPriceProvider),
            priceFunctionCalldata: abi.encodeWithSelector(BoringVaultPriceProvider.getPriceInEth.selector, tokens[0]),
            isChainlinkType: false,
            oraclePriceDecimals: BoringVaultPriceProvider(address(boringVaultPriceProvider)).decimals(tokens[0]),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Uint256,
            isBaseTokenEth: true
        });

        priceProviderConfig[1] = PriceProvider.Config({
            oracle: address(boringVaultPriceProvider),
            priceFunctionCalldata: abi.encodeWithSelector(BoringVaultPriceProvider.getPriceInEth.selector, tokens[1]),
            isChainlinkType: false,
            oraclePriceDecimals: BoringVaultPriceProvider(address(boringVaultPriceProvider)).decimals(tokens[1]),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Uint256,
            isBaseTokenEth: true
        });

        string memory priceProviderSetConfig = iToHex(abi.encodeWithSignature("setTokenConfig(address[],(address,bytes,bool,uint8,uint24,uint8,bool)[])", tokens, priceProviderConfig));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(priceProvider), priceProviderSetConfig, false)));

        string memory registerSEthFiToken = iToHex(abi.encodeWithSignature("registerToken(address,uint64)", sEthFi, HUNDRED_PERCENT_LIMIT));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(lrtSquared), registerSEthFiToken, false)));
        
        string memory registerEEigenToken = iToHex(abi.encodeWithSignature("registerToken(address,uint64)", eEigen, HUNDRED_PERCENT_LIMIT));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(lrtSquared), registerEEigenToken, false)));
        
        ILRTSquared.StrategyConfig memory ethFiStrategyConfig = ILRTSquared.StrategyConfig({
            strategyAdapter: address(sEthFiStrategy),
            maxSlippageInBps: 50
        });
        string memory setEthFiStrategyConfig = iToHex(abi.encodeWithSignature("setTokenStrategyConfig(address,(address,uint96))", ethFi, ethFiStrategyConfig));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(lrtSquared), setEthFiStrategyConfig, false)));

        ILRTSquared.StrategyConfig memory eigenStrategyConfig = ILRTSquared.StrategyConfig({
            strategyAdapter: address(eEigenStrategy),
            maxSlippageInBps: 50
        });
        string memory setEigenStrategyConfig = iToHex(abi.encodeWithSignature("setTokenStrategyConfig(address,(address,uint96))", eigen, eigenStrategyConfig));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(lrtSquared), setEigenStrategyConfig, false)));

        string memory depositEthFiToStrategy = iToHex(abi.encodeWithSignature("depositToStrategy(address,uint256)", ethFi, IERC20(ethFi).balanceOf(lrtSquared)));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(lrtSquared), depositEthFiToStrategy, false)));

        string memory depositEigenToStrategy = iToHex(abi.encodeWithSignature("depositToStrategy(address,uint256)", eigen, IERC20(eigen).balanceOf(lrtSquared)));
        gnosisTx = string(abi.encodePacked(gnosisTx, _getGnosisTransaction(addressToHex(lrtSquared), depositEigenToStrategy, true)));

        vm.createDir("./output", true);
        string memory path = "./output/DepositToStrategy.json";
        vm.writeFile(path, gnosisTx);

        executeGnosisTransactionBundle(path, ILRTSquared(lrtSquared).governor());
    }
}