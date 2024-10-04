// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @notice 1Inch Pathfinder V6 implementation of the general ISwapper interface.
 * @author ether.fi [shivam@ether.fi]
 * @dev This contract is not expected to hold any funds
 * @dev It is possible that dust token amounts are left in this contract after a swap.
 * This can happen with some tokens that don't send the full transfer amount.
 * These dust amounts can build up over time and be used by anyone who calls the `swap` function.
 */
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAggregationExecutor, IOneInchRouterV6, SwapDescription} from "./interfaces/IOneInch.sol";
import {ISwapper} from "./interfaces/ISwapper.sol";
import {console} from "forge-std/console.sol";

/**
 * @title Swapper1InchV6
 * @notice 1Inch Pathfinder V6 implementation of the general ISwapper interface.
 */
contract Swapper1InchV6 is ISwapper {
    using SafeERC20 for IERC20;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /// @notice 1Inch router contract to give allowance to perform swaps
    address public immutable swapRouter;

    error ToAssetBalanceDecreased();
    error OutputLessThanMinAmount();
    error SwapFailed();

    constructor(address _swapRouter) {
        swapRouter = _swapRouter;
    }

    /**
     * @notice Strategist swaps assets sitting in the contract of the `assetHolder`.
     * @param _fromAsset The token address of the asset being sold by the vault.
     * @param _toAsset The token address of the asset being purchased by the vault.
     * @param _fromAssetAmount The amount of assets being sold by the vault.
     * @param _minToAssetAmount The minimum amount of assets to be purchased.
     * @param _data RLP encoded executer address and bytes data. This is re-encoded tx.data from 1Inch swap API
     */
    function swap(
        address _fromAsset,
        address _toAsset,
        uint256 _fromAssetAmount,
        uint256 _minToAssetAmount,
        bytes calldata _data
    ) external returns (uint256 toAssetAmount) {
        if (IERC20(_fromAsset).allowance(address(this), swapRouter) < _fromAssetAmount) 
            IERC20(_fromAsset).forceApprove(swapRouter, type(uint256).max);

        uint256 toAssetBalBefore = IERC20(_toAsset).balanceOf(msg.sender);

        (bool success, ) = swapRouter.call(_data);        
        if (!success) revert SwapFailed();

        uint256 toAssetBalAfter = IERC20(_toAsset).balanceOf(msg.sender);
        if (toAssetBalAfter < toAssetBalBefore) revert ToAssetBalanceDecreased();
        if ((toAssetBalAfter - toAssetBalBefore) < _minToAssetAmount) revert OutputLessThanMinAmount();

        return toAssetBalAfter - toAssetBalBefore;
    }
}