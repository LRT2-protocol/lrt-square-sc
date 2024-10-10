// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IPriceProvider {
    /// @notice Get the price of the token in ETH (18 decimals) for the token amount = 1 * 10 ** token.decimals()
    function getPriceInEth(address token) external view returns (uint256);

    /// @notice Get the decimals of the price provider (6 decimals)
    function decimals() external pure returns (uint8);

    /// @notice Get the price of ETH in USD
    function getEthUsdPrice() external view returns (uint256, uint8);
}
