// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LrtSquare, MockPriceProvider} from "./LRTSquareSetup.t.sol";

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
            abi.encodeWithSelector(LrtSquare.InvalidValue.selector)
        );
    }
}
