// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LRTSquare, IERC20, SafeERC20} from "./LRTSquareSetup.t.sol";
import {BucketLimiter} from "../../src/libraries/BucketLimiter.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Governable} from "../../src/governance/Governable.sol";

contract LRTSquareRateLimitTest is LRTSquareTestSetup {
    using Math for uint256;

    uint256 initialDeposit = 100 ether;
    LRTSquare.RateLimit rateLimit;
    
    uint256[] assetIndices;
    address[] assets;
    uint256[] amounts;

    function setUp() public override {
        super.setUp();

        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        _registerToken(address(tokens[1]), tokenPositionWeightLimits[1], hex"");

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

        (uint256 sharesToMint, uint256 feeForDeposit) = lrtSquare.previewDeposit(assets, amounts);
        uint256 expectedShares = (amounts[0] * tokenPrices[0]) / 1 ether;
        uint256 depositFee = expectedShares.mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        expectedShares -= depositFee;

        assertApproxEqAbs(  
            sharesToMint,
            expectedShares,
            1
        ); 

        assertApproxEqAbs(  
            feeForDeposit,
            depositFee,
            1
        ); 

        // 100 ether * 0.1 ether / 1 ether = 10 ether worth
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

        rateLimit = lrtSquare.getRateLimit();
    }

    function test_CanMintUpToRateLimit() public {
        uint256 amountEqualToTheRemaining = uint256(rateLimit.limit.remaining).mulDiv(1 ether, tokenPrices[0]);
        vm.startPrank(owner);
        tokens[0].approve(address(lrtSquare), amountEqualToTheRemaining);
        amounts[0] = amountEqualToTheRemaining;

        uint256 totalValueInEthAfterDeposit = _getTokenValuesInEth(
            assetIndices,
            amounts
        );
        uint256 expectedSharesAfterDeposit = totalValueInEthAfterDeposit;
        uint256 fee = expectedSharesAfterDeposit.mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        expectedSharesAfterDeposit -= fee;

        vm.expectEmit(true, true, true, true);
        emit LRTSquare.Deposit(
            owner,
            merkleDistributor,
            expectedSharesAfterDeposit,
            fee,
            assets,
            amounts
        );
        lrtSquare.deposit(assets, amounts, merkleDistributor);
    }

    function test_CannotMintMoreThanRateLimit() public {
        uint256 amountGreaterThanCapacity = initialDeposit * rateLimit.limit.capacity / lrtSquare.HUNDRED_PERCENT_LIMIT() + 1e12;
        vm.startPrank(owner);
        tokens[0].approve(address(lrtSquare), amountGreaterThanCapacity);
        amounts[0] = amountGreaterThanCapacity;

        vm.expectRevert(LRTSquare.RateLimitExceeded.selector);
        lrtSquare.deposit(assets, amounts, merkleDistributor);
    }

    function test_BucketRefills() public {
        uint256 amountEqualToTheRemaining = uint256(rateLimit.limit.remaining).mulDiv(1 ether, tokenPrices[0]);
        vm.startPrank(owner);
        tokens[0].approve(address(lrtSquare), amountEqualToTheRemaining);
        amounts[0] = amountEqualToTheRemaining;

        uint256 totalValueInEthAfterDeposit = _getTokenValuesInEth(
            assetIndices,
            amounts
        );
        uint256 expectedSharesAfterDeposit = totalValueInEthAfterDeposit;
        uint256 depositFee = expectedSharesAfterDeposit.mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        expectedSharesAfterDeposit -= depositFee;

        vm.expectEmit(true, true, true, true);
        emit LRTSquare.Deposit(
            owner,
            merkleDistributor,
            expectedSharesAfterDeposit,
            depositFee,
            assets,
            amounts
        );
        lrtSquare.deposit(assets, amounts, merkleDistributor);

        rateLimit = lrtSquare.getRateLimit();

        assertEq(rateLimit.limit.remaining, 0);

        uint64 timePeriod = 10;
        uint256 expectedRefillAmtInTimePeriod = 10 * rateLimit.limit.refillRate;
        
        vm.warp(block.timestamp + timePeriod);
        rateLimit = lrtSquare.getRateLimit();

        assertEq(rateLimit.limit.remaining, expectedRefillAmtInTimePeriod);
    }

    function test_CanChangeRateLimitTimePeriod() public {
        uint64 newTimePeriod = 2 * 3600;
        _setRateLimitTimePeriod(newTimePeriod, hex"");

        assertEq(lrtSquare.getRateLimit().timePeriod, newTimePeriod);
    }

    function test_OnlyGovernorCanSetRateLimitTimePeriod() public {
        uint64 newTimePeriod = 2 * 3600;
        address notGovernor = makeAddr("notGovernor");
        vm.prank(notGovernor);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquare.setRateLimitTimePeriod(newTimePeriod);
    }

    function test_CanChangeRateLimitRefillRate() public {
        uint64 newRate = 1000;
        _setRateLimitRefillRate(newRate, hex"");

        assertEq(lrtSquare.getRateLimit().limit.refillRate, newRate);
    }

    function test_OnlyGovernorCanChangeRateLimitRefillRate() public {
        uint64 newRate = 1000;

        address notGovernor = makeAddr("notGovernor");
        vm.prank(notGovernor);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquare.setRefillRatePerSecond(newRate);
    }


    function test_CanChangePercentageRateLimit() public {
        uint64 newPercentage = 100_000_000_000;
        _setPercentageRateLimit(newPercentage, hex"");

        assertEq(lrtSquare.getRateLimit().percentageLimit, newPercentage);
    }

    function test_OnlyGovernorCanChangePercentageRateLimit() public {
        uint64 newPercentage = 100_000_000_000;

        address notGovernor = makeAddr("notGovernor");
        vm.prank(notGovernor);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquare.setPercentageRateLimit(newPercentage);
    }

    function test_CanChangeRateLimitConfig() public {
        uint64 newTimePeriod = 2 * 3600;
        uint64 newRate = 1000;
        uint64 newPercentage = 100_000_000_000;

        _setRateLimitConfig(newPercentage, newTimePeriod, newRate, hex"");

        assertEq(lrtSquare.getRateLimit().percentageLimit, newPercentage);
        assertEq(lrtSquare.getRateLimit().limit.refillRate, newRate);
        assertEq(lrtSquare.getRateLimit().timePeriod, newTimePeriod);
    }

    function test_OnlyGovernorCanChangeRateLimitConfig() public {
        uint64 newTimePeriod = 2 * 3600;
        uint64 newRate = 1000;
        uint64 newPercentage = 100_000_000_000;

        address notGovernor = makeAddr("notGovernor");
        vm.prank(notGovernor);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquare.setRateLimitConfig(newPercentage, newTimePeriod, newRate);
    }

    function test_CannotPrankTheRateLimit() public {
        uint256 amountEqualToTheRemaining = uint256(rateLimit.limit.remaining).mulDiv(1 ether, tokenPrices[0]);

        uint256 depositAmt = amountEqualToTheRemaining / 2; 

        vm.startPrank(owner);
        tokens[0].approve(address(lrtSquare), depositAmt);
        amounts[0] = depositAmt;
        lrtSquare.deposit(assets, amounts, merkleDistributor);

        rateLimit = lrtSquare.getRateLimit();

        assertEq(rateLimit.limit.remaining, uint256(depositAmt).mulDiv(tokenPrices[0], 1 ether));

        depositAmt = depositAmt / 2; 
        tokens[0].approve(address(lrtSquare), depositAmt);
        amounts[0] = depositAmt;
        lrtSquare.deposit(assets, amounts, merkleDistributor);

        rateLimit = lrtSquare.getRateLimit();
        assertEq(rateLimit.limit.remaining, uint256(depositAmt).mulDiv(tokenPrices[0], 1 ether));
        vm.stopPrank();
    }
}