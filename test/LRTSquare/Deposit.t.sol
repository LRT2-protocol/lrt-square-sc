// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LrtSquare, IERC20, SafeERC20} from "./LRTSquareSetup.t.sol";

contract LRTSquareDepositTest is LRTSquareTestSetup {
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();

        _registerToken(address(tokens[0]), tokenMaxPercentageValues[0], hex"");
        _registerToken(address(tokens[1]), tokenMaxPercentageValues[1], hex"");
        _registerToken(address(tokens[2]), tokenMaxPercentageValues[2], hex"");

        address[] memory depositors = new address[](1);
        depositors[0] = alice;
        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;
        _setDepositors(depositors, isDepositor, hex"");
    }

    function test_Deposit() public {
        uint256[] memory _tokenIndices = new uint256[](3);
        _tokenIndices[0] = 0;
        _tokenIndices[1] = 1;
        _tokenIndices[2] = 2;

        address[] memory _tokens = new address[](3);
        _tokens[0] = address(tokens[_tokenIndices[0]]);
        _tokens[1] = address(tokens[_tokenIndices[1]]);
        _tokens[2] = address(tokens[_tokenIndices[2]]);

        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = 10 * 10 ** tokenDecimals[_tokenIndices[0]];
        _amounts[1] = 50 * 10 ** tokenDecimals[_tokenIndices[1]];
        _amounts[2] = 25 * 10 ** tokenDecimals[_tokenIndices[2]];

        uint256 totalValueInEthAfterDeposit = _getAvsTokenValuesInEth(
            _tokenIndices,
            _amounts
        );
        uint256 expectedSharesAfterDeposit = totalValueInEthAfterDeposit;

        vm.startPrank(alice);
        for (uint256 i = 0; i < _tokens.length; ) {
            deal(_tokens[i], alice, _amounts[i]);

            IERC20(_tokens[i]).safeIncreaseAllowance(
                address(lrtSquare),
                _amounts[i]
            );
            unchecked {
                ++i;
            }
        }
        vm.expectEmit(true, true, true, true);
        emit LrtSquare.Deposit(
            alice,
            alice,
            expectedSharesAfterDeposit,
            _tokens,
            _amounts
        );
        lrtSquare.deposit(_tokens, _amounts, alice);
        vm.stopPrank();

        assertApproxEqAbs(
            lrtSquare.balanceOf(alice),
            expectedSharesAfterDeposit,
            10
        );

        assertApproxEqAbs(
            lrtSquare.assetOf(alice, address(tokens[0])),
            _amounts[0],
            10
        );
        assertApproxEqAbs(
            lrtSquare.assetOf(alice, address(tokens[1])),
            _amounts[1],
            10
        );
        assertApproxEqAbs(
            lrtSquare.assetOf(alice, address(tokens[2])),
            _amounts[2],
            10
        );

        (address[] memory assets, uint256[] memory assetAmounts) = lrtSquare
            .totalAssets();
        assertEq(assets.length, 3);
        assertEq(assetAmounts.length, 3);

        assertEq(assets[0], address(_tokens[0]));
        assertEq(assets[1], address(_tokens[1]));
        assertEq(assets[2], address(_tokens[2]));

        assertApproxEqAbs(assetAmounts[0], _amounts[0], 10);
        assertApproxEqAbs(assetAmounts[1], _amounts[1], 10);
        assertApproxEqAbs(assetAmounts[2], _amounts[2], 10);
    }

    function test_OnlyDepositorsCanDeposit() public {
        address[] memory _tokens = new address[](3);
        _tokens[0] = address(tokens[0]);
        _tokens[1] = address(tokens[1]);
        _tokens[2] = address(tokens[2]);

        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = 10 * 10 ** tokenDecimals[0];
        _amounts[1] = 50 * 10 ** tokenDecimals[1];
        _amounts[2] = 25 * 10 ** tokenDecimals[2];

        vm.prank(owner);
        vm.expectRevert(LrtSquare.OnlyDepositors.selector);
        lrtSquare.deposit(_tokens, _amounts, owner);
    }

    function test_CannotDepositIfArrayLengthMismatch() public {
        address[] memory _tokens = new address[](3);
        _tokens[0] = address(tokens[0]);
        _tokens[1] = address(tokens[1]);
        _tokens[2] = address(tokens[2]);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 10 * 10 ** tokenDecimals[0];
        _amounts[1] = 50 * 10 ** tokenDecimals[1];

        vm.prank(alice);
        vm.expectRevert(LrtSquare.ArrayLengthMismatch.selector);
        lrtSquare.deposit(_tokens, _amounts, alice);
    }

    function test_CannotDepositIfRecipientAddress0() public {
        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[0]);
        _tokens[1] = address(tokens[1]);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 10 * 10 ** tokenDecimals[0];
        _amounts[1] = 50 * 10 ** tokenDecimals[1];

        vm.prank(alice);
        vm.expectRevert(LrtSquare.InvalidRecipient.selector);
        lrtSquare.deposit(_tokens, _amounts, address(0));
    }

    function test_CannotDepositIfTokenNotRegistered() public {
        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[0]);
        _tokens[1] = address(address(1));

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 10 * 10 ** tokenDecimals[0];
        _amounts[1] = 1;

        vm.prank(alice);
        vm.expectRevert(LrtSquare.TokenNotRegistered.selector);
        lrtSquare.deposit(_tokens, _amounts, alice);
    }

    function test_CannotDepositIfTokenNotWhitelisted() public {
        _updateWhitelist(address(tokens[0]), false, hex"");

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[0]);
        _tokens[1] = address(tokens[1]);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 10 * 10 ** tokenDecimals[0];
        _amounts[1] = 10 * 10 ** tokenDecimals[1];

        vm.prank(alice);
        vm.expectRevert(LrtSquare.TokenNotWhitelisted.selector);
        lrtSquare.deposit(_tokens, _amounts, alice);
    }

    function test_CannotDepositIfPriceIsZero() public {
        priceProvider.setPrice(address(tokens[0]), 0);

        address[] memory _tokens = new address[](1);
        _tokens[0] = address(tokens[0]);

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 10 * 10 ** tokenDecimals[0];

        vm.prank(alice);
        vm.expectRevert(LrtSquare.PriceProviderFailed.selector);
        lrtSquare.deposit(_tokens, _amounts, alice);
    }
}
