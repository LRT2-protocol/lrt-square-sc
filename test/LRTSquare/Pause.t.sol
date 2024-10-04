// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LRTSquare, Governable, SafeERC20, IERC20} from "./LRTSquareSetup.t.sol";

error EnforcedPause();
error ExpectedPause();

contract LRTSquarePauseTest is LRTSquareTestSetup {
    using SafeERC20 for IERC20;

    function test_CanSetPauser() public {
        address newPauser = makeAddr("newPauser");
        vm.prank(address(timelock));
        vm.expectEmit(true, true, true, true);
        emit LRTSquare.PauserSet(newPauser, true);
        lrtSquare.setPauser(newPauser, true);
        
        vm.prank(address(timelock)); 
        vm.expectEmit(true, true, true, true);
        emit LRTSquare.PauserSet(newPauser, false);
        lrtSquare.setPauser(newPauser, false);
    }

    function test_CanAddMultiplePausers() public {
        address newPauser1 = makeAddr("newPauser1");
        address newPauser2 = makeAddr("newPauser2");
        address newPauser3 = makeAddr("newPauser3");

        vm.startPrank(address(timelock));
        lrtSquare.setPauser(newPauser1, true);
        lrtSquare.setPauser(newPauser2, true);
        lrtSquare.setPauser(newPauser3, true);
        vm.stopPrank();

        assertEq(lrtSquare.pauser(newPauser1), true);
        assertEq(lrtSquare.pauser(newPauser2), true);
        assertEq(lrtSquare.pauser(newPauser3), true);
    }

    function test_CannotSetPauserInSameState() public {
        vm.prank(address(timelock));
        vm.expectRevert(LRTSquare.AlreadyInSameState.selector);
        lrtSquare.setPauser(pauser, true);

        vm.prank(address(timelock));
        lrtSquare.setPauser(pauser, false);
        
        vm.prank(address(timelock));
        vm.expectRevert(LRTSquare.AlreadyInSameState.selector);
        lrtSquare.setPauser(pauser, false);
    }

    function test_OnlyGovernorCanSetPauser() public {
        address newPauser = makeAddr("newPauser");
        vm.prank(address(newPauser));
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquare.setPauser(newPauser, true);
    }

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
        assertEq(lrtSquare.paused(), false);

        uint256 contractEthBalBefore = address(lrtSquare).balance;
        uint256 communityPauseDepositBefore = lrtSquare
            .communityPauseDepositedAmt();

        assertEq(contractEthBalBefore, 0);
        assertEq(communityPauseDepositBefore, 0);

        deal(alice, communityPauseDepositAmt);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit LRTSquare.CommunityPause(alice);
        lrtSquare.communityPause{value: communityPauseDepositAmt}();

        assertEq(lrtSquare.paused(), true);

        uint256 contractEthBalAfter = address(lrtSquare).balance;
        uint256 communityPauseDepositAfter = lrtSquare
            .communityPauseDepositedAmt();

        assertEq(contractEthBalAfter, communityPauseDepositAmt);
        assertEq(communityPauseDepositAfter, communityPauseDepositAmt);
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
        vm.prank(address(timelock));
        lrtSquare.setCommunityPauseDepositAmount(0);

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
        assertEq(lrtSquare.paused(), false);

        deal(alice, communityPauseDepositAmt);
        vm.prank(alice);
        lrtSquare.communityPause{value: communityPauseDepositAmt}();

        assertEq(lrtSquare.paused(), true);

        lrtSquare.withdrawCommunityDepositedPauseAmount();

        vm.prank(pauser);
        lrtSquare.unpause();
        assertEq(lrtSquare.paused(), false);

        vm.stopPrank();
    }

    function test_CanUnpauseIfCommunityPauseDepositNotWithdrawn() public {
        assertEq(lrtSquare.paused(), false);

        deal(alice, communityPauseDepositAmt);
        vm.prank(alice);
        lrtSquare.communityPause{value: communityPauseDepositAmt}();

        assertEq(lrtSquare.paused(), true);

        uint256 balBefore = address(timelock).balance;

        vm.prank(pauser);
        lrtSquare.unpause();

        uint256 balAfter = address(timelock).balance;

        assertEq(balAfter - balBefore, communityPauseDepositAmt);
    }

    function test_WithdrawCommunityPauseDepositIsPermissionless() public {
        assertEq(lrtSquare.paused(), false);

        deal(alice, communityPauseDepositAmt);
        vm.prank(alice);
        lrtSquare.communityPause{value: communityPauseDepositAmt}();

        assertEq(lrtSquare.paused(), true);

        uint256 balBefore = address(timelock).balance;

        address newAddr = makeAddr("newAddr");
        vm.prank(newAddr);
        emit LRTSquare.CommunityPauseAmountWithdrawal(address(timelock), communityPauseDepositAmt);
        lrtSquare.withdrawCommunityDepositedPauseAmount();
        uint256 balAfter = address(timelock).balance;

        assertEq(balAfter - balBefore, communityPauseDepositAmt);
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
