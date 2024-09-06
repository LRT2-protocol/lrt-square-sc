// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LrtSquare} from "./LRTSquareSetup.t.sol";

contract LRTSquareWhitelistTokenTest is LRTSquareTestSetup {
    function setUp() public override {
        super.setUp();
        _registerToken(address(tokens[0]), tokenMaxPercentageValues[0], hex"");
    }

    function test_WhitelistTokenWithGovernance() public {
        assertEq(lrtSquare.isTokenWhitelisted(address(tokens[0])), true);
        _updateWhitelist(address(tokens[0]), false, hex"");

        assertEq(lrtSquare.isTokenWhitelisted(address(tokens[0])), false);
    }

    function test_CannotWhitelistTokenIfAddressZero() public {
        _updateWhitelist(
            address(0),
            false,
            abi.encodeWithSelector(LrtSquare.InvalidValue.selector)
        );
    }

    function test_CannotWhitelistTokenIfNotAlreadyRegistered() public {
        _updateWhitelist(
            address(tokens[1]),
            true,
            abi.encodeWithSelector(LrtSquare.TokenNotRegistered.selector)
        );
    }
}
