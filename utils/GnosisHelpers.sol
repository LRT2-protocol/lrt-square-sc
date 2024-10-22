// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract GnosisHelpers is Test {
    event Transaction(address to, address target, uint256 value, bytes data);

    address constant gnosis = 0xF46D3734564ef9a5a16fC3B1216831a28f78e2B5;
    bytes32 constant predecessor = 0x0000000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant salt = 0x0000000000000000000000000000000000000000000000000000000000000000;
    uint256 constant delay = 0;

    function _output_schedule_txn(address target, bytes memory data) internal {
        string memory obj_k = "safe_txn";
        stdJson.serialize(obj_k, "to", address(gnosis));
        stdJson.serialize(obj_k, "target", address(target));
        stdJson.serialize(obj_k, "value", uint256(0));
        string memory output = stdJson.serialize(obj_k, "data", data);

        emit Transaction(gnosis, target, 0, data);

        string memory prefix = string.concat(vm.toString(block.number), string.concat(".", vm.toString(block.timestamp)));
        string memory output_path = string.concat(string("./release/logs/txns/"), string.concat(prefix, string(".json"))); // release/logs/$(block_number)_{$(block_timestamp)}json
        stdJson.write(output, output_path);
    }
}