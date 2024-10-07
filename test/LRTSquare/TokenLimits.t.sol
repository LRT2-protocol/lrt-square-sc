// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LRTSquare, IERC20, SafeERC20} from "./LRTSquareSetup.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LRTSquareTokenLimitTest is LRTSquareTestSetup {
    using Math for uint256;

    uint256 initialDepositToken0 = 100 ether;
    
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
        tokens[0].approve(address(lrtSquare), initialDepositToken0);
        assetIndices.push(0);
        assets.push(address(tokens[0]));
        amounts.push(initialDepositToken0);

        (uint256 sharesToMint, uint256 feeForDeposit) = lrtSquare.previewDeposit(assets, amounts);
        uint256 expectedShares = (amounts[0] * tokenPrices[0]) / 1 ether;
        uint256 fee = expectedShares.mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        expectedShares -= fee;

        assertApproxEqAbs(
            sharesToMint,
            expectedShares,
            1
        ); 
        assertApproxEqAbs(
            feeForDeposit,
            fee,
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
    }

    function test_SetMaxPercentageForATokenInVault() public {
        (,,uint64 maxPercentageBefore) = lrtSquare.tokenInfos(address(tokens[0]));
        assertEq(maxPercentageBefore, lrtSquare.HUNDRED_PERCENT_LIMIT());

        // 1 gwei is 100% 
        uint64 newMaxPercentage = 0.1 gwei; // 10%
        _updateTokenPositionWeightLimit(address(tokens[0]), newMaxPercentage, hex"");

        ( , , uint64 maxPercentageAfter) = lrtSquare.tokenInfos(address(tokens[0]));
        assertEq(maxPercentageAfter, newMaxPercentage);
    }

    function test_CannotSetMaxPercentageForATokenIfTokenIsAddressZero() public {
        _updateTokenPositionWeightLimit(
            address(0), 
            1, 
            abi.encodeWithSelector(LRTSquare.InvalidValue.selector)
        );
    }

    function test_CannotSetMaxPercentageForATokenIfTokenNotRegistered() public {
        _updateTokenPositionWeightLimit(
            address(1), 
            1, 
            abi.encodeWithSelector(LRTSquare.TokenNotRegistered.selector)
        );
    }

    function test_CannotSetMaxPercentageForATokenIfPercentageIsGreaterThanHundred() public {
        _updateTokenPositionWeightLimit(
            address(tokens[0]), 
            lrtSquare.HUNDRED_PERCENT_LIMIT() + 1, 
            abi.encodeWithSelector(LRTSquare.WeightLimitCannotBeGreaterThanHundred.selector)
        );
    }

    function test_CanDepositUpToMaxPercentage() public {
        vm.prank(address(timelock));
        tokens[1].mint(owner, 1000000 ether);

        uint64 newPercentageForToken0 = 0.5 gwei; // 50% of vault total value max
        uint64 newPercentageForToken1 = 0.5 gwei; // 50% of vault total value max

        _updateTokenPositionWeightLimit(address(tokens[0]), newPercentageForToken0, hex"");
        _updateTokenPositionWeightLimit(address(tokens[1]), newPercentageForToken1, hex"");

        // currently in the setup, the vault contains a 100% of `tokens[0]` 
        uint256 currentTotalValueInVault = (amounts[0] * tokenPrices[0]) / 1 ether; // 100% value

        // breaking into 50/50, we need to supply equal value of `tokens[1]` so that both are 50/50
        uint256 amountToken1 = (currentTotalValueInVault * 10 ** tokenDecimals[1]) / tokenPrices[1];        

        address[] memory assetsToSupply = new address[](1);
        assetsToSupply[0] = address(tokens[1]);
        uint256[] memory amountsToSupply = new uint256[](1);
        amountsToSupply[0] = amountToken1;
        
        vm.startPrank(owner);
        tokens[1].approve(address(lrtSquare), initialDepositToken0);
        lrtSquare.deposit(assetsToSupply, amountsToSupply, merkleDistributor);
        vm.stopPrank(); 

        ( , uint64[] memory percentages) = lrtSquare.positionWeightLimit();
        assertEq(percentages[0], 0.5 gwei);
        assertEq(percentages[1], 0.5 gwei);
    }

    function test_CannotDepositOverMaxPercentage() public {
        vm.prank(address(timelock));
        tokens[1].mint(owner, 1000000 ether);

        uint64 newPercentageForToken0 = 0.5 gwei; // 50% of vault total value max
        uint64 newPercentageForToken1 = 0.5 gwei; // 50% of vault total value max

        _updateTokenPositionWeightLimit(address(tokens[0]), newPercentageForToken0, hex"");
        _updateTokenPositionWeightLimit(address(tokens[1]), newPercentageForToken1, hex"");

        // currently in the setup, the vault contains a 100% of `tokens[0]` 
        uint256 currentTotalValueInVault = (amounts[0] * tokenPrices[0]) / 1 ether; // 100% value

        // breaking into 50/50, we need to supply equal value of `tokens[1]` so that both are 50/50
        // we deposit 1 token less than the required amount so that it is not 50/50, token 1 becomes 51% and reverts
        uint256 amountToken1 = (currentTotalValueInVault * 10 ** tokenDecimals[1]) / tokenPrices[1] - 10 ** tokenDecimals[1];         

        address[] memory assetsToSupply = new address[](1);
        assetsToSupply[0] = address(tokens[1]);
        uint256[] memory amountsToSupply = new uint256[](1);
        amountsToSupply[0] = amountToken1;
        
        vm.startPrank(owner);
        tokens[1].approve(address(lrtSquare), initialDepositToken0);
        vm.expectRevert(LRTSquare.TokenWeightLimitBreached.selector);
        lrtSquare.deposit(assetsToSupply, amountsToSupply, merkleDistributor);
        vm.stopPrank(); 
    }
}