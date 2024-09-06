// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IPriceProvider} from "src/interfaces/IPriceProvider.sol";

contract MockPriceProvider is IPriceProvider {
    mapping(address token => uint256 price) private _price;

    constructor() {}

    function getPriceInEth(
        address token
    ) external view override returns (uint256) {
        return _price[token];
    }

    function setPrice(address token, uint256 price) external {
        _price[token] = price;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}
