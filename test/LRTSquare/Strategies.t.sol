// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseStrategy} from "../../src/strategies/BaseStrategy.sol";
import {EEigenStrategy} from "../../src/strategies/EEigenStrategy.sol";
import {SEthFiStrategy} from "../../src/strategies/SEthFiStrategy.sol";
import {LRTSquaredCore} from "../../src/LRTSquared/LRTSquaredCore.sol";
import {LRTSquaredAdmin} from "../../src/LRTSquared/LRTSquaredAdmin.sol";
import {ILRTSquared} from "../../src/interfaces/ILRTSquared.sol";
import {PriceProvider} from "../../src/PriceProvider.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {BadStrategyWithReturnTokenZero} from "../../src/mocks/BadStrategyWithReturnTokenZero.sol";
import {BadStrategyWithReturnTokenUnregistered} from "../../src/mocks/BadStrategyWithReturnTokenUnregistered.sol";
import {Governable} from "../../src/governance/Governable.sol";

contract LRTSquaredStrategiesTest is Test {
    using SafeERC20 for IERC20;

    uint64 public constant HUNDRED_PERCENT_LIMIT = 1_000_000_000;

    address owner = 0xF46D3734564ef9a5a16fC3B1216831a28f78e2B5;
    PriceProvider priceProvider = PriceProvider(0x2B90103cdc9Bba6c0dBCAaF961F0B5b1920F19E3);
    ILRTSquared lrtSquared = ILRTSquared(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);

    address eEigen = 0xE77076518A813616315EaAba6cA8e595E845EeE9;
    address sEthFi = 0x86B5780b606940Eb59A062aA85a07959518c0161;
    address eigen = 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83;
    address ethFi = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address eEigenOracle = 0xf2917e602C2dCa458937fad715bb1E465305A4A1;
    address sEthFiOracle = 0xf2917e602C2dCa458937fad715bb1E465305A4A1;

    EEigenStrategy eEigenStrategy;
    SEthFiStrategy sEthFiStrategy;

    function setUp() public {
        string memory mainnet = "https://eth-pokt.nodies.app";
        vm.createSelectFork(mainnet);

        vm.startPrank(owner);

        address[] memory tokens = new address[](2);
        tokens[0] = eEigen;
        tokens[1] = sEthFi;

        PriceProvider.Config[] memory priceProviderConfig = new PriceProvider.Config[](tokens.length);
       
        priceProviderConfig[0] = PriceProvider.Config({
            oracle: eEigenOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(eEigenOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false
        });
       
        priceProviderConfig[1] = PriceProvider.Config({
            oracle: sEthFiOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(sEthFiOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false
        });

        priceProvider.setTokenConfig(tokens, priceProviderConfig);
        lrtSquared.registerToken(tokens[0], HUNDRED_PERCENT_LIMIT);
        lrtSquared.registerToken(tokens[1], HUNDRED_PERCENT_LIMIT);

        // TODO: Remove this when the contracts are upgraded on Mainnet
        // Upgrade LRT2 contracts to support this
        address lrtSquaredCoreImpl = address(new LRTSquaredCore());
        address lrtSquaredAdminImpl = address(new LRTSquaredAdmin());
        LRTSquaredCore(address(lrtSquared)).upgradeToAndCall(lrtSquaredCoreImpl, "");
        LRTSquaredCore(address(lrtSquared)).setAdminImpl(lrtSquaredAdminImpl);

        // Set strategy
        eEigenStrategy = new EEigenStrategy(address(priceProvider));
        sEthFiStrategy = new SEthFiStrategy(address(priceProvider));

        ILRTSquared.StrategyConfig memory eEigenStrategyConfig = ILRTSquared.StrategyConfig({
            strategyAdapter: address(eEigenStrategy),
            maxSlippageInBps: 50
        });

        ILRTSquared.StrategyConfig memory sEthFiStrategyConfig = ILRTSquared.StrategyConfig({
            strategyAdapter: address(sEthFiStrategy),
            maxSlippageInBps: 50
        });

        lrtSquared.setTokenStrategyConfig(eigen, eEigenStrategyConfig);
        lrtSquared.setTokenStrategyConfig(ethFi, sEthFiStrategyConfig);

        vm.stopPrank();
    }

    function test_VerifyDeploy() external view {
        assertEq(lrtSquared.tokenStrategyConfig(eigen).strategyAdapter, address(eEigenStrategy));
        assertEq(lrtSquared.tokenStrategyConfig(ethFi).strategyAdapter, address(sEthFiStrategy));
    }

    function test_AddEigenToStrategy() external {
        uint256 eigenBalBefore = IERC20(eigen).balanceOf(address(lrtSquared));
        uint256 eEigenBalBefore = IERC20(eEigen).balanceOf(address(lrtSquared));
        
        uint256 amount = 10 ether;
        vm.prank(owner);
        lrtSquared.depositToStrategy(eigen, amount);
        
        uint256 eigenBalAfter = IERC20(eigen).balanceOf(address(lrtSquared));
        uint256 eEigenBalAfter = IERC20(eEigen).balanceOf(address(lrtSquared));

        assertEq(eigenBalBefore - eigenBalAfter, amount);
        assertGt(eEigenBalAfter - eEigenBalBefore, 0);
    }

    function test_AddEthFiToStrategy() external {
        uint256 ethFiBalBefore = IERC20(ethFi).balanceOf(address(lrtSquared));
        uint256 sEthFiBalBefore = IERC20(sEthFi).balanceOf(address(lrtSquared));
        
        uint256 amount = 10 ether;
        vm.prank(owner);
        lrtSquared.depositToStrategy(ethFi, amount);
        
        uint256 ethFiBalAfter = IERC20(ethFi).balanceOf(address(lrtSquared));
        uint256 sEthFiBalAfter = IERC20(sEthFi).balanceOf(address(lrtSquared));

        assertEq(ethFiBalBefore - ethFiBalAfter, amount);
        assertGt(sEthFiBalAfter - sEthFiBalBefore, 0);
    }

    function test_CanDepositAllTokensToStrategyIfAmountIsMaxUint() public {
        uint256 eigenBalBefore = IERC20(eigen).balanceOf(address(lrtSquared));
        assertGt(eigenBalBefore, 0);
        vm.prank(address(owner));
        lrtSquared.depositToStrategy(eigen, type(uint256).max);

        uint256 eigenBalAfter = IERC20(eigen).balanceOf(address(lrtSquared));
        assertEq(eigenBalAfter, 0);
    }

    function test_CannotAddStrategyForAnTokenAddressZero() public {
        ILRTSquared.StrategyConfig memory strategyConfig;

        vm.prank(owner);
        vm.expectRevert(ILRTSquared.InvalidValue.selector);
        lrtSquared.setTokenStrategyConfig(address(0), strategyConfig);
    }
    
    function test_CannotAddStrategyForAnUnregisteredToken() public {
        ILRTSquared.StrategyConfig memory strategyConfig;

        vm.prank(owner);
        vm.expectRevert(ILRTSquared.TokenNotRegistered.selector);
        lrtSquared.setTokenStrategyConfig(owner, strategyConfig);
    }

    function test_CannotAddStrategyForWhichReturnTokenIsZeroAddress() public {
        BadStrategyWithReturnTokenZero badStrategy = new BadStrategyWithReturnTokenZero(address(priceProvider));
        ILRTSquared.StrategyConfig memory strategyConfig = ILRTSquared.StrategyConfig({
            strategyAdapter: address(badStrategy),
            maxSlippageInBps: 50
        }); 

        vm.prank(owner);
        vm.expectRevert(ILRTSquared.StrategyReturnTokenCannotBeAddressZero.selector);
        lrtSquared.setTokenStrategyConfig(eigen, strategyConfig);
    }

    function test_CannotAddStrategyForWhichReturnTokenIsNotRegistered() public {
        BadStrategyWithReturnTokenUnregistered badStrategy = new BadStrategyWithReturnTokenUnregistered(address(priceProvider));
        ILRTSquared.StrategyConfig memory strategyConfig = ILRTSquared.StrategyConfig({
            strategyAdapter: address(badStrategy),
            maxSlippageInBps: 50
        }); 

        vm.prank(owner);
        vm.expectRevert(ILRTSquared.StrategyReturnTokenNotRegistered.selector);
        lrtSquared.setTokenStrategyConfig(eigen, strategyConfig);
    }

    function test_CannotAddStrategyWhereStrategyAdapterIsAddressZero() public {
        ILRTSquared.StrategyConfig memory strategyConfig = ILRTSquared.StrategyConfig({
            strategyAdapter: address(0),
            maxSlippageInBps: 50
        }); 

        vm.prank(owner);
        vm.expectRevert(ILRTSquared.StrategyAdapterCannotBeAddressZero.selector);
        lrtSquared.setTokenStrategyConfig(eigen, strategyConfig);
    }

    function test_CannotAddStrategyWhereMaxSlippageIsGreaterThanLimit() public {
        ILRTSquared.StrategyConfig memory strategyConfig = ILRTSquared.StrategyConfig({
            strategyAdapter: address(eEigenStrategy),
            maxSlippageInBps: 1000
        }); 

        vm.prank(owner);
        vm.expectRevert(ILRTSquared.SlippageCannotBeGreaterThanMaxLimit.selector);
        lrtSquared.setTokenStrategyConfig(eigen, strategyConfig);
    }

    function test_OnlyGovernorCanAddStrategy() public {
        ILRTSquared.StrategyConfig memory strategyConfig = ILRTSquared.StrategyConfig({
            strategyAdapter: address(eEigenStrategy),
            maxSlippageInBps: 50
        }); 

        vm.prank(address(1));
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquared.setTokenStrategyConfig(eigen, strategyConfig);
    }

    function test_CannotDepositToStrategyIfAmountIsZero() public {
        vm.prank(address(owner));
        vm.expectRevert(ILRTSquared.AmountCannotBeZero.selector);
        lrtSquared.depositToStrategy(eigen, 0);
    }

    function test_CannotDepositToStrategyIfTokenStrategyNotConfigured() public {
        vm.prank(address(owner));
        vm.expectRevert(ILRTSquared.TokenStrategyConfigNotSet.selector);
        lrtSquared.depositToStrategy(weth, 1);
    }

    function test_OnlyGovernorCanDepositIntoStrategy() public {
        vm.prank(address(1));
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquared.depositToStrategy(eigen, 1);
    }
}