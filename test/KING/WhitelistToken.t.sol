// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {KINGTestSetup, IKING} from "./KINGSetup.t.sol";

contract KINGWhitelistTokenTest is KINGTestSetup {
    function setUp() public override {
        super.setUp();
        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
    }

    function test_WhitelistTokenWithGovernance() public {
        assertEq(king.isTokenWhitelisted(address(tokens[0])), true);
        _updateWhitelist(address(tokens[0]), false, hex"");

        assertEq(king.isTokenWhitelisted(address(tokens[0])), false);
    }

    function test_CannotWhitelistTokenIfAddressZero() public {
        _updateWhitelist(
            address(0),
            false,
            abi.encodeWithSelector(IKING.InvalidValue.selector)
        );
    }

    function test_CannotWhitelistTokenIfNotAlreadyRegistered() public {
        _updateWhitelist(
            address(tokens[1]),
            true,
            abi.encodeWithSelector(IKING.TokenNotRegistered.selector)
        );
    }
}
