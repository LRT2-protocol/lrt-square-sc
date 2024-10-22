// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {GnosisHelpers} from "../../utils/GnosisHelpers.sol";
import {LRTSquared} from "../../src/LRTSquared.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract GenerateNameUpgrades is GnosisHelpers {
    address lrtSquare = 0x8F08B70456eb22f6109F57b8fafE862ED28E6040;
    address lrtSquareOldImpl = 0xa838B3D1219710F0E42d5deA26CfA2Fd5A03EC54;
    address lrtSquareWithNameFunction = 0x8F08B70456eb22f6109F57b8fafE862ED28E6040;
    
    function test_GenerateNameUpgrades() public {
        _output_schedule_txn(
            lrtSquare, 
            abi.encodeWithSelector(
                UUPSUpgradeable(lrtSquare).upgradeToAndCall.selector,
                lrtSquareWithNameFunction,
                hex""
            )
        );

        vm.warp(2);
        _output_schedule_txn(
            lrtSquare, 
            abi.encodeWithSelector(
                LRTSquared(lrtSquare).updateName.selector,
                "LRTSquared"
            )
        );

        vm.warp(3);
        _output_schedule_txn(
            lrtSquare, 
            abi.encodeWithSelector(
                UUPSUpgradeable(lrtSquare).upgradeToAndCall.selector,
                lrtSquareOldImpl,
                hex""
            )
        );

    }
}