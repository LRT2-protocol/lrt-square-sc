// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, IPriceProvider, LrtSquare, IERC20, SafeERC20} from "./LRTSquareSetup.t.sol";
import {Swapper1InchV6} from "../../src/Swapper1InchV6.sol";
import {PriceProvider} from "../../src/PriceProvider.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Governable} from "../../src/governance/Governable.sol";

interface IWeETH {
    function getEETHByWeETH(uint256 _weETHAmoun) external view returns (uint256);
}

contract LRTSquareRebalanceTest is LRTSquareTestSetup {
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

        swapper1Inch = new Swapper1InchV6(swapRouter1InchV6, assets);


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

        oracle = IPriceProvider(address(new PriceProvider(
            address(timelock),
            initialTokens,
            initialTokensConfig
        )));

        address[] memory depositors = new address[](1);
        depositors[0] = alice;
        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;

        lrtSquare.setDepositors(depositors, isDepositor); 
        lrtSquare.updatePriceProvider(address(oracle));
        lrtSquare.registerToken(assets[0], lrtSquare.HUNDRED_PERCENT_LIMIT());
        lrtSquare.registerToken(assets[1], lrtSquare.HUNDRED_PERCENT_LIMIT());
        lrtSquare.setSwapper(address(swapper1Inch));

        vm.stopPrank();
    }

    function test_CanRebalance() public {
        vm.prank(rebalancer);
        lrtSquare.setMaxSlippageForRebalancing(0.9 ether); // 10% slippage so swap does not fail

        deal(address(weETH), alice, 1 ether);

        // Deposit funds into the contract
        uint256 depositAmt = 1 ether;
        vm.startPrank(alice);
        address[] memory _tokens = new address[](1);
        _tokens[0] = weETH;
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = depositAmt;

        IERC20(weETH).safeIncreaseAllowance(address(lrtSquare), depositAmt);
        lrtSquare.deposit(_tokens, _amounts, alice);

        vm.stopPrank();

        // Rebalance funds to include some BTC 
        vm.prank(address(timelock));
        lrtSquare.whitelistRebalacingOutputToken(btc, true);

        uint256 vaultWeEthBalBefore = IERC20(weETH).balanceOf(address(lrtSquare));
        uint256 vaultBtcBalBefore = IERC20(btc).balanceOf(address(lrtSquare));

        assertEq(vaultWeEthBalBefore, depositAmt);
        assertEq(vaultBtcBalBefore, 0);

        uint256 rebalanceAmount = 0.5 ether;
        bytes memory swapData = getQuoteOneInch(
            vm.toString(block.chainid),
            address(swapper),
            address(lrtSquare),
            address(weETH),
            address(btc),
            rebalanceAmount
        );

        vm.prank(rebalancer);
        lrtSquare.rebalance(weETH, btc, rebalanceAmount, 1, swapData);

        uint256 vaultWeEthBalAfter = IERC20(weETH).balanceOf(address(lrtSquare));
        uint256 vaultBtcBalAfter = IERC20(btc).balanceOf(address(lrtSquare));
       
        assertEq(vaultWeEthBalAfter, depositAmt - rebalanceAmount);
        assertGt(vaultBtcBalAfter, 0);
    }

    function test_OnlyGovernorCanSetRebalancer() public {
        vm.prank(alice);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquare.setRebalancer(alice);

        vm.startPrank(address(timelock));
        vm.expectEmit(true, true, true, true);
        emit LrtSquare.RebalancerSet(lrtSquare.rebalancer(), alice);
        lrtSquare.setRebalancer(alice);
        assertEq(lrtSquare.rebalancer(), alice);
        vm.stopPrank();
    }

    function test_RebalancerCannotBeAddressZero() public {
        vm.prank(address(timelock));
        vm.expectRevert(LrtSquare.InvalidValue.selector);
        lrtSquare.setRebalancer(address(0));
    }

    function test_OnlyRebalancerCanSetMaxSlippage() public {
        uint256 newMaxSlippage = 1 ether;
        vm.prank(alice);
        vm.expectRevert(LrtSquare.OnlyRebalancer.selector);
        lrtSquare.setMaxSlippageForRebalancing(newMaxSlippage);

        vm.startPrank(rebalancer);
        vm.expectEmit(true, true, true, true);
        emit LrtSquare.MaxSlippageForRebalanceSet(lrtSquare.maxSlippageForRebalancing(), newMaxSlippage);
        lrtSquare.setMaxSlippageForRebalancing(newMaxSlippage);
        assertEq(lrtSquare.maxSlippageForRebalancing(), newMaxSlippage);
        vm.stopPrank();
    }

    function test_MaxSlippageCannotBeZero() public {
        vm.prank(rebalancer);
        vm.expectRevert(LrtSquare.InvalidValue.selector);
        lrtSquare.setMaxSlippageForRebalancing(0);
    }

    function test_OnlyGovernorCanWhitelistRebalanceOutputTokens() public {
        vm.prank(alice);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquare.whitelistRebalacingOutputToken(weETH, true);
        
        vm.prank(address(timelock));
        vm.expectEmit(true, true, true, true);
        emit LrtSquare.WhitelistRebalanceOutputToken(weETH, true);
        lrtSquare.whitelistRebalacingOutputToken(weETH, true);
        assertEq(lrtSquare.isWhitelistedRebalanceOutputToken(weETH), true);
    }

    function test_CannotWhitelistAddressZeroAsRebalanceOutputToken() public {
        vm.prank(address(timelock));
        vm.expectRevert(LrtSquare.InvalidValue.selector);
        lrtSquare.whitelistRebalacingOutputToken(address(0), true);
    }

    function test_CannotWhitelistAsRebalanceOutputTokenIfTokenNotRegistered() public {
        vm.prank(address(timelock));
        vm.expectRevert(LrtSquare.TokenNotRegistered.selector);
        lrtSquare.whitelistRebalacingOutputToken(address(1), true);
    }

    function test_CannotWhitelistAsRebalanceOutputTokenIfPriceNotConfigured() public {
        // set mock price provider which does not have weETH price
        vm.prank(address(timelock));
        lrtSquare.updatePriceProvider(address(priceProvider));

        vm.prank(address(timelock));
        vm.expectRevert(LrtSquare.PriceProviderNotConfigured.selector);
        lrtSquare.whitelistRebalacingOutputToken(weETH, true);
    }

    function test_CannotRebalanceIfInputTokenNotRegistered() public {
        vm.prank(rebalancer);
        vm.expectRevert(LrtSquare.TokenNotRegistered.selector);
        lrtSquare.rebalance(address(1), btc, 1, 1, hex"");
    }

    function test_CannotRebalanceIfOutputTokenNotRegistered() public {
        vm.prank(rebalancer);
        vm.expectRevert(LrtSquare.TokenNotRegistered.selector);
        lrtSquare.rebalance(weETH, address(1), 1, 1, hex"");
    }

    function test_CannotRebalanceIfOutputTokenNotWhitelisted() public {
        vm.prank(address(timelock));
        lrtSquare.updateWhitelist(btc, false);

        vm.prank(rebalancer);
        vm.expectRevert(LrtSquare.TokenNotWhitelisted.selector);
        lrtSquare.rebalance(weETH, btc, 1, 1, hex"");
    }

    function test_CannotRebalanceIfOutputTokenIsNotARegisteredValidOutputToken() public {
        vm.prank(address(timelock));
        lrtSquare.whitelistRebalacingOutputToken(btc, false);

        vm.prank(rebalancer);
        vm.expectRevert(LrtSquare.NotAValidRebalanceOutputToken.selector);
        lrtSquare.rebalance(weETH, btc, 1, 1, hex"");
    }
}