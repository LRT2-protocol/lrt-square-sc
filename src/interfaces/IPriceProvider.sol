// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPriceProvider {
    /// @notice Get the price of the token in USD (6 decimals) for the token amount = 1 * 10 ** token.decimals()
    function getPriceInUsd() external view returns (uint256);

    /// @notice Get the decimals of the price provider (6 decimals)
    function decimals() external pure returns (uint8);

    /// @notice Set the price of the token in USD (6 decimals)
    function setPrice(uint256 _price) external;
}