// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, ILRTSquared} from "./LRTSquaredSetup.t.sol";

contract LRTSquaredRegisterTokenTest is LRTSquaredTestSetup {
    function test_RegisterTokenWithGovernance() public {
        assertEq(lrtSquared.isTokenRegistered(address(tokens[0])), false);
        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        assertEq(lrtSquared.isTokenRegistered(address(tokens[0])), true);
    }

    function test_CannotRegisterTokenIfAddressZero() public {
        _registerToken(
            address(0),
            0,
            abi.encodeWithSelector(ILRTSquared.InvalidValue.selector)
        );
    }

    function test_CannotRegisterTokenIfAlreadyRegistered() public {
        _registerToken(address(tokens[0]), 0, hex"");

        _registerToken(
            address(tokens[0]),
            0,
            abi.encodeWithSelector(ILRTSquared.TokenAlreadyRegistered.selector)
        );
    }

    function test_CannotRegisterTokenIfPriceNotConfigured() public {
        priceProvider.setPrice(address(tokens[0]), 0);

        _registerToken(
            address(tokens[0]),
            0,
            abi.encodeWithSelector(
                ILRTSquared.PriceProviderNotConfigured.selector
            )
        );
    }

    function test_CannotRegisterTokenIfMaxPercentageIsTooHigh() public {
        _registerToken(
            address(tokens[0]),
            lrtSquared.HUNDRED_PERCENT_LIMIT() + 1,
            abi.encodeWithSelector(
                ILRTSquared.WeightLimitCannotBeGreaterThanHundred.selector
            )
        );
    }
}
