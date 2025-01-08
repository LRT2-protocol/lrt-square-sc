// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {KINGTestSetup, IKING, MockPriceProvider} from "./KINGSetup.t.sol";

contract KINGUpdatePriceProviderTest is KINGTestSetup {
    function test_UpdatePriceProviderWithGovernance() public {
        assertEq(king.priceProvider(), address(priceProvider));
        address newPriceProvider = address(new MockPriceProvider());

        _updatePriceProvider(newPriceProvider, hex"");
        assertEq(king.priceProvider(), newPriceProvider);
    }

    function test_CannotUpdatePriceProviderIfAddressZero() public {
        _updatePriceProvider(
            address(0),
            abi.encodeWithSelector(IKING.InvalidValue.selector)
        );
    }
}
