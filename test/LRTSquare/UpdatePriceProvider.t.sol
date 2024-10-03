// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LRTSquare, MockPriceProvider} from "./LRTSquareSetup.t.sol";

contract LRTSquareUpdatePriceProviderTest is LRTSquareTestSetup {
    function test_UpdatePriceProviderWithGovernance() public {
        assertEq(lrtSquare.priceProvider(), address(priceProvider));
        address newPriceProvider = address(new MockPriceProvider());

        _updatePriceProvider(newPriceProvider, hex"");
        assertEq(lrtSquare.priceProvider(), newPriceProvider);
    }

    function test_CannotUpdatePriceProviderIfAddressZero() public {
        _updatePriceProvider(
            address(0),
            abi.encodeWithSelector(LRTSquare.InvalidValue.selector)
        );
    }
}
