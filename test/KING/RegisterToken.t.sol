// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {KINGTestSetup, IKING} from "./KINGSetup.t.sol";

contract KINGRegisterTokenTest is KINGTestSetup {
    function test_RegisterTokenWithGovernance() public {
        assertEq(king.isTokenRegistered(address(tokens[0])), false);
        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        assertEq(king.isTokenRegistered(address(tokens[0])), true);
    }

    function test_CannotRegisterTokenIfAddressZero() public {
        _registerToken(
            address(0),
            0,
            abi.encodeWithSelector(IKING.InvalidValue.selector)
        );
    }

    function test_CannotRegisterTokenIfAlreadyRegistered() public {
        _registerToken(address(tokens[0]), 0, hex"");

        _registerToken(
            address(tokens[0]),
            0,
            abi.encodeWithSelector(IKING.TokenAlreadyRegistered.selector)
        );
    }

    function test_CannotRegisterTokenIfPriceNotConfigured() public {
        priceProvider.setPrice(address(tokens[0]), 0);

        _registerToken(
            address(tokens[0]),
            0,
            abi.encodeWithSelector(
                IKING.PriceProviderNotConfigured.selector
            )
        );
    }

    function test_CannotRegisterTokenIfMaxPercentageIsTooHigh() public {
        _registerToken(
            address(tokens[0]),
            king.HUNDRED_PERCENT_LIMIT() + 1,
            abi.encodeWithSelector(
                IKING.WeightLimitCannotBeGreaterThanHundred.selector
            )
        );
    }
}
