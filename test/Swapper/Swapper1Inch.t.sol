// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Utils} from "../Utils.sol";
import {Swapper1InchV6} from "../../src/Swapper1InchV6.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Swapper1InchV6Test is Utils {
    using SafeERC20 for IERC20;

    Swapper1InchV6 swapper;
    
    address alice = makeAddr("alice");
    address swapRouter1InchV6 = 0x111111125421cA6dc452d289314280a0f8842A65;
    address weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address btc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    function setUp() public {
        string memory mainnet = "https://eth-pokt.nodies.app";
        vm.createSelectFork(mainnet);

        address[] memory assets = new address[](2);
        assets[0] = address(weETH);
        assets[1] = address(btc);

        swapper = new Swapper1InchV6(swapRouter1InchV6, assets);
    }

    function test_Swap() public {
        vm.startPrank(alice);
        deal(weETH, address(swapper), 1 ether);

        uint256 aliceBtcBalBefore = IERC20(btc).balanceOf(alice);

        bytes memory swapData = getQuoteOneInch(
            vm.toString(block.chainid),
            address(swapper),
            address(alice),
            address(weETH),
            address(btc),
            1 ether
        );

        uint256 receivedAmt = swapper.swap(
            address(weETH),
            address(btc),
            1 ether,
            1,
            swapData
        );
        uint256 aliceBtcBalAfter = IERC20(btc).balanceOf(alice);
        
        assertGt(receivedAmt, 0);
        assertEq(aliceBtcBalAfter - aliceBtcBalBefore, receivedAmt);

        vm.stopPrank();
    }

}
