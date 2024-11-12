// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BaseStrategy} from "../strategies/BaseStrategy.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";

interface ITellerWithMultiAssetSupport {
    function deposit(ERC20 depositAsset, uint256 depositAmount, uint256 minimumMint) external payable returns (uint256 shares);
}

// Return token is address(0)
contract BadStrategyWithReturnTokenZero is BaseStrategy {
    using Math for uint256;
    using SafeERC20 for ERC20;

    ITellerWithMultiAssetSupport public constant E_EIGEN_TELLER =
        ITellerWithMultiAssetSupport(
            0x63b2B0528376d1B34Ed8c9FF61Bd67ab2C8c2Bb0
        );
    ERC20 public constant E_EIGEN =
        ERC20(0xE77076518A813616315EaAba6cA8e595E845EeE9);
    ERC20 public constant EIGEN =
        ERC20(0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83);

    constructor(address _priceProvider) BaseStrategy(_priceProvider) {}

    function _deposit(
        address token,
        uint256 amount,
        uint256 maxSlippageInBps
    ) internal override {
        uint256 minReturn = eEigenForEigen(amount).mulDiv(
            HUNDRED_PERCENT_IN_BPS - maxSlippageInBps,
            HUNDRED_PERCENT_IN_BPS
        );
        if (minReturn == 0) revert MinReturnCannotBeZero();

        uint256 balBefore = E_EIGEN.balanceOf(address(this));

        EIGEN.forceApprove(address(E_EIGEN), amount);
        E_EIGEN_TELLER.deposit(ERC20(token), amount, minReturn);

        uint256 balAfter = E_EIGEN.balanceOf(address(this));
        if (balAfter - balBefore < minReturn) revert ReturnLessThanMinReturn();

        emit DepositToStrategy(
            token,
            amount,
            address(E_EIGEN),
            balAfter - balBefore
        );
    }

    function eEigenForEigen(uint256 amount) internal view returns (uint256) {
        uint256 eigenPrice = priceProvider.getPriceInEth(address(EIGEN));
        uint256 eEigenPrice = priceProvider.getPriceInEth(address(E_EIGEN));

        return amount.mulDiv(eigenPrice, eEigenPrice);
    }

    function returnToken() external pure override returns (address) {
        return address(0);
    }
}