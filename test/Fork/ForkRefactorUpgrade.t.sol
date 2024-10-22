// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Utils} from "../Utils.sol";
import {ILRTSquared} from "../../src/interfaces/ILRTSquared.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PriceProvider} from "../../src/PriceProvider.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {LRTSquaredStorage, Governable} from "../../src/LRTSquared/LRTSquaredStorage.sol";
import {LRTSquaredAdmin} from "../../src/LRTSquared/LRTSquaredAdmin.sol";
import {LRTSquaredInitializer} from "../../src/LRTSquared/LRTSquaredInitializer.sol";
import {LRTSquaredCore} from "../../src/LRTSquared/LRTSquaredCore.sol";

contract ForkLRTSqauredRefactorTest is Utils {
    using SafeERC20 for IERC20;

    ILRTSquared lrtSquared = ILRTSquared(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);
    uint256 tvl;
    address rebalancer;

    function setUp() public {
        string memory mainnet = "https://eth-pokt.nodies.app";
        vm.createSelectFork(mainnet);

        (tvl, ) = lrtSquared.tvl();
        rebalancer = lrtSquared.rebalancer();

        address lrtSquaredCoreImpl = address(new LRTSquaredCore());
        address lrtSquaredAdminImpl = address(new LRTSquaredAdmin());

        vm.startPrank(lrtSquared.governor());
        LRTSquaredCore(address(lrtSquared)).upgradeToAndCall(lrtSquaredCoreImpl, "");
        LRTSquaredCore(address(lrtSquared)).setAdminImpl(lrtSquaredAdminImpl);
        vm.stopPrank();
    }

    function test_Deploy() public view {
        (uint256 tvlFromNewContract, ) = lrtSquared.tvl();
        assertEq(tvl, tvlFromNewContract);

        assertEq(rebalancer, lrtSquared.rebalancer());
    }
}