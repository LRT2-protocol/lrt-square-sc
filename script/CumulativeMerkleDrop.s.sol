// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquare, Governable} from "../src/LRTSquare.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract DeployCumulativeMerkleDrop is Utils {
    uint48 accessControlDelay = 120;
    address owner;
}