// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {KINGStorageDummy, BucketLimiter} from "./KINGStorageDummy.sol";

contract KINGInitializer is KINGStorageDummy {
    using BucketLimiter for BucketLimiter.Limit;
    
    function setInfo(string memory __name, string memory __symbol) onlyGovernor public initializer {
        setNameAndSymbol(__name, __symbol);
    }
}