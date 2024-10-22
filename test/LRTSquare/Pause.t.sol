// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, ILRTSquared, Governable, SafeERC20, IERC20} from "./LRTSquaredSetup.t.sol";

error EnforcedPause();
error ExpectedPause();

contract LRTSquaredPauseTest is LRTSquaredTestSetup {
    using SafeERC20 for IERC20;

    function test_CanSetPauser() public {
        address newPauser = makeAddr("newPauser");
        vm.prank(address(timelock));
        vm.expectEmit(true, true, true, true);
        emit ILRTSquared.PauserSet(newPauser, true);
        lrtSquared.setPauser(newPauser, true);
        
        vm.prank(address(timelock)); 
        vm.expectEmit(true, true, true, true);
        emit ILRTSquared.PauserSet(newPauser, false);
        lrtSquared.setPauser(newPauser, false);
    }

    function test_CanAddMultiplePausers() public {
        address newPauser1 = makeAddr("newPauser1");
        address newPauser2 = makeAddr("newPauser2");
        address newPauser3 = makeAddr("newPauser3");

        vm.startPrank(address(timelock));
        lrtSquared.setPauser(newPauser1, true);
        lrtSquared.setPauser(newPauser2, true);
        lrtSquared.setPauser(newPauser3, true);
        vm.stopPrank();

        assertEq(lrtSquared.pauser(newPauser1), true);
        assertEq(lrtSquared.pauser(newPauser2), true);
        assertEq(lrtSquared.pauser(newPauser3), true);
    }

    function test_CannotSetPauserInSameState() public {
        vm.prank(address(timelock));
        vm.expectRevert(ILRTSquared.AlreadyInSameState.selector);
        lrtSquared.setPauser(pauser, true);

        vm.prank(address(timelock));
        lrtSquared.setPauser(pauser, false);
        
        vm.prank(address(timelock));
        vm.expectRevert(ILRTSquared.AlreadyInSameState.selector);
        lrtSquared.setPauser(pauser, false);
    }

    function test_OnlyGovernorCanSetPauser() public {
        address newPauser = makeAddr("newPauser");
        vm.prank(address(newPauser));
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquared.setPauser(newPauser, true);
    }

    function test_PauserCanPause() public {
        assertEq(lrtSquared.paused(), false);

        vm.prank(pauser);
        lrtSquared.pause();

        assertEq(lrtSquared.paused(), true);
    }

    function test_PauserCanUnpause() public {
        vm.prank(pauser);
        lrtSquared.pause();
        assertEq(lrtSquared.paused(), true);

        vm.prank(pauser);
        lrtSquared.unpause();
        assertEq(lrtSquared.paused(), false);
    }

    function test_CommunityPause() public {
        assertEq(lrtSquared.paused(), false);

        uint256 contractEthBalBefore = address(lrtSquared).balance;
        uint256 communityPauseDepositBefore = lrtSquared
            .communityPauseDepositedAmt();

        assertEq(contractEthBalBefore, 0);
        assertEq(communityPauseDepositBefore, 0);

        deal(alice, communityPauseDepositAmt);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ILRTSquared.CommunityPause(alice);
        lrtSquared.communityPause{value: communityPauseDepositAmt}();

        assertEq(lrtSquared.paused(), true);

        uint256 contractEthBalAfter = address(lrtSquared).balance;
        uint256 communityPauseDepositAfter = lrtSquared
            .communityPauseDepositedAmt();

        assertEq(contractEthBalAfter, communityPauseDepositAmt);
        assertEq(communityPauseDepositAfter, communityPauseDepositAmt);
    }

    function test_CannotPauseWhenAlreadyPaused() public {
        vm.prank(pauser);
        lrtSquared.pause();
        assertEq(lrtSquared.paused(), true);

        vm.prank(pauser);
        vm.expectRevert(EnforcedPause.selector);
        lrtSquared.pause();
    }

    function test_CannotUnpauseWhenAlreadyPaused() public {
        vm.prank(pauser);
        vm.expectRevert(ExpectedPause.selector);
        lrtSquared.unpause();
    }

    function test_CannotCommunityPauseWhenAlreadyPaused() public {
        vm.prank(pauser);
        lrtSquared.pause();
        assertEq(lrtSquared.paused(), true);

        uint256 depositAmt = 1 ether;
        vm.prank(address(timelock));
        lrtSquared.setCommunityPauseDepositAmount(depositAmt);

        deal(alice, depositAmt);

        vm.prank(alice);
        vm.expectRevert(EnforcedPause.selector);
        lrtSquared.communityPause{value: depositAmt}();
    }

    function test_CannotCommunityPauseIfDepositAmountNotSet() public {
        vm.prank(address(timelock));
        lrtSquared.setCommunityPauseDepositAmount(0);

        vm.prank(alice);
        vm.expectRevert(ILRTSquared.CommunityPauseDepositNotSet.selector);
        lrtSquared.communityPause();
    }

    function test_CannotCommunityPauseIfIncorrectDepositAmountIsSent() public {
        uint256 depositAmt = 1 ether;
        vm.prank(address(timelock));
        lrtSquared.setCommunityPauseDepositAmount(depositAmt);

        deal(alice, depositAmt);

        vm.prank(alice);
        vm.expectRevert(ILRTSquared.IncorrectAmountOfEtherSent.selector);
        lrtSquared.communityPause{value: depositAmt - 1}();
    }

    function test_OnlyPauserCanPause() public {
        vm.startPrank(alice);
        vm.expectRevert(ILRTSquared.OnlyPauser.selector);
        lrtSquared.pause();
        vm.stopPrank();
    }

    function test_OnlyPauserCanUnpause() public {
        vm.prank(pauser);
        lrtSquared.pause();

        vm.startPrank(alice);
        vm.expectRevert(ILRTSquared.OnlyPauser.selector);
        lrtSquared.unpause();
        vm.stopPrank();
    }

    function test_CanUnpauseAfterCommunityPause() public {
        assertEq(lrtSquared.paused(), false);

        deal(alice, communityPauseDepositAmt);
        vm.prank(alice);
        lrtSquared.communityPause{value: communityPauseDepositAmt}();

        assertEq(lrtSquared.paused(), true);

        lrtSquared.withdrawCommunityDepositedPauseAmount();

        vm.prank(pauser);
        lrtSquared.unpause();
        assertEq(lrtSquared.paused(), false);

        vm.stopPrank();
    }

    function test_CanUnpauseIfCommunityPauseDepositNotWithdrawn() public {
        assertEq(lrtSquared.paused(), false);

        deal(alice, communityPauseDepositAmt);
        vm.prank(alice);
        lrtSquared.communityPause{value: communityPauseDepositAmt}();

        assertEq(lrtSquared.paused(), true);

        uint256 balBefore = address(timelock).balance;

        vm.prank(pauser);
        lrtSquared.unpause();

        uint256 balAfter = address(timelock).balance;

        assertEq(balAfter - balBefore, communityPauseDepositAmt);
    }

    function test_WithdrawCommunityPauseDepositIsPermissionless() public {
        assertEq(lrtSquared.paused(), false);

        deal(alice, communityPauseDepositAmt);
        vm.prank(alice);
        lrtSquared.communityPause{value: communityPauseDepositAmt}();

        assertEq(lrtSquared.paused(), true);

        uint256 balBefore = address(timelock).balance;

        address newAddr = makeAddr("newAddr");
        vm.prank(newAddr);
        emit ILRTSquared.CommunityPauseAmountWithdrawal(address(timelock), communityPauseDepositAmt);
        lrtSquared.withdrawCommunityDepositedPauseAmount();
        uint256 balAfter = address(timelock).balance;

        assertEq(balAfter - balBefore, communityPauseDepositAmt);
    }       

    function test_CannotDepositWhenPaused() public {
        vm.prank(pauser);
        lrtSquared.pause();

        address[] memory _tokens = new address[](1);
        _tokens[0] = address(tokens[0]);

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 10 * 10 ** tokenDecimals[0];
        vm.startPrank(alice);
        deal(_tokens[0], alice, _amounts[0]);
        IERC20(_tokens[0]).safeIncreaseAllowance(
            address(lrtSquared),
            _amounts[0]
        );

        vm.expectRevert(EnforcedPause.selector);
        lrtSquared.deposit(_tokens, _amounts, alice);

        vm.stopPrank();
    }
}
