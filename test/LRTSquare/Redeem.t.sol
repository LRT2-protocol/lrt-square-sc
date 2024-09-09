// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquareTestSetup, LrtSquare, IERC20, SafeERC20} from "./LRTSquareSetup.t.sol";

contract LRTSquareRedeemTest is LRTSquareTestSetup {
    using SafeERC20 for IERC20;

    uint256[] _tokenIndices;
    address[] _tokens;
    uint256[] _amounts;
    uint256 sharesAlloted;

    function setUp() public override {
        super.setUp();

        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        _registerToken(address(tokens[1]), tokenPositionWeightLimits[1], hex"");
        _registerToken(address(tokens[2]), tokenPositionWeightLimits[2], hex"");

        address[] memory depositors = new address[](1);
        depositors[0] = alice;
        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;
        _setDepositors(depositors, isDepositor, hex"");

        _tokenIndices.push(0);
        _tokenIndices.push(1);
        _tokenIndices.push(2);

        _tokens.push(address(tokens[0]));
        _tokens.push(address(tokens[1]));
        _tokens.push(address(tokens[2]));

        _amounts.push(10 * 10 ** tokenDecimals[0]);
        _amounts.push(50 * 10 ** tokenDecimals[1]);
        _amounts.push(25 * 10 ** tokenDecimals[2]);

        uint256 totalValueInEthAfterDeposit = _getAvsTokenValuesInEth(
            _tokenIndices,
            _amounts
        );
        sharesAlloted = totalValueInEthAfterDeposit;

        vm.startPrank(alice);
        for (uint256 i = 0; i < _tokens.length; ) {
            deal(_tokens[i], alice, _amounts[i]);

            IERC20(_tokens[i]).safeIncreaseAllowance(
                address(lrtSquare),
                _amounts[i]
            );
            unchecked {
                ++i;
            }
        }

        vm.expectEmit(true, true, true, true);
        emit LrtSquare.Deposit(alice, alice, sharesAlloted, _tokens, _amounts);
        lrtSquare.deposit(_tokens, _amounts, alice);
        vm.stopPrank();
    }

    function test_Redeem() public {
        uint256 aliceSharesBefore = lrtSquare.balanceOf(alice);
        uint256 aliceBalToken0Before = IERC20(_tokens[0]).balanceOf(alice);
        uint256 aliceBalToken1Before = IERC20(_tokens[1]).balanceOf(alice);
        uint256 aliceBalToken2Before = IERC20(_tokens[2]).balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, true, false);
        emit LrtSquare.Redeem(alice, sharesAlloted, _tokens, _amounts);
        lrtSquare.redeem(sharesAlloted);

        uint256 aliceSharesAfter = lrtSquare.balanceOf(alice);
        uint256 aliceBalToken0After = IERC20(_tokens[0]).balanceOf(alice);
        uint256 aliceBalToken1After = IERC20(_tokens[1]).balanceOf(alice);
        uint256 aliceBalToken2After = IERC20(_tokens[2]).balanceOf(alice);

        assertEq(aliceSharesBefore, sharesAlloted);
        assertEq(aliceSharesAfter, 0);
        assertApproxEqAbs(
            aliceBalToken0After - aliceBalToken0Before,
            _amounts[0],
            10
        );
        assertApproxEqAbs(
            aliceBalToken1After - aliceBalToken1Before,
            _amounts[1],
            10
        );
        assertApproxEqAbs(
            aliceBalToken2After - aliceBalToken2Before,
            _amounts[2],
            10
        );
    }

    function test_CannotRedeemIfInsufficientShares() public {
        vm.prank(alice);
        vm.expectRevert(LrtSquare.InsufficientShares.selector);
        lrtSquare.redeem(sharesAlloted + 1);
    }
}
