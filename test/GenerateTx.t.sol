// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {GnosisHelpers} from "../utils/GnosisHelpers.sol";
import {LRTSquaredCore} from "../src/LRTSquared/LRTSquaredCore.sol";
import {LRTSquaredAdmin} from "../src/LRTSquared/LRTSquaredAdmin.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract GenerateTx is GnosisHelpers {
    address lrtSquare = 0x8F08B70456eb22f6109F57b8fafE862ED28E6040;
    address lrtSquareCoreImpl = 0x8F08B70456eb22f6109F57b8fafE862ED28E6040;
    address lrtSquareAdminImpl = 0x8F08B70456eb22f6109F57b8fafE862ED28E6040;

    function test_GenerateTx() public {
        _output_schedule_txn(
            lrtSquare, 
            abi.encodeWithSelector(
                UUPSUpgradeable(lrtSquare).upgradeToAndCall.selector,
                lrtSquareCoreImpl,
                hex""
            )
        );

        vm.warp(block.timestamp + 1);
        _output_schedule_txn(
            lrtSquare, 
            abi.encodeWithSelector(
                LRTSquaredCore(lrtSquare).setAdminImpl.selector,
                lrtSquareAdminImpl
            )
        );
    }
}