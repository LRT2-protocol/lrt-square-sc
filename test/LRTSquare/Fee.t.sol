// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, LRTSquared, IERC20, SafeERC20} from "./LRTSquaredSetup.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Governable} from "../../src/governance/Governable.sol";

contract LRTSquaredFeeTest is LRTSquaredTestSetup {
    function test_CanSetFee() public {
        address treasuryAddr = vm.addr(0x11111);
        uint48 depositFee = 1;
        uint48 redeemFee = 2;

        LRTSquared.Fee memory fee = LRTSquared.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(address(timelock));
        lrtSquared.setFee(fee);

        (
            address treasuryAddrFromContract, 
            uint48 depositFeeFromContract, 
            uint48 redeemFeeFromContract
        ) = lrtSquared.fee();

        assertEq(treasuryAddr, treasuryAddrFromContract);
        assertEq(depositFee, depositFeeFromContract);
        assertEq(redeemFee, redeemFeeFromContract);
    }

    function test_OnlyGovernorCanSetFee() public {
        address treasuryAddr = vm.addr(0x11111);
        uint48 depositFee = 1;
        uint48 redeemFee = 2;

        LRTSquared.Fee memory fee = LRTSquared.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(alice);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquared.setFee(fee);
    }

    function test_DepositFeeCannotBeGreaterThanHundredPercent() public {
        address treasuryAddr = vm.addr(0x11111);
        uint48 depositFee = HUNDRED_PERCENT_IN_BPS + 1;
        uint48 redeemFee = 2;

        LRTSquared.Fee memory fee = LRTSquared.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(address(timelock));
        vm.expectRevert(LRTSquared.InvalidValue.selector);
        lrtSquared.setFee(fee);
    }

    function test_RedeemFeeCannotBeGreaterThanHundredPercent() public {
        address treasuryAddr = vm.addr(0x11111);
        uint48 depositFee = 1;
        uint48 redeemFee = HUNDRED_PERCENT_IN_BPS + 1;

        LRTSquared.Fee memory fee = LRTSquared.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(address(timelock));
        vm.expectRevert(LRTSquared.InvalidValue.selector);
        lrtSquared.setFee(fee);
    }
    
    function test_TreasuryCannotBeZeroAddress() public {
        address treasuryAddr = address(0);
        uint48 depositFee = 1;
        uint48 redeemFee = 2;

        LRTSquared.Fee memory fee = LRTSquared.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(address(timelock));
        vm.expectRevert(LRTSquared.InvalidValue.selector);
        lrtSquared.setFee(fee);

        vm.prank(address(timelock));
        vm.expectRevert(LRTSquared.InvalidValue.selector);
        lrtSquared.setTreasuryAddress(treasuryAddr);
    }

    function test_SetTreasury() public {
        address treasuryAddr = makeAddr("treasuryAddr");
        vm.prank(address(timelock));
        lrtSquared.setTreasuryAddress(treasuryAddr);

        (address treasuryAddrFromContract, , ) = lrtSquared.fee();

        assertEq(treasuryAddrFromContract, treasuryAddr);
    }
}