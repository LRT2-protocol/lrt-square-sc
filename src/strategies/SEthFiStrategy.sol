// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BaseStrategy} from "./BaseStrategy.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";

interface ITellerWithMultiAssetSupport {
    function deposit(ERC20 depositAsset, uint256 depositAmount, uint256 minimumMint) external payable returns (uint256 shares);
}

contract SEthFiStrategy is BaseStrategy {
    using Math for uint256;
    using SafeERC20 for ERC20;

    ITellerWithMultiAssetSupport public constant S_ETHFI_TELLER = ITellerWithMultiAssetSupport(0xe2acf9f80a2756E51D1e53F9f41583C84279Fb1f);
    ERC20 public constant S_ETHFI = ERC20(0x86B5780b606940Eb59A062aA85a07959518c0161);
    ERC20 public constant ETHFI = ERC20(0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB);

    constructor (address _priceProvider) BaseStrategy(_priceProvider) {}

    function _deposit(address token, uint256 amount, uint256 maxSlippageInBps) internal override {
        uint256 minReturn = sEthFiForEthFi(amount).mulDiv(HUNDRED_PERCENT_IN_BPS - maxSlippageInBps, HUNDRED_PERCENT_IN_BPS);
        if (minReturn == 0) revert MinReturnCannotBeZero();

        uint256 balBefore = S_ETHFI.balanceOf(address(this));
        
        ETHFI.forceApprove(address(S_ETHFI), amount);
        S_ETHFI_TELLER.deposit(ERC20(token), amount, minReturn);
        
        uint256 balAfter = S_ETHFI.balanceOf(address(this));
        if (balAfter - balBefore < minReturn) revert ReturnLessThanMinReturn();

        emit DepositToStrategy(token, amount, address(S_ETHFI), balAfter - balBefore);
    }

    function sEthFiForEthFi(uint256 amount) internal view returns (uint256) {
        uint256 ethFiPrice = priceProvider.getPriceInEth(address(ETHFI));
        uint256 sEthFiPrice = priceProvider.getPriceInEth(address(S_ETHFI));

        return amount.mulDiv(ethFiPrice, sEthFiPrice);
    }

    function returnToken() external pure override returns (address) {
        return address(ETHFI);
    }
}