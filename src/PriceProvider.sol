// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IPriceProvider} from "src/interfaces/IPriceProvider.sol";

contract PriceProvider is IPriceProvider {
    uint256 public price;

    constructor() {}

    function getPriceInUsd() external view override returns (uint256) {
        return price;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }
}
