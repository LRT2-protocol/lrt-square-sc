// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LRTSquare, SafeERC20, IERC20} from "./LRTSquareSetup.t.sol";

error EnforcedPause();
error ExpectedPause();

contract LRTSquarePauseTest is LRTSquareTestSetup {
    using SafeERC20 for IERC20;

    function test_PauserCanPause() public {
        assertEq(lrtSquare.paused(), false);

        vm.prank(pauser);
        lrtSquare.pause();

        assertEq(lrtSquare.paused(), true);
    }

    function test_PauserCanUnpause() public {
        vm.prank(pauser);
        lrtSquare.pause();
        assertEq(lrtSquare.paused(), true);

        vm.prank(pauser);
        lrtSquare.unpause();
        assertEq(lrtSquare.paused(), false);
    }

    function test_CommunityPause() public {
        uint256 depositAmt = 100 ether;
        vm.prank(address(timelock));
        lrtSquare.setCommunityPauseDepositAmount(depositAmt);

        assertEq(lrtSquare.paused(), false);

        uint256 contractEthBalBefore = address(lrtSquare).balance;
        uint256 communityPauseDepositBefore = lrtSquare
            .communityPauseDepositedAmt();

        assertEq(contractEthBalBefore, 0);
        assertEq(communityPauseDepositBefore, 0);

        deal(alice, depositAmt);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit LRTSquare.CommunityPause(alice);
        lrtSquare.communityPause{value: depositAmt}();

        assertEq(lrtSquare.paused(), true);

        uint256 contractEthBalAfter = address(lrtSquare).balance;
        uint256 communityPauseDepositAfter = lrtSquare
            .communityPauseDepositedAmt();

        assertEq(contractEthBalAfter, depositAmt);
        assertEq(communityPauseDepositAfter, depositAmt);
    }

    function test_CannotPauseWhenAlreadyPaused() public {
        vm.prank(pauser);
        lrtSquare.pause();
        assertEq(lrtSquare.paused(), true);

        vm.prank(pauser);
        vm.expectRevert(EnforcedPause.selector);
        lrtSquare.pause();
    }

    function test_CannotUnpauseWhenAlreadyPaused() public {
        vm.prank(pauser);
        vm.expectRevert(ExpectedPause.selector);
        lrtSquare.unpause();
    }

    function test_CannotCommunityPauseWhenAlreadyPaused() public {
        vm.prank(pauser);
        lrtSquare.pause();
        assertEq(lrtSquare.paused(), true);

        uint256 depositAmt = 1 ether;
        vm.prank(address(timelock));
        lrtSquare.setCommunityPauseDepositAmount(depositAmt);

        deal(alice, depositAmt);

        vm.prank(alice);
        vm.expectRevert(EnforcedPause.selector);
        lrtSquare.communityPause{value: depositAmt}();
    }

    function test_CannotCommunityPauseIfDepositAmountNotSet() public {
        vm.prank(alice);
        vm.expectRevert(LRTSquare.CommunityPauseDepositNotSet.selector);
        lrtSquare.communityPause();
    }

    function test_CannotCommunityPauseIfIncorrectDepositAmountIsSent() public {
        uint256 depositAmt = 1 ether;
        vm.prank(address(timelock));
        lrtSquare.setCommunityPauseDepositAmount(depositAmt);

        deal(alice, depositAmt);

        vm.prank(alice);
        vm.expectRevert(LRTSquare.IncorrectAmountOfEtherSent.selector);
        lrtSquare.communityPause{value: depositAmt - 1}();
    }

    function test_OnlyPauserCanPause() public {
        vm.startPrank(alice);
        vm.expectRevert(LRTSquare.OnlyPauser.selector);
        lrtSquare.pause();
        vm.stopPrank();
    }

    function test_OnlyPauserCanUnpause() public {
        vm.prank(pauser);
        lrtSquare.pause();

        vm.startPrank(alice);
        vm.expectRevert(LRTSquare.OnlyPauser.selector);
        lrtSquare.unpause();
        vm.stopPrank();
    }

    function test_CanUnpauseAfterCommunityPause() public {
        uint256 depositAmt = 100 ether;
        vm.prank(address(timelock));
        lrtSquare.setCommunityPauseDepositAmount(depositAmt);

        assertEq(lrtSquare.paused(), false);

        deal(alice, depositAmt);
        vm.prank(alice);
        lrtSquare.communityPause{value: depositAmt}();

        assertEq(lrtSquare.paused(), true);

        vm.startPrank(pauser);
        lrtSquare.withdrawCommunityDepositedPauseAmount();

        lrtSquare.unpause();
        assertEq(lrtSquare.paused(), false);

        vm.stopPrank();
    }

    function test_CanUnpauseIfCommunityPauseDepositNotWithdrawn() public {
        uint256 depositAmt = 100 ether;
        vm.prank(address(timelock));
        lrtSquare.setCommunityPauseDepositAmount(depositAmt);

        assertEq(lrtSquare.paused(), false);

        deal(alice, depositAmt);
        vm.prank(alice);
        lrtSquare.communityPause{value: depositAmt}();

        assertEq(lrtSquare.paused(), true);

        uint256 balBefore = pauser.balance;

        vm.prank(pauser);
        lrtSquare.unpause();

        uint256 balAfter = pauser.balance;

        assertGt(balAfter, balBefore);
    }

    function test_CannotDepositWhenPaused() public {
        vm.prank(pauser);
        lrtSquare.pause();

        address[] memory _tokens = new address[](1);
        _tokens[0] = address(tokens[0]);

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 10 * 10 ** tokenDecimals[0];
        vm.startPrank(alice);
        deal(_tokens[0], alice, _amounts[0]);
        IERC20(_tokens[0]).safeIncreaseAllowance(
            address(lrtSquare),
            _amounts[0]
        );

        vm.expectRevert(EnforcedPause.selector);
        lrtSquare.deposit(_tokens, _amounts, alice);

        vm.stopPrank();
    }
}
