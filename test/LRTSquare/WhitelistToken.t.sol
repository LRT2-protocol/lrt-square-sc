// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, LRTSquared} from "./LRTSquaredSetup.t.sol";

contract LRTSquaredWhitelistTokenTest is LRTSquaredTestSetup {
    function setUp() public override {
        super.setUp();
        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
    }

    function test_WhitelistTokenWithGovernance() public {
        assertEq(lrtSquared.isTokenWhitelisted(address(tokens[0])), true);
        _updateWhitelist(address(tokens[0]), false, hex"");

        assertEq(lrtSquared.isTokenWhitelisted(address(tokens[0])), false);
    }

    function test_CannotWhitelistTokenIfAddressZero() public {
        _updateWhitelist(
            address(0),
            false,
            abi.encodeWithSelector(LRTSquared.InvalidValue.selector)
        );
    }

    function test_CannotWhitelistTokenIfNotAlreadyRegistered() public {
        _updateWhitelist(
            address(tokens[1]),
            true,
            abi.encodeWithSelector(LRTSquared.TokenNotRegistered.selector)
        );
    }
}
