// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface ISwapper {
    /**
     * @notice Strategist swaps assets sitting in the contract of the `assetHolder`
     * @param _fromAsset The token address of the asset being sold by the vault
     * @param _toAsset The token address of the asset being purchased by the vault
     * @param _fromAssetAmount The amount of assets being sold by the vault
     * @param _minToAssetAmount The minimum amount of assets to be purchased
     * @param _data Swap data
     */
    function swap(
        address _fromAsset,
        address _toAsset,
        uint256 _fromAssetAmount,
        uint256 _minToAssetAmount,
        bytes calldata _data
    ) external returns (uint256 toAssetAmount);
}