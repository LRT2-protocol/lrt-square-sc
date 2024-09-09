// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LrtSquare, IERC20, SafeERC20} from "./LRTSquareSetup.t.sol";

contract LRTSquareBasicsTest is LRTSquareTestSetup {
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();

        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        _registerToken(address(tokens[1]), tokenPositionWeightLimits[1], hex"");
        _registerToken(address(tokens[2]), tokenPositionWeightLimits[2], hex"");
    }

    function test_Deploy() public {
        assertEq(lrtSquare.isTokenRegistered(address(tokens[0])), true);
        assertEq(lrtSquare.isTokenRegistered(address(tokens[1])), true);
        assertEq(lrtSquare.isTokenRegistered(address(tokens[2])), true);

        assertEq(lrtSquare.isTokenWhitelisted(address(tokens[0])), true);
        assertEq(lrtSquare.isTokenWhitelisted(address(tokens[1])), true);
        assertEq(lrtSquare.isTokenWhitelisted(address(tokens[2])), true);

        assertEq(lrtSquare.totalSupply(), 0);
        assertEq(lrtSquare.totalAssetsValueInEth(), 0);

        vm.expectRevert(LrtSquare.TotalSupplyZero.selector);
        lrtSquare.assetsForVaultShares(1);

        address[] memory _tokens = new address[](3);
        _tokens[0] = address(tokens[0]);
        _tokens[1] = address(tokens[1]);
        _tokens[2] = address(tokens[2]);

        uint256[] memory _amounts = new uint256[](3);

        (
            address[] memory _tokensFromContract,
            uint256[] memory _amountsFromContract
        ) = lrtSquare.totalAssets();
        assertEq(_tokens, _tokensFromContract);
        assertEq(_amounts, _amountsFromContract);
    }

    function test_AvsTokenValuesInEth() public view {
        uint256[] memory _tokenIndices = new uint256[](2);
        _tokenIndices[0] = 0;
        _tokenIndices[1] = 1;

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[_tokenIndices[0]]);
        _tokens[1] = address(tokens[_tokenIndices[1]]);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 1 * 10 ** tokenDecimals[_tokenIndices[0]];
        _amounts[1] = 5 * 10 ** tokenDecimals[_tokenIndices[1]];

        uint256 expectedTotal = _getAvsTokenValuesInEth(
            _tokenIndices,
            _amounts
        );

        assertEq(
            lrtSquare.getAvsTokenValuesInEth(_tokens, _amounts),
            expectedTotal
        );
    }

    function test_CannotGetAvsTokenValuesInEthIfArrayLengthMismatch() public {
        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[0]);
        _tokens[1] = address(tokens[1]);

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 1 * 10 ** tokenDecimals[0];

        vm.expectRevert(LrtSquare.ArrayLengthMismatch.selector);
        lrtSquare.getAvsTokenValuesInEth(_tokens, _amounts);
    }

    function test_CannotGetAvsTokenValuesInEthIfTokenNotRegistered() public {
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(address(1));

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 1 ether;

        vm.expectRevert(LrtSquare.TokenNotRegistered.selector);
        lrtSquare.getAvsTokenValuesInEth(_tokens, _amounts);
    }

    function test_CannotGetAvsTokenValuesInEthIfTokenNotWhitelisted() public {
        _updateWhitelist(address(tokens[0]), false, hex"");

        address[] memory _tokens = new address[](1);
        _tokens[0] = address(tokens[0]);

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 1 * 10 ** tokenDecimals[0];

        vm.expectRevert(LrtSquare.TokenNotWhitelisted.selector);
        lrtSquare.getAvsTokenValuesInEth(_tokens, _amounts);
    }

    function test_PreviewDeposit() public {
        uint256[] memory _tokenIndices = new uint256[](2);
        _tokenIndices[0] = 0;
        _tokenIndices[1] = 1;

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[_tokenIndices[0]]);
        _tokens[1] = address(tokens[_tokenIndices[1]]);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 1 * 10 ** tokenDecimals[_tokenIndices[0]];
        _amounts[1] = 5 * 10 ** tokenDecimals[_tokenIndices[1]];

        uint256 totalValueInEth = _getAvsTokenValuesInEth(
            _tokenIndices,
            _amounts
        );
        uint256 expectedShares = _getSharesForEth(totalValueInEth);
        assertApproxEqAbs(
            lrtSquare.previewDeposit(_tokens, _amounts),
            expectedShares,
            1
        );

        _deposit(_tokens, _amounts, alice);

        _amounts[0] = 10 * 10 ** tokenDecimals[_tokenIndices[0]];
        _amounts[1] = 500 * 10 ** tokenDecimals[_tokenIndices[1]];

        uint256 totalValueInEthAfterDeposit = _getAvsTokenValuesInEth(
            _tokenIndices,
            _amounts
        );
        uint256 expectedSharesAfterDeposit = _getSharesForEth(
            totalValueInEthAfterDeposit
        );

        assertApproxEqAbs(
            lrtSquare.previewDeposit(_tokens, _amounts),
            expectedSharesAfterDeposit,
            1
        );
    }

    function test_AssetOf() public {
        uint256[] memory _tokenIndices = new uint256[](2);
        _tokenIndices[0] = 0;
        _tokenIndices[1] = 1;

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[_tokenIndices[0]]);
        _tokens[1] = address(tokens[_tokenIndices[1]]);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 1 * 10 ** tokenDecimals[_tokenIndices[0]];
        _amounts[1] = 5 * 10 ** tokenDecimals[_tokenIndices[1]];

        _deposit(_tokens, _amounts, alice);
        uint256 totalValueInEth = _getAvsTokenValuesInEth(
            _tokenIndices,
            _amounts
        );
        uint256 sharesMinted = _getSharesForEth(totalValueInEth);

        uint256 assetOfAliceInToken0 = _getAssetForVaultShares(
            sharesMinted,
            _tokens[0]
        );
        uint256 assetOfAliceInToken1 = _getAssetForVaultShares(
            sharesMinted,
            _tokens[1]
        );

        assertEq(lrtSquare.assetOf(alice, _tokens[0]), assetOfAliceInToken0);
        assertEq(lrtSquare.assetOf(alice, _tokens[1]), assetOfAliceInToken1);
    }

    function test_AssetsOf() public {
        uint256[] memory _tokenIndices = new uint256[](2);
        _tokenIndices[0] = 0;
        _tokenIndices[1] = 1;

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[_tokenIndices[0]]);
        _tokens[1] = address(tokens[_tokenIndices[1]]);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 1 * 10 ** tokenDecimals[_tokenIndices[0]];
        _amounts[1] = 5 * 10 ** tokenDecimals[_tokenIndices[1]];

        _deposit(_tokens, _amounts, alice);

        (
            address[] memory _tokensFromContract,
            uint256[] memory _amountsFromContract
        ) = lrtSquare.assetsOf(alice);

        address[] memory _expectedTokens = new address[](3);
        _expectedTokens[0] = address(tokens[_tokenIndices[0]]);
        _expectedTokens[1] = address(tokens[_tokenIndices[1]]);
        _expectedTokens[2] = address(tokens[2]);

        uint256[] memory _expectedAmounts = new uint256[](3);
        _expectedAmounts[0] = 1 * 10 ** tokenDecimals[_tokenIndices[0]];
        _expectedAmounts[1] = 5 * 10 ** tokenDecimals[_tokenIndices[1]];
        _expectedAmounts[2] = 0;

        assertEq(_tokensFromContract, _expectedTokens);
        assertApproxEqAbs(_amountsFromContract[0], _expectedAmounts[0], 10);
        assertApproxEqAbs(_amountsFromContract[1], _expectedAmounts[1], 10);
        assertApproxEqAbs(_amountsFromContract[2], _expectedAmounts[2], 10);
    }

    function test_TotalAssetsValueInEth() public {
        uint256[] memory _tokenIndices = new uint256[](2);
        _tokenIndices[0] = 0;
        _tokenIndices[1] = 1;

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[_tokenIndices[0]]);
        _tokens[1] = address(tokens[_tokenIndices[1]]);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 1 * 10 ** tokenDecimals[_tokenIndices[0]];
        _amounts[1] = 5 * 10 ** tokenDecimals[_tokenIndices[1]];

        _deposit(_tokens, _amounts, alice);
        uint256 totalValueInEth = _getAvsTokenValuesInEth(
            _tokenIndices,
            _amounts
        );

        assertEq(lrtSquare.totalAssetsValueInEth(), totalValueInEth);
    }

    function _deposit(
        address[] memory _tokens,
        uint256[] memory _amounts,
        address _receiver
    ) internal {
        address[] memory depositors = new address[](1);
        depositors[0] = alice;
        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;
        _setDepositors(depositors, isDepositor, hex"");

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
        lrtSquare.deposit(_tokens, _amounts, _receiver);
        vm.stopPrank();
    }
}
