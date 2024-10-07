// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LRTSquare, IERC20, SafeERC20} from "./LRTSquareSetup.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Governable} from "../../src/governance/Governable.sol";

contract LRTSquareFeeTest is LRTSquareTestSetup {
    function test_CanSetFee() public {
        address treasuryAddr = vm.addr(0x11111);
        uint48 depositFee = 1;
        uint48 redeemFee = 2;

        LRTSquare.Fee memory fee = LRTSquare.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(address(timelock));
        lrtSquare.setFee(fee);

        (
            address treasuryAddrFromContract, 
            uint48 depositFeeFromContract, 
            uint48 redeemFeeFromContract
        ) = lrtSquare.fee();

        assertEq(treasuryAddr, treasuryAddrFromContract);
        assertEq(depositFee, depositFeeFromContract);
        assertEq(redeemFee, redeemFeeFromContract);
    }

    function test_OnlyGovernorCanSetFee() public {
        address treasuryAddr = vm.addr(0x11111);
        uint48 depositFee = 1;
        uint48 redeemFee = 2;

        LRTSquare.Fee memory fee = LRTSquare.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(alice);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquare.setFee(fee);
    }

    function test_DepositFeeCannotBeGreaterThanHundredPercent() public {
        address treasuryAddr = vm.addr(0x11111);
        uint48 depositFee = HUNDRED_PERCENT_IN_BPS + 1;
        uint48 redeemFee = 2;

        LRTSquare.Fee memory fee = LRTSquare.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(address(timelock));
        vm.expectRevert(LRTSquare.InvalidValue.selector);
        lrtSquare.setFee(fee);
    }

    function test_RedeemFeeCannotBeGreaterThanHundredPercent() public {
        address treasuryAddr = vm.addr(0x11111);
        uint48 depositFee = 1;
        uint48 redeemFee = HUNDRED_PERCENT_IN_BPS + 1;

        LRTSquare.Fee memory fee = LRTSquare.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(address(timelock));
        vm.expectRevert(LRTSquare.InvalidValue.selector);
        lrtSquare.setFee(fee);
    }
    
    function test_TreasuryCannotBeZeroAddress() public {
        address treasuryAddr = address(0);
        uint48 depositFee = 1;
        uint48 redeemFee = 2;

        LRTSquare.Fee memory fee = LRTSquare.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(address(timelock));
        vm.expectRevert(LRTSquare.InvalidValue.selector);
        lrtSquare.setFee(fee);

        vm.prank(address(timelock));
        vm.expectRevert(LRTSquare.InvalidValue.selector);
        lrtSquare.setTreasuryAddress(treasuryAddr);
    }

    function test_SetTreasury() public {
        address treasuryAddr = makeAddr("treasuryAddr");
        vm.prank(address(timelock));
        lrtSquare.setTreasuryAddress(treasuryAddr);

        (address treasuryAddrFromContract, , ) = lrtSquare.fee();

        assertEq(treasuryAddrFromContract, treasuryAddr);
    }
}