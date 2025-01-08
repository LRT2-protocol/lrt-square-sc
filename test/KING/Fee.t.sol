// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {KINGTestSetup, IKING, IERC20, SafeERC20} from "./KINGSetup.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Governable} from "../../src/governance/Governable.sol";

contract KINGFeeTest is KINGTestSetup {
    function test_CanSetFee() public {
        address treasuryAddr = vm.addr(0x11111);
        uint48 depositFee = 1;
        uint48 redeemFee = 2;

        IKING.Fee memory fee = IKING.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(address(timelock));
        king.setFee(fee);

        IKING.Fee memory feeFromContract = king.fee();

        assertEq(treasuryAddr, feeFromContract.treasury);
        assertEq(depositFee, feeFromContract.depositFeeInBps);
        assertEq(redeemFee, feeFromContract.redeemFeeInBps);
    }

    function test_OnlyGovernorCanSetFee() public {
        address treasuryAddr = vm.addr(0x11111);
        uint48 depositFee = 1;
        uint48 redeemFee = 2;

        IKING.Fee memory fee = IKING.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(alice);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        king.setFee(fee);
    }

    function test_DepositFeeCannotBeGreaterThanHundredPercent() public {
        address treasuryAddr = vm.addr(0x11111);
        uint48 depositFee = HUNDRED_PERCENT_IN_BPS + 1;
        uint48 redeemFee = 2;

        IKING.Fee memory fee = IKING.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(address(timelock));
        vm.expectRevert(IKING.InvalidValue.selector);
        king.setFee(fee);
    }

    function test_RedeemFeeCannotBeGreaterThanHundredPercent() public {
        address treasuryAddr = vm.addr(0x11111);
        uint48 depositFee = 1;
        uint48 redeemFee = HUNDRED_PERCENT_IN_BPS + 1;

        IKING.Fee memory fee = IKING.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(address(timelock));
        vm.expectRevert(IKING.InvalidValue.selector);
        king.setFee(fee);
    }
    
    function test_TreasuryCannotBeZeroAddress() public {
        address treasuryAddr = address(0);
        uint48 depositFee = 1;
        uint48 redeemFee = 2;

        IKING.Fee memory fee = IKING.Fee(treasuryAddr, depositFee, redeemFee);
        vm.prank(address(timelock));
        vm.expectRevert(IKING.InvalidValue.selector);
        king.setFee(fee);

        vm.prank(address(timelock));
        vm.expectRevert(IKING.InvalidValue.selector);
        king.setTreasuryAddress(treasuryAddr);
    }

    function test_SetTreasury() public {
        address treasuryAddr = makeAddr("treasuryAddr");
        vm.prank(address(timelock));
        king.setTreasuryAddress(treasuryAddr);

        address treasuryAddrFromContract = king.fee().treasury;
        assertEq(treasuryAddrFromContract, treasuryAddr);
    }
}