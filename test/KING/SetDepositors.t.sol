// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {KINGTestSetup, IKING} from "./KINGSetup.t.sol";

contract KINGSetDepositorsTest is KINGTestSetup {
    function test_SetDepositorsWithGovernance() public {
        address depositor = makeAddr("depositor");
        address[] memory depositors = new address[](1);
        depositors[0] = depositor;

        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;

        assertEq(king.depositor(depositor), false);
        _setDepositors(depositors, isDepositor, hex"");
        assertEq(king.depositor(depositor), true);
    }

    function test_CannotSetDepositorIfAddressZero() public {
        address[] memory depositors = new address[](1);
        depositors[0] = address(0);

        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;

        _setDepositors(
            depositors,
            isDepositor,
            abi.encodeWithSelector(IKING.InvalidValue.selector)
        );
    }

    function test_CannotSetDepositorIfArrayLengthMismatch() public {
        address[] memory depositors = new address[](1);
        depositors[0] = address(0);

        bool[] memory isDepositor = new bool[](2);
        isDepositor[0] = true;
        isDepositor[0] = false;

        _setDepositors(
            depositors,
            isDepositor,
            abi.encodeWithSelector(IKING.ArrayLengthMismatch.selector)
        );
    }
}
