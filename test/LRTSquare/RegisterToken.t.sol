// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LrtSquare} from "./LRTSquareSetup.t.sol";

contract LRTSquareRegisterTokenTest is LRTSquareTestSetup {
    function test_RegisterTokenWithGovernance() public {
        assertEq(lrtSquare.isTokenRegistered(address(tokens[0])), false);
        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        assertEq(lrtSquare.isTokenRegistered(address(tokens[0])), true);
    }

    function test_CannotRegisterTokenIfAddressZero() public {
        _registerToken(
            address(0),
            0,
            abi.encodeWithSelector(LrtSquare.InvalidValue.selector)
        );
    }

    function test_CannotRegisterTokenIfAlreadyRegistered() public {
        _registerToken(address(tokens[0]), 0, hex"");

        _registerToken(
            address(tokens[0]),
            0,
            abi.encodeWithSelector(LrtSquare.TokenAlreadyRegistered.selector)
        );
    }

    function test_CannotRegisterTokenIfPriceNotConfigured() public {
        priceProvider.setPrice(address(tokens[0]), 0);

        _registerToken(
            address(tokens[0]),
            0,
            abi.encodeWithSelector(
                LrtSquare.PriceProviderNotConfigured.selector
            )
        );
    }

    function test_CannotRegisterTokenIfMaxPercentageIsTooHigh() public {
        _registerToken(
            address(tokens[0]),
            lrtSquare.HUNDRED_PERCENT_LIMIT() + 1,
            abi.encodeWithSelector(
                LrtSquare.WeightLimitCannotBeGreaterThanHundred.selector
            )
        );
    }
}
