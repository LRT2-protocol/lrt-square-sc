// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredStorageDummy, BucketLimiter} from "./LRTSquaredStorageDummy.sol";

contract LRTSquaredDummy is LRTSquaredStorageDummy {
    using BucketLimiter for BucketLimiter.Limit;
    
    function setInfo(string memory __name, string memory __symbol) onlyGovernor public {
        setNameAndSymbol(__name, __symbol);
    }
}