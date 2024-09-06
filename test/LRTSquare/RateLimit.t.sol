// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LrtSquare, IERC20, SafeERC20} from "./LRTSquareSetup.t.sol";
import {BucketLimiter} from "../../src/libraries/BucketLimiter.sol";

contract LRTSquareRateLimitTest is LRTSquareTestSetup {
    uint256 initialDeposit = 100 ether;
    BucketLimiter.Limit limit;
    
    uint256[] assetIndices;
    address[] assets;
    uint256[] amounts;

    function setUp() public override {
        super.setUp();

        _registerToken(address(tokens[0]), tokenMaxPercentageValues[0], hex"");
        _registerToken(address(tokens[1]), tokenMaxPercentageValues[1], hex"");

        address[] memory depositors = new address[](1);
        depositors[0] = owner;
        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;
        _setDepositors(depositors, isDepositor, hex"");

        vm.prank(address(timelock));
        tokens[0].mint(owner, 1000000 ether);

        vm.startPrank(owner);
        tokens[0].approve(address(lrtSquare), initialDeposit);
        assetIndices.push(0);
        assets.push(address(tokens[0]));
        amounts.push(initialDeposit);

        assertApproxEqAbs(
            lrtSquare.previewDeposit(assets, amounts),
            (amounts[0] * tokenPrices[0]) / 1 ether,
            1
        ); // 100 ether * 0.1 ether / 1 ether = 10 ether worth
        lrtSquare.deposit(assets, amounts, merkleDistributor);
        // 10 ether LRT^2 == {tokens[0]: 100 ether}

        assertApproxEqAbs(
            lrtSquare.totalAssetsValueInEth(),
            (amounts[0] * tokenPrices[0]) / 1 ether,
            1
        );
        assertEq(
            lrtSquare.totalSupply(),
            100 * priceProvider.getPriceInEth(address(tokens[0]))
        ); // initial mint
        vm.stopPrank();

        limit = lrtSquare.getRateLimit();
    }

    function test_CanMintUpToRateLimit() public {
        uint256 amountEqualToTheCapacity = initialDeposit * limit.capacity / lrtSquare.HUNDRED_PERCENT_LIMIT();
        vm.startPrank(owner);
        tokens[0].approve(address(lrtSquare), amountEqualToTheCapacity);
        amounts[0] = amountEqualToTheCapacity;

        uint256 totalValueInEthAfterDeposit = _getAvsTokenValuesInEth(
            assetIndices,
            amounts
        );
        uint256 expectedSharesAfterDeposit = totalValueInEthAfterDeposit;

        vm.expectEmit(true, true, true, true);
        emit LrtSquare.Deposit(
            owner,
            merkleDistributor,
            expectedSharesAfterDeposit,
            assets,
            amounts
        );
        lrtSquare.deposit(assets, amounts, merkleDistributor);
    }

    function test_CannotMintMoreThanRateLimit() public {
        uint256 amountGreaterThanCapacity = initialDeposit * limit.capacity / lrtSquare.HUNDRED_PERCENT_LIMIT() + 1e12;
        vm.startPrank(owner);
        tokens[0].approve(address(lrtSquare), amountGreaterThanCapacity);
        amounts[0] = amountGreaterThanCapacity;

        vm.expectRevert(LrtSquare.RateLimitExceeded.selector);
        lrtSquare.deposit(assets, amounts, merkleDistributor);
    }

    function test_BucketRefills() public {
        uint256 amountEqualToTheCapacity = initialDeposit * limit.capacity / lrtSquare.HUNDRED_PERCENT_LIMIT();
        vm.startPrank(owner);
        tokens[0].approve(address(lrtSquare), amountEqualToTheCapacity);
        amounts[0] = amountEqualToTheCapacity;

        uint256 totalValueInEthAfterDeposit = _getAvsTokenValuesInEth(
            assetIndices,
            amounts
        );
        uint256 expectedSharesAfterDeposit = totalValueInEthAfterDeposit;

        vm.expectEmit(true, true, true, true);
        emit LrtSquare.Deposit(
            owner,
            merkleDistributor,
            expectedSharesAfterDeposit,
            assets,
            amounts
        );
        lrtSquare.deposit(assets, amounts, merkleDistributor);

        limit = lrtSquare.getRateLimit();

        assertEq(limit.remaining, 0);

        uint64 timePeriod = 10;
        uint256 expectedRefillAmtInTimePeriod = 10 * limit.refillRate;
        
        vm.warp(block.timestamp + timePeriod);
        limit = lrtSquare.getRateLimit();

        assertEq(limit.remaining, expectedRefillAmtInTimePeriod);
    }

    function test_CanChangeRateLimitCapacity() public {
        uint64 newCapacity = 1000000;
        _setRateLimitCapacity(newCapacity, hex"");

        assertEq(lrtSquare.getRateLimit().capacity, newCapacity);
    }

    function test_CanChangeRateLimitRefillRate() public {
        uint64 newRate = 1000;
        _setRateLimitRefillRate(newRate, hex"");

        assertEq(lrtSquare.getRateLimit().refillRate, newRate);
    }

    function test_CannotSetRateLimitRefillRateMoreThanCapacity() public {
        uint64 newRate = limit.capacity + 1;
        _setRateLimitRefillRate(newRate, abi.encodeWithSelector(LrtSquare.RateLimitRefillRateCannotBeGreaterThanCapacity.selector));
    }
}