// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, IERC20, SafeERC20} from "./LRTSquaredSetup.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LRTSquaredTestAvsRewardScenario is LRTSquaredTestSetup {
    using Math for uint256;    
    
    function setUp() public override {
        super.setUp();

        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        _registerToken(address(tokens[1]), tokenPositionWeightLimits[1], hex"");

        address[] memory depositors = new address[](1);
        depositors[0] = owner;
        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;
        _setDepositors(depositors, isDepositor, hex"");
    }

    function test_avs_rewards_scenario_1() public {
        (uint256 tvl, uint256 tvlUsd) = lrtSquared.tvl();
        assertApproxEqAbs(tvl, 0, 0);

        // 1. At week-0, ether.fi receives an AVS reward 'tokens[0]'
        // Assume that only alice was holding 1 weETH
        // tokens[0] rewards amount is 100 ether
        //
        // Perform `distributeRewards`
        // - initial price of `tokens[0]` is 0.1 ether per token
        // - ether.fi sends the 'tokens[0]' rewards 100 ether to the LrtSquared vault
        // - ether.fi mints LRT^2 tokens 10 ether to MerkleDistributor. MerkleDistributor will distribute the LrtSquared to Alice

        (uint256 ethUsdPrice, uint8 ethUsdDecimals) = priceProvider.getEthUsdPrice();
        vm.prank(address(timelock));
        tokens[0].mint(owner, 100 ether);

        {
            vm.startPrank(owner);
            tokens[0].approve(address(lrtSquared), 100 ether);
            address[] memory assets = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = address(tokens[0]);
            amounts[0] = 100 ether;

            (uint256 sharesToMint, ) = lrtSquared.previewDeposit(assets, amounts);

            assertApproxEqAbs(
                sharesToMint,
                _deductFee((amounts[0] * tokenPrices[0]) / 1 ether),
                1
            ); // 100 ether * 0.1 ether / 1 ether = 10 ether worth
            lrtSquared.deposit(assets, amounts, merkleDistributor);
            // 10 ether LRT^2 == {tokens[0]: 100 ether}

            (tvl, tvlUsd) = lrtSquared.tvl();
            assertApproxEqAbs(
                tvl,
                (amounts[0] * tokenPrices[0]) / 1 ether,
                1
            );
            assertApproxEqAbs(
                tvlUsd,
                (((amounts[0] * tokenPrices[0]) / 1 ether) * ethUsdPrice) / 10 ** ethUsdDecimals,
                1
            );
            assertEq(
                lrtSquared.totalSupply(),
                100 * priceProvider.getPriceInEth(address(tokens[0]))
            ); // initial mint
            vm.stopPrank();
        }

        // 2. At week-1, ether.fi receives rewards
        // Assume that {alice, bob} were holding 1 weETH
        // tokens[0] rewards amount is 200 ether
        vm.prank(address(timelock));
        tokens[0].mint(owner, 200 ether);

        {
            vm.startPrank(owner);
            tokens[0].approve(address(lrtSquared), 200 ether);
            address[] memory assets = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = address(tokens[0]);
            amounts[0] = 200 ether;

            assertApproxEqAbs(
                _getSharesToMint(assets, amounts),
                _deductFee((amounts[0] * tokenPrices[0]) / 1 ether),
                1
            ); // 200 ether * 0.1 ether / 1 ether = 20 ether worth
            lrtSquared.deposit(assets, amounts, merkleDistributor);
            // (10 + 20) ether LRT^2 == {tokens[0]: 100 + 200 ether}
            // --> 1 ether LRT^2 == {tokens[0]: 10 ether}

            (tvl, tvlUsd) = lrtSquared.tvl();
            assertApproxEqAbs(
                tvl,
                (100 + 200) * tokenPrices[0],
                1
            );
            assertApproxEqAbs(
                tvlUsd,
                ((100 + 200) * tokenPrices[0] * ethUsdPrice) / 10 ** ethUsdDecimals,
                1
            );

            vm.stopPrank();
        }

        // 3. At week-3, ether.fi receives rewards
        // Assume that {alice, bob} were holding 1 weETH
        // tokens[0] rewards amount is 100 ether
        vm.prank(address(timelock));
        tokens[0].mint(owner, 100 ether);
        {
            vm.startPrank(owner);
            tokens[0].approve(address(lrtSquared), 100 ether);
            address[] memory assets = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = address(tokens[0]);
            amounts[0] = 100 ether;

            // lrtSquared.deposit(assets, amounts, 20 ether, merkleDistributor);
            /// @dev this will be unfair distribution to the existing holders of LRT^2
            // (10 + 20 + 20) ether LRT^2 == {tokens[0]: 100 + 200 + 100 ether}
            // After 'distributeRewards'. the value of LRT^2 token has decreased
            // - from 1 ether LRT^2 == {tokens[0]: 10 ether}
            // - to 1 ether LRT^2 == {tokens[0]: 8 ether}

            // (10 + 20 + x) ether LRT^2 == {tokens[0]: 100 + 200 + 100 ether}
            // What should be 'x' to make it fair distribution; keep the current LRT^2 token's value the same after 'distributeRewards'
            // 100 ether = (100 + 200 + 100) ether / (10 + 20 + x)
            // => x = (100 + 200 + 100) * 0.1 (price of token0) - (10 + 20) = 1
            assertApproxEqAbs(
                _getSharesToMint(assets, amounts),
                _deductFee((amounts[0] * tokenPrices[0]) / 1 ether),
                1
            ); // 100 ether * 0.1 ether / 1 ether = 10 ether worth
            lrtSquared.deposit(assets, amounts, merkleDistributor);
            // (10 + 20 + 10) ether LRT^2 == {tokens[0]: 100 + 200 + 100 ether}
            // --> 1 ether LRT^2 == {tokens[0]: 10 ether}
            (tvl, tvlUsd) = lrtSquared.tvl();
            assertApproxEqAbs(
                tvl,
                (100 + 200 + 100) * tokenPrices[0],
                1
            );
            assertApproxEqAbs(
                tvlUsd,
                ((100 + 200 + 100) * tokenPrices[0] * ethUsdPrice) / 10 ** ethUsdDecimals,
                1
            );

            vm.stopPrank();
        }

        // 4. At week-3, ether.fi receives rewards from one more AVS
        // Assume that {alice, bob} were holding 1 weETH
        // Rewards: 100 ether in `tokens[0]` and 10 * 10 ** token[1].decimals() in `token[1]`
        // Price of `tokens[0]` is 0.1 ether per token
        // Price of `tokens[1]` is 0.5 ether per token

        vm.startPrank(address(timelock));
        tokens[0].mint(owner, 100 ether);
        tokens[1].mint(owner, 10 * 10 ** tokenDecimals[1]);
        vm.stopPrank();

        {
            vm.startPrank(owner);
            tokens[0].approve(address(lrtSquared), 100 ether);
            tokens[1].approve(address(lrtSquared), 10 * 10 ** tokenDecimals[1]);

            address[] memory assets = new address[](2);
            uint256[] memory amounts = new uint256[](2);
            assets[0] = address(tokens[0]);
            assets[1] = address(tokens[1]);
            amounts[0] = 100 ether;
            amounts[1] = 10 * 10 ** tokenDecimals[1];

            // We must ensure that the value per LRT^2 token remains the same before/after the deposit of AVS rewards + miting new shares
            //
            // Here's the breakdown using actual values:
            // Currently:
            // - the vault contract currently has 400 token0
            // - the token0 is worth 0.1 ether each
            // - therefore, the vault has 40 eth worth of token0
            // Newly:
            // - we add 100 token0 (10 ether worth) and 10 token1 (5 ether worth) to the vault
            // - we mint new shares equivalent to the proportion of the increase
            // To maintain the value of each share, new shares equivalent to the proportion of the increase must be minted.
            // Execute 'distributeRewards' operation
            assertApproxEqAbs(
                _getSharesToMint(assets, amounts),
                _deductFee((amounts[0] * tokenPrices[0]) /
                    10 ** tokenDecimals[0] +
                    (amounts[1] * tokenPrices[1]) /
                    10 ** tokenDecimals[1]),
                1
            ); // 100 * 0.1 ether + 10 * 0.5 ether = 15 ether worth
            lrtSquared.deposit(assets, amounts, merkleDistributor);

            (tvl, tvlUsd) = lrtSquared.tvl();
            assertApproxEqAbs(
                tvl,
                (100 + 200 + 100 + 100) * tokenPrices[0] + 10 * tokenPrices[1],
                1
            );
            assertApproxEqAbs(
                tvlUsd,
                (((100 + 200 + 100 + 100) * tokenPrices[0] + 10 * tokenPrices[1]) * ethUsdPrice) / 10 ** ethUsdDecimals,
                1
            );
            vm.stopPrank();
        }
    }

    function _deductFee(uint256 amount) internal view returns (uint256) {
        return amount - amount.mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
    }

    function _getSharesToMint(
        address[] memory assets, 
        uint256[] memory amounts
    ) internal view returns (uint256) {
        (uint256 sharesToMint, ) = lrtSquared.previewDeposit(assets, amounts);
        return sharesToMint;
    }
}
