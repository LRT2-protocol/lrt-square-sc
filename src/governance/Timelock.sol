// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract Timelock is TimelockController {
    constructor(
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(86400 * 2, proposers, executors, admin) {}
}
