// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, IPriceProvider, ILRTSquared, IERC20, SafeERC20} from "./LRTSquaredSetup.t.sol";
import {Swapper1InchV6} from "../../src/Swapper1InchV6.sol";
import {PriceProvider} from "../../src/PriceProvider.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Governable} from "../../src/governance/Governable.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";

interface IWeETH {
    function getEETHByWeETH(uint256 _weETHAmoun) external view returns (uint256);
}

contract LRTSquaredRebalanceTest is LRTSquaredTestSetup {
    using SafeERC20 for IERC20;

    Swapper1InchV6 swapper1Inch;
    
    address swapRouter1InchV6 = 0x111111125421cA6dc452d289314280a0f8842A65;
    address weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address btc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address weETHOracle = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address btcEthOracle = 0xdeb288F737066589598e9214E782fa5A8eD689e8;
    address ethUsdOracle = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    IPriceProvider oracle;
    PriceProvider.Config weETHConfig;
    PriceProvider.Config btcConfig;
    PriceProvider.Config ethConfig;

    function setUp() public override {
        string memory mainnet = "https://eth-pokt.nodies.app";
        vm.createSelectFork(mainnet);

        super.setUp();

        address[] memory assets = new address[](2);
        assets[0] = address(weETH);
        assets[1] = address(btc);

        swapper1Inch = new Swapper1InchV6(swapRouter1InchV6);


        vm.startPrank(address(timelock));

        weETHConfig = PriceProvider.Config({
            oracle: weETHOracle,
            priceFunctionCalldata: abi.encodeWithSelector(
                IWeETH.getEETHByWeETH.selector,
                1000000000000000000
            ),
            isChainlinkType: false,
            oraclePriceDecimals: 18,
            maxStaleness: 0,
            dataType: PriceProvider.ReturnType.Uint256,
            isBaseTokenEth: true
        });

        btcConfig = PriceProvider.Config({
            oracle: btcEthOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(btcEthOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: true
        });

        ethConfig = PriceProvider.Config({
            oracle: ethUsdOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(ethUsdOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false
        });

        address[] memory initialTokens = new address[](3);
        initialTokens[0] = weETH;
        initialTokens[1] = btc;
        initialTokens[2] = eth;

        PriceProvider.Config[] memory initialTokensConfig = new PriceProvider.Config[](3);
        initialTokensConfig[0] = weETHConfig;
        initialTokensConfig[1] = btcConfig;
        initialTokensConfig[2] = ethConfig;

        address priceProviderImpl = address(new PriceProvider());
        oracle = IPriceProvider(
            address(
                new UUPSProxy(
                    priceProviderImpl, 
                    abi.encodeWithSelector(
                        PriceProvider.initialize.selector,
                        address(timelock),
                        initialTokens,
                        initialTokensConfig
                    )
                )
            )
        );
        
        address[] memory depositors = new address[](1);
        depositors[0] = alice;
        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;

        lrtSquared.setDepositors(depositors, isDepositor); 
        lrtSquared.updatePriceProvider(address(oracle));
        lrtSquared.registerToken(assets[0], lrtSquared.HUNDRED_PERCENT_LIMIT());
        lrtSquared.registerToken(assets[1], lrtSquared.HUNDRED_PERCENT_LIMIT());
        lrtSquared.setSwapper(address(swapper1Inch));

        vm.stopPrank();
    }

    function test_CanRebalance() public {
        vm.prank(rebalancer);
        lrtSquared.setMaxSlippageForRebalancing(0.9 ether); // 10% slippage so swap does not fail

        deal(address(weETH), alice, 1 ether);

        // Deposit funds into the contract
        uint256 depositAmt = 1 ether;
        vm.startPrank(alice);
        address[] memory _tokens = new address[](1);
        _tokens[0] = weETH;
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = depositAmt;

        IERC20(weETH).safeIncreaseAllowance(address(lrtSquared), depositAmt);
        lrtSquared.deposit(_tokens, _amounts, alice);

        vm.stopPrank();

        // Rebalance funds to include some BTC 
        vm.prank(address(timelock));
        lrtSquared.whitelistRebalacingOutputToken(btc, true);

        uint256 vaultWeEthBalBefore = IERC20(weETH).balanceOf(address(lrtSquared));
        uint256 vaultBtcBalBefore = IERC20(btc).balanceOf(address(lrtSquared));

        assertEq(vaultWeEthBalBefore, depositAmt);
        assertEq(vaultBtcBalBefore, 0);

        uint256 rebalanceAmount = 0.5 ether;
        bytes memory swapData = getQuoteOneInch(
            vm.toString(block.chainid),
            address(swapper),
            address(lrtSquared),
            address(weETH),
            address(btc),
            rebalanceAmount
        );

        vm.prank(rebalancer);
        lrtSquared.rebalance(weETH, btc, rebalanceAmount, 1, swapData);

        uint256 vaultWeEthBalAfter = IERC20(weETH).balanceOf(address(lrtSquared));
        uint256 vaultBtcBalAfter = IERC20(btc).balanceOf(address(lrtSquared));
       
        assertEq(vaultWeEthBalAfter, depositAmt - rebalanceAmount);
        assertGt(vaultBtcBalAfter, 0);
    }

    function test_OnlyGovernorCanSetRebalancer() public {
        vm.prank(alice);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquared.setRebalancer(alice);

        vm.startPrank(address(timelock));
        vm.expectEmit(true, true, true, true);
        emit ILRTSquared.RebalancerSet(lrtSquared.rebalancer(), alice);
        lrtSquared.setRebalancer(alice);
        assertEq(lrtSquared.rebalancer(), alice);
        vm.stopPrank();
    }

    function test_RebalancerCannotBeAddressZero() public {
        vm.prank(address(timelock));
        vm.expectRevert(ILRTSquared.InvalidValue.selector);
        lrtSquared.setRebalancer(address(0));
    }

    function test_OnlyRebalancerCanSetMaxSlippage() public {
        uint256 newMaxSlippage = 1 ether;
        vm.prank(alice);
        vm.expectRevert(ILRTSquared.OnlyRebalancer.selector);
        lrtSquared.setMaxSlippageForRebalancing(newMaxSlippage);

        vm.startPrank(rebalancer);
        vm.expectEmit(true, true, true, true);
        emit ILRTSquared.MaxSlippageForRebalanceSet(lrtSquared.maxSlippageForRebalancing(), newMaxSlippage);
        lrtSquared.setMaxSlippageForRebalancing(newMaxSlippage);
        assertEq(lrtSquared.maxSlippageForRebalancing(), newMaxSlippage);
        vm.stopPrank();
    }

    function test_MaxSlippageCannotBeZero() public {
        vm.prank(rebalancer);
        vm.expectRevert(ILRTSquared.InvalidValue.selector);
        lrtSquared.setMaxSlippageForRebalancing(0);
    }

    function test_OnlyGovernorCanWhitelistRebalanceOutputTokens() public {
        vm.prank(alice);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquared.whitelistRebalacingOutputToken(weETH, true);
        
        vm.prank(address(timelock));
        vm.expectEmit(true, true, true, true);
        emit ILRTSquared.WhitelistRebalanceOutputToken(weETH, true);
        lrtSquared.whitelistRebalacingOutputToken(weETH, true);
        assertEq(lrtSquared.isWhitelistedRebalanceOutputToken(weETH), true);
    }

    function test_CannotWhitelistAddressZeroAsRebalanceOutputToken() public {
        vm.prank(address(timelock));
        vm.expectRevert(ILRTSquared.InvalidValue.selector);
        lrtSquared.whitelistRebalacingOutputToken(address(0), true);
    }

    function test_CannotWhitelistAsRebalanceOutputTokenIfTokenNotRegistered() public {
        vm.prank(address(timelock));
        vm.expectRevert(ILRTSquared.TokenNotRegistered.selector);
        lrtSquared.whitelistRebalacingOutputToken(address(1), true);
    }

    function test_CannotWhitelistAsRebalanceOutputTokenIfPriceNotConfigured() public {
        // set mock price provider which does not have weETH price
        vm.prank(address(timelock));
        lrtSquared.updatePriceProvider(address(priceProvider));

        vm.prank(address(timelock));
        vm.expectRevert(ILRTSquared.PriceProviderNotConfigured.selector);
        lrtSquared.whitelistRebalacingOutputToken(weETH, true);
    }

    function test_CannotRebalanceIfInputTokenNotRegistered() public {
        vm.prank(rebalancer);
        vm.expectRevert(ILRTSquared.TokenNotRegistered.selector);
        lrtSquared.rebalance(address(1), btc, 1, 1, hex"");
    }

    function test_CannotRebalanceIfOutputTokenNotRegistered() public {
        vm.prank(rebalancer);
        vm.expectRevert(ILRTSquared.TokenNotRegistered.selector);
        lrtSquared.rebalance(weETH, address(1), 1, 1, hex"");
    }

    function test_CannotRebalanceIfOutputTokenNotWhitelisted() public {
        vm.prank(address(timelock));
        lrtSquared.updateWhitelist(btc, false);

        vm.prank(rebalancer);
        vm.expectRevert(ILRTSquared.TokenNotWhitelisted.selector);
        lrtSquared.rebalance(weETH, btc, 1, 1, hex"");
    }

    function test_CannotRebalanceIfOutputTokenIsNotARegisteredValidOutputToken() public {
        vm.prank(address(timelock));
        lrtSquared.whitelistRebalacingOutputToken(btc, false);

        vm.prank(rebalancer);
        vm.expectRevert(ILRTSquared.NotAValidRebalanceOutputToken.selector);
        lrtSquared.rebalance(weETH, btc, 1, 1, hex"");
    }
}