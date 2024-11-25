// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, ILRTSquared, MockPriceProvider} from "./LRTSquaredSetup.t.sol";

contract LRTSquaredUpdatePriceProviderTest is LRTSquaredTestSetup {
    function test_UpdatePriceProviderWithGovernance() public {
        assertEq(lrtSquared.priceProvider(), address(priceProvider));
        address newPriceProvider = address(new MockPriceProvider());

        _updatePriceProvider(newPriceProvider, hex"");
        assertEq(lrtSquared.priceProvider(), newPriceProvider);
    }

    function test_CannotUpdatePriceProviderIfAddressZero() public {
        _updatePriceProvider(
            address(0),
            abi.encodeWithSelector(ILRTSquared.InvalidValue.selector)
        );
    }
}
