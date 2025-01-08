// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {KINGTestSetup, IKING, IERC20, SafeERC20} from "./KINGSetup.t.sol";
import {BucketLimiter} from "../../src/libraries/BucketLimiter.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Governable} from "../../src/governance/Governable.sol";

contract KINGRateLimitTest is KINGTestSetup {
    using Math for uint256;

    uint256 initialDeposit = 100 ether;
    IKING.RateLimit rateLimit;
    
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
        tokens[0].approve(address(king), initialDeposit);
        assetIndices.push(0);
        assets.push(address(tokens[0]));
        amounts.push(initialDeposit);

        (uint256 sharesToMint, uint256 feeForDeposit) = king.previewDeposit(assets, amounts);
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
        king.deposit(assets, amounts, merkleDistributor);
        // 10 ether KING == {tokens[0]: 100 ether}

        (uint256 tvl, ) = king.tvl();
        assertApproxEqAbs(
            tvl,
            (amounts[0] * tokenPrices[0]) / 1 ether,
            1
        );
        assertEq(
            king.totalSupply(),
            100 * priceProvider.getPriceInEth(address(tokens[0]))
        ); // initial mint
        vm.stopPrank();

        rateLimit = king.getRateLimit();
    }

    function test_CanMintUpToRateLimit() public {
        uint256 amountEqualToTheRemaining = uint256(rateLimit.limit.remaining).mulDiv(1 ether, tokenPrices[0]);
        vm.startPrank(owner);
        tokens[0].approve(address(king), amountEqualToTheRemaining);
        amounts[0] = amountEqualToTheRemaining;

        uint256 totalValueInEthAfterDeposit = _getTokenValuesInEth(
            assetIndices,
            amounts
        );
        uint256 expectedSharesAfterDeposit = totalValueInEthAfterDeposit;
        uint256 fee = expectedSharesAfterDeposit.mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        expectedSharesAfterDeposit -= fee;

        vm.expectEmit(true, true, true, true);
        emit IKING.Deposit(
            owner,
            merkleDistributor,
            expectedSharesAfterDeposit,
            fee,
            assets,
            amounts
        );
        king.deposit(assets, amounts, merkleDistributor);
    }

    function test_CannotMintMoreThanRateLimit() public {
        uint256 amountGreaterThanCapacity = initialDeposit * rateLimit.limit.capacity / king.HUNDRED_PERCENT_LIMIT() + 1e12;
        vm.startPrank(owner);
        tokens[0].approve(address(king), amountGreaterThanCapacity);
        amounts[0] = amountGreaterThanCapacity;

        vm.expectRevert(IKING.RateLimitExceeded.selector);
        king.deposit(assets, amounts, merkleDistributor);
    }

    function test_BucketRefills() public {
        uint256 amountEqualToTheRemaining = uint256(rateLimit.limit.remaining).mulDiv(1 ether, tokenPrices[0]);
        vm.startPrank(owner);
        tokens[0].approve(address(king), amountEqualToTheRemaining);
        amounts[0] = amountEqualToTheRemaining;

        uint256 totalValueInEthAfterDeposit = _getTokenValuesInEth(
            assetIndices,
            amounts
        );
        uint256 expectedSharesAfterDeposit = totalValueInEthAfterDeposit;
        uint256 depositFee = expectedSharesAfterDeposit.mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        expectedSharesAfterDeposit -= depositFee;

        vm.expectEmit(true, true, true, true);
        emit IKING.Deposit(
            owner,
            merkleDistributor,
            expectedSharesAfterDeposit,
            depositFee,
            assets,
            amounts
        );
        king.deposit(assets, amounts, merkleDistributor);

        rateLimit = king.getRateLimit();

        assertEq(rateLimit.limit.remaining, 0);

        uint64 timePeriod = 10;
        uint256 expectedRefillAmtInTimePeriod = 10 * rateLimit.limit.refillRate;
        
        vm.warp(block.timestamp + timePeriod);
        rateLimit = king.getRateLimit();

        assertEq(rateLimit.limit.remaining, expectedRefillAmtInTimePeriod);
    }

    function test_CanChangeRateLimitTimePeriod() public {
        uint64 newTimePeriod = 2 * 3600;
        _setRateLimitTimePeriod(newTimePeriod, hex"");

        assertEq(king.getRateLimit().timePeriod, newTimePeriod);
    }

    function test_OnlyGovernorCanSetRateLimitTimePeriod() public {
        uint64 newTimePeriod = 2 * 3600;
        address notGovernor = makeAddr("notGovernor");
        vm.prank(notGovernor);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        king.setRateLimitTimePeriod(newTimePeriod);
    }

    function test_CanChangeRateLimitRefillRate() public {
        uint64 newRate = 1000;
        _setRateLimitRefillRate(newRate, hex"");

        assertEq(king.getRateLimit().limit.refillRate, newRate);
    }

    function test_OnlyGovernorCanChangeRateLimitRefillRate() public {
        uint64 newRate = 1000;

        address notGovernor = makeAddr("notGovernor");
        vm.prank(notGovernor);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        king.setRefillRatePerSecond(newRate);
    }


    function test_CanChangePercentageRateLimit() public {
        uint64 newPercentage = 100_000_000_000;
        _setPercentageRateLimit(newPercentage, hex"");

        assertEq(king.getRateLimit().percentageLimit, newPercentage);
    }

    function test_OnlyGovernorCanChangePercentageRateLimit() public {
        uint64 newPercentage = 100_000_000_000;

        address notGovernor = makeAddr("notGovernor");
        vm.prank(notGovernor);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        king.setPercentageRateLimit(newPercentage);
    }

    function test_CanChangeRateLimitConfig() public {
        uint64 newTimePeriod = 2 * 3600;
        uint64 newRate = 1000;
        uint64 newPercentage = 100_000_000_000;

        _setRateLimitConfig(newPercentage, newTimePeriod, newRate, hex"");

        assertEq(king.getRateLimit().percentageLimit, newPercentage);
        assertEq(king.getRateLimit().limit.refillRate, newRate);
        assertEq(king.getRateLimit().timePeriod, newTimePeriod);
    }

    function test_OnlyGovernorCanChangeRateLimitConfig() public {
        uint64 newTimePeriod = 2 * 3600;
        uint64 newRate = 1000;
        uint64 newPercentage = 100_000_000_000;

        address notGovernor = makeAddr("notGovernor");
        vm.prank(notGovernor);
        vm.expectRevert(Governable.OnlyGovernor.selector);
        king.setRateLimitConfig(newPercentage, newTimePeriod, newRate);
    }

    function test_CannotPrankTheRateLimit() public {
        uint256 amountEqualToTheRemaining = uint256(rateLimit.limit.remaining).mulDiv(1 ether, tokenPrices[0]);

        uint256 depositAmt = amountEqualToTheRemaining / 2; 

        vm.startPrank(owner);
        tokens[0].approve(address(king), depositAmt);
        amounts[0] = depositAmt;
        king.deposit(assets, amounts, merkleDistributor);

        rateLimit = king.getRateLimit();

        assertEq(rateLimit.limit.remaining, uint256(depositAmt).mulDiv(tokenPrices[0], 1 ether));

        depositAmt = depositAmt / 2; 
        tokens[0].approve(address(king), depositAmt);
        amounts[0] = depositAmt;
        king.deposit(assets, amounts, merkleDistributor);

        rateLimit = king.getRateLimit();
        assertEq(rateLimit.limit.remaining, uint256(depositAmt).mulDiv(tokenPrices[0], 1 ether));
        vm.stopPrank();
    }
}