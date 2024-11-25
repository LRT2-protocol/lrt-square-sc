// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, ILRTSquared, IERC20, SafeERC20} from "./LRTSquaredSetup.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LRTSquaredBasicsTest is LRTSquaredTestSetup {
    using SafeERC20 for IERC20;
    using Math for uint256;

    function setUp() public override {
        super.setUp();

        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        _registerToken(address(tokens[1]), tokenPositionWeightLimits[1], hex"");
        _registerToken(address(tokens[2]), tokenPositionWeightLimits[2], hex"");
    }

    function test_Deploy() public {
        assertEq(lrtSquared.isTokenRegistered(address(tokens[0])), true);
        assertEq(lrtSquared.isTokenRegistered(address(tokens[1])), true);
        assertEq(lrtSquared.isTokenRegistered(address(tokens[2])), true);

        assertEq(lrtSquared.isTokenWhitelisted(address(tokens[0])), true);
        assertEq(lrtSquared.isTokenWhitelisted(address(tokens[1])), true);
        assertEq(lrtSquared.isTokenWhitelisted(address(tokens[2])), true);

        assertEq(lrtSquared.totalSupply(), 0);
        (uint256 tvl, uint256 tvlUsd) = lrtSquared.tvl();
        assertEq(tvl, 0);
        assertEq(tvlUsd, 0);

        vm.expectRevert(ILRTSquared.TotalSupplyZero.selector);
        lrtSquared.assetsForVaultShares(1);

        address[] memory _tokens = new address[](3);
        _tokens[0] = address(tokens[0]);
        _tokens[1] = address(tokens[1]);
        _tokens[2] = address(tokens[2]);

        uint256[] memory _amounts = new uint256[](3);

        (
            address[] memory _tokensFromContract,
            uint256[] memory _amountsFromContract
        ) = lrtSquared.totalAssets();
        assertEq(_tokens, _tokensFromContract);
        assertEq(_amounts, _amountsFromContract);
    }

    function test_TokenValuesInEth() public view {
        uint256[] memory _tokenIndices = new uint256[](2);
        _tokenIndices[0] = 0;
        _tokenIndices[1] = 1;

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[_tokenIndices[0]]);
        _tokens[1] = address(tokens[_tokenIndices[1]]);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 1 * 10 ** tokenDecimals[_tokenIndices[0]];
        _amounts[1] = 5 * 10 ** tokenDecimals[_tokenIndices[1]];

        uint256 expectedTotal = _getTokenValuesInEth(
            _tokenIndices,
            _amounts
        );

        assertEq(
            lrtSquared.getTokenValuesInEth(_tokens, _amounts),
            expectedTotal
        );
    }

    function test_CannotGetTokenValuesInEthIfArrayLengthMismatch() public {
        address[] memory _tokens = new address[](2);
        _tokens[0] = address(tokens[0]);
        _tokens[1] = address(tokens[1]);

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 1 * 10 ** tokenDecimals[0];

        vm.expectRevert(ILRTSquared.ArrayLengthMismatch.selector);
        lrtSquared.getTokenValuesInEth(_tokens, _amounts);
    }

    function test_CannotGetTokenValuesInEthIfTokenNotRegistered() public {
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(address(1));

        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 1 ether;

        vm.expectRevert(ILRTSquared.TokenNotRegistered.selector);
        lrtSquared.getTokenValuesInEth(_tokens, _amounts);
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

        uint256 totalValueInEth = _getTokenValuesInEth(
            _tokenIndices,
            _amounts
        );
        uint256 expectedShares = _getSharesForEth(totalValueInEth);

        uint256 depositFee = expectedShares.mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        expectedShares -= depositFee;

        (uint256 sharesToMint, uint256 feeForDeposit) = lrtSquared.previewDeposit(_tokens, _amounts);

        assertApproxEqAbs(
            sharesToMint,
            expectedShares,
            1
        );
        assertApproxEqAbs(
            depositFee,
            feeForDeposit,
            1
        );

        _deposit(_tokens, _amounts, alice);

        _amounts[0] = 10 * 10 ** tokenDecimals[_tokenIndices[0]];
        _amounts[1] = 500 * 10 ** tokenDecimals[_tokenIndices[1]];

        uint256 totalValueInEthAfterDeposit = _getTokenValuesInEth(
            _tokenIndices,
            _amounts
        );
        uint256 expectedSharesAfterDeposit = _getSharesForEth(
            totalValueInEthAfterDeposit
        );
        depositFee = expectedSharesAfterDeposit.mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        expectedSharesAfterDeposit -= depositFee;

        (sharesToMint, feeForDeposit) = lrtSquared.previewDeposit(_tokens, _amounts);


        assertApproxEqAbs(
            sharesToMint,
            expectedSharesAfterDeposit,
            1
        );

        assertApproxEqAbs(
            depositFee,
            feeForDeposit,
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
        uint256 totalValueInEth = _getTokenValuesInEth(
            _tokenIndices,
            _amounts
        );
        uint256 sharesMinted = _getSharesForEth(totalValueInEth);
        uint256 fee = sharesMinted.mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        sharesMinted -= fee;

        uint256 assetOfAliceInToken0 = _getAssetForVaultShares(
            sharesMinted,
            _tokens[0]
        );
        uint256 assetOfAliceInToken1 = _getAssetForVaultShares(
            sharesMinted,
            _tokens[1]
        );

        assertEq(lrtSquared.assetOf(alice, _tokens[0]), assetOfAliceInToken0);
        assertEq(lrtSquared.assetOf(alice, _tokens[1]), assetOfAliceInToken1);
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
        ) = lrtSquared.assetsOf(alice);

        address[] memory _expectedTokens = new address[](3);
        _expectedTokens[0] = address(tokens[_tokenIndices[0]]);
        _expectedTokens[1] = address(tokens[_tokenIndices[1]]);
        _expectedTokens[2] = address(tokens[2]);

        uint256[] memory _expectedAmounts = new uint256[](3);
        _expectedAmounts[0] = 1 * 10 ** tokenDecimals[_tokenIndices[0]];
        _expectedAmounts[1] = 5 * 10 ** tokenDecimals[_tokenIndices[1]];
        _expectedAmounts[2] = 0;

        // Deduct the fee from here because it was already deducted when user deposited
        _expectedAmounts[0] -= _expectedAmounts[0].mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        _expectedAmounts[1] -= _expectedAmounts[1].mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        _expectedAmounts[2] -= _expectedAmounts[2].mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);

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
        uint256 totalValueInEth = _getTokenValuesInEth(
            _tokenIndices,
            _amounts
        );

        (uint256 tvl, uint256 tvlUsd) = lrtSquared.tvl();
        (uint256 ethUsdPrice, uint8 ethUsdDecimals) = priceProvider.getEthUsdPrice();
        assertEq(tvl, totalValueInEth);
        assertEq(tvlUsd, (totalValueInEth * ethUsdPrice) / 10 ** ethUsdDecimals);
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
                address(lrtSquared),
                _amounts[i]
            );
            unchecked {
                ++i;
            }
        }
        lrtSquared.deposit(_tokens, _amounts, _receiver);
        vm.stopPrank();
    }
}
