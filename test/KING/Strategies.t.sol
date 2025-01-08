// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseStrategy} from "../../src/strategies/BaseStrategy.sol";
import {EEigenStrategy} from "../../src/strategies/EEigenStrategy.sol";
import {SEthFiStrategy} from "../../src/strategies/SEthFiStrategy.sol";
import {KINGCore} from "../../src/KING/KINGCore.sol";
import {KINGAdmin} from "../../src/KING/KINGAdmin.sol";
import {IKING} from "../../src/interfaces/IKING.sol";
import {PriceProvider} from "../../src/PriceProvider.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {BadStrategyWithReturnTokenZero} from "../../src/mocks/BadStrategyWithReturnTokenZero.sol";
import {BadStrategyWithReturnTokenUnregistered} from "../../src/mocks/BadStrategyWithReturnTokenUnregistered.sol";
import {Governable} from "../../src/governance/Governable.sol";
import {BoringVaultPriceProvider, Ownable} from "../../src/BoringVaultPriceProvider.sol";

contract KINGStrategiesTest is Test {
    using SafeERC20 for IERC20;

    uint64 public constant HUNDRED_PERCENT_LIMIT = 1_000_000_000;

    address owner = 0xF46D3734564ef9a5a16fC3B1216831a28f78e2B5;
    PriceProvider priceProvider = PriceProvider(0x2B90103cdc9Bba6c0dBCAaF961F0B5b1920F19E3);
    IKING king = IKING(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);

    address eEigen = 0xE77076518A813616315EaAba6cA8e595E845EeE9;
    address sEthFi = 0x86B5780b606940Eb59A062aA85a07959518c0161;
    address eigen = 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83;
    address ethFi = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    EEigenStrategy eEigenStrategy;
    SEthFiStrategy sEthFiStrategy;
    BoringVaultPriceProvider boringVaultPriceProvider;

    function setUp() public {
        string memory mainnet = "https://eth-pokt.nodies.app";
        vm.createSelectFork(mainnet);

        vm.startPrank(owner);

        address[] memory vaultTokens = new address[](2);
        vaultTokens[0] = eEigen;
        vaultTokens[1] = sEthFi;

        address[] memory underlyingTokens = new address[](2);
        underlyingTokens[0] = eigen;
        underlyingTokens[1] = ethFi;

        uint8[] memory priceDecimals = new uint8[](2);
        priceDecimals[0] = 18;
        priceDecimals[1] = 18;

        boringVaultPriceProvider = new BoringVaultPriceProvider(owner, address(priceProvider), vaultTokens, underlyingTokens, priceDecimals);


        address[] memory tokens = new address[](2);
        tokens[0] = eEigen;
        tokens[1] = sEthFi;

        PriceProvider.Config[] memory priceProviderConfig = new PriceProvider.Config[](tokens.length);
        priceProviderConfig[0] = PriceProvider.Config({
            oracle: address(boringVaultPriceProvider),
            priceFunctionCalldata: abi.encodeWithSelector(BoringVaultPriceProvider.getPriceInEth.selector, tokens[0]),
            isChainlinkType: false,
            oraclePriceDecimals: BoringVaultPriceProvider(address(boringVaultPriceProvider)).decimals(eEigen),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Uint256,
            isBaseTokenEth: true
        });
        priceProviderConfig[1] = PriceProvider.Config({
            oracle: address(boringVaultPriceProvider),
            priceFunctionCalldata: abi.encodeWithSelector(BoringVaultPriceProvider.getPriceInEth.selector, tokens[1]),
            isChainlinkType: false,
            oraclePriceDecimals: BoringVaultPriceProvider(address(boringVaultPriceProvider)).decimals(sEthFi),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Uint256,
            isBaseTokenEth: true
        });

        priceProvider.setTokenConfig(tokens, priceProviderConfig);
        king.registerToken(tokens[0], HUNDRED_PERCENT_LIMIT);
        king.registerToken(tokens[1], HUNDRED_PERCENT_LIMIT);

        // TODO: Remove this when the contracts are upgraded on Mainnet
        // Upgrade KING2 contracts to support this
        address kingCoreImpl = address(new KINGCore());
        address kingAdminImpl = address(new KINGAdmin());
        KINGCore(address(king)).upgradeToAndCall(kingCoreImpl, "");
        KINGCore(address(king)).setAdminImpl(kingAdminImpl);

        // Set strategy
        eEigenStrategy = new EEigenStrategy(address(priceProvider));
        sEthFiStrategy = new SEthFiStrategy(address(priceProvider));

        IKING.StrategyConfig memory eEigenStrategyConfig = IKING.StrategyConfig({
            strategyAdapter: address(eEigenStrategy),
            maxSlippageInBps: 50
        });

        IKING.StrategyConfig memory sEthFiStrategyConfig = IKING.StrategyConfig({
            strategyAdapter: address(sEthFiStrategy),
            maxSlippageInBps: 50
        });

        king.setTokenStrategyConfig(eigen, eEigenStrategyConfig);
        king.setTokenStrategyConfig(ethFi, sEthFiStrategyConfig);

        vm.stopPrank();
    }

    function test_VerifyDeploy() external view {
        assertEq(king.tokenStrategyConfig(eigen).strategyAdapter, address(eEigenStrategy));
        assertEq(king.tokenStrategyConfig(ethFi).strategyAdapter, address(sEthFiStrategy));
    }

    function test_AddEigenToStrategy() external {
        uint256 eigenBalBefore = IERC20(eigen).balanceOf(address(king));
        uint256 eEigenBalBefore = IERC20(eEigen).balanceOf(address(king));
        
        uint256 amount = 10 ether;
        vm.prank(owner);
        king.depositToStrategy(eigen, amount);
        
        uint256 eigenBalAfter = IERC20(eigen).balanceOf(address(king));
        uint256 eEigenBalAfter = IERC20(eEigen).balanceOf(address(king));

        assertEq(eigenBalBefore - eigenBalAfter, amount);
        assertGt(eEigenBalAfter - eEigenBalBefore, 0);
    }

    function test_AddEthFiToStrategy() external {
        uint256 ethFiBalBefore = IERC20(ethFi).balanceOf(address(king));
        uint256 sEthFiBalBefore = IERC20(sEthFi).balanceOf(address(king));
        
        uint256 amount = 10 ether;
        vm.prank(owner);
        king.depositToStrategy(ethFi, amount);
        
        uint256 ethFiBalAfter = IERC20(ethFi).balanceOf(address(king));
        uint256 sEthFiBalAfter = IERC20(sEthFi).balanceOf(address(king));

        assertEq(ethFiBalBefore - ethFiBalAfter, amount);
        assertGt(sEthFiBalAfter - sEthFiBalBefore, 0);
    }

    function test_CanDepositAllTokensToStrategyIfAmountIsMaxUint() public {
        uint256 eigenBalBefore = IERC20(eigen).balanceOf(address(king));
        assertGt(eigenBalBefore, 0);
        vm.prank(address(owner));
        king.depositToStrategy(eigen, type(uint256).max);

        uint256 eigenBalAfter = IERC20(eigen).balanceOf(address(king));
        assertEq(eigenBalAfter, 0);
    }

    function test_CannotAddStrategyForAnTokenAddressZero() public {
        IKING.StrategyConfig memory strategyConfig;

        vm.prank(owner);
        vm.expectRevert(IKING.InvalidValue.selector);
        king.setTokenStrategyConfig(address(0), strategyConfig);
    }
    
    function test_CannotAddStrategyForAnUnregisteredToken() public {
        IKING.StrategyConfig memory strategyConfig;

        vm.prank(owner);
        vm.expectRevert(IKING.TokenNotRegistered.selector);
        king.setTokenStrategyConfig(owner, strategyConfig);
    }

    function test_CannotAddStrategyForWhichReturnTokenIsZeroAddress() public {
        BadStrategyWithReturnTokenZero badStrategy = new BadStrategyWithReturnTokenZero(address(priceProvider));
        IKING.StrategyConfig memory strategyConfig = IKING.StrategyConfig({
            strategyAdapter: address(badStrategy),
            maxSlippageInBps: 50
        }); 

        vm.prank(owner);
        vm.expectRevert(IKING.StrategyReturnTokenCannotBeAddressZero.selector);
        king.setTokenStrategyConfig(eigen, strategyConfig);
    }

    function test_CannotAddStrategyForWhichReturnTokenIsNotRegistered() public {
        BadStrategyWithReturnTokenUnregistered badStrategy = new BadStrategyWithReturnTokenUnregistered(address(priceProvider));
        IKING.StrategyConfig memory strategyConfig = IKING.StrategyConfig({
            strategyAdapter: address(badStrategy),
            maxSlippageInBps: 50
        }); 

        vm.prank(owner);
        vm.expectRevert(IKING.StrategyReturnTokenNotRegistered.selector);
        king.setTokenStrategyConfig(eigen, strategyConfig);
    }

    function test_CannotAddStrategyWhereStrategyAdapterIsAddressZero() public {
        IKING.StrategyConfig memory strategyConfig = IKING.StrategyConfig({
            strategyAdapter: address(0),
            maxSlippageInBps: 50
        }); 

        vm.prank(owner);
        vm.expectRevert(IKING.StrategyAdapterCannotBeAddressZero.selector);
        king.setTokenStrategyConfig(eigen, strategyConfig);
    }

    function test_CannotAddStrategyWhereMaxSlippageIsGreaterThanLimit() public {
        IKING.StrategyConfig memory strategyConfig = IKING.StrategyConfig({
            strategyAdapter: address(eEigenStrategy),
            maxSlippageInBps: 1000
        }); 

        vm.prank(owner);
        vm.expectRevert(IKING.SlippageCannotBeGreaterThanMaxLimit.selector);
        king.setTokenStrategyConfig(eigen, strategyConfig);
    }

    function test_OnlyGovernorCanAddStrategy() public {
        IKING.StrategyConfig memory strategyConfig = IKING.StrategyConfig({
            strategyAdapter: address(eEigenStrategy),
            maxSlippageInBps: 50
        }); 

        vm.prank(address(1));
        vm.expectRevert(Governable.OnlyGovernor.selector);
        king.setTokenStrategyConfig(eigen, strategyConfig);
    }

    function test_CannotDepositToStrategyIfAmountIsZero() public {
        vm.prank(address(owner));
        vm.expectRevert(IKING.AmountCannotBeZero.selector);
        king.depositToStrategy(eigen, 0);
    }

    function test_CannotDepositToStrategyIfTokenStrategyNotConfigured() public {
        vm.prank(address(owner));
        vm.expectRevert(IKING.TokenStrategyConfigNotSet.selector);
        king.depositToStrategy(weth, 1);
    }

    function test_OnlyGovernorCanDepositIntoStrategy() public {
        vm.prank(address(1));
        vm.expectRevert(Governable.OnlyGovernor.selector);
        king.depositToStrategy(eigen, 1);
    }
}