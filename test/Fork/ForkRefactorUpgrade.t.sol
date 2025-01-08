// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Utils} from "../Utils.sol";
import {IKING} from "../../src/interfaces/IKING.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PriceProvider} from "../../src/PriceProvider.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {KINGStorage, Governable} from "../../src/KING/KINGStorage.sol";
import {KINGAdmin} from "../../src/KING/KINGAdmin.sol";
import {KINGInitializer} from "../../src/KING/KINGInitializer.sol";
import {KINGCore} from "../../src/KING/KINGCore.sol";

contract ForkKINGSqauredRefactorTest is Utils {
    using SafeERC20 for IERC20;

    IKING king = IKING(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);
    uint256 tvl;
    address rebalancer;

    function setUp() public {
        string memory mainnet = "https://eth-pokt.nodies.app";
        vm.createSelectFork(mainnet);

        (tvl, ) = king.tvl();
        rebalancer = king.rebalancer();

        address kingCoreImpl = address(new KINGCore());
        address kingAdminImpl = address(new KINGAdmin());

        vm.startPrank(king.governor());
        KINGCore(address(king)).upgradeToAndCall(kingCoreImpl, "");
        KINGCore(address(king)).setAdminImpl(kingAdminImpl);
        vm.stopPrank();
    }

    function test_Deploy() public view {
        (uint256 tvlFromNewContract, ) = king.tvl();
        assertEq(tvl, tvlFromNewContract);

        assertEq(rebalancer, king.rebalancer());
    }
}