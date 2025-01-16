// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredStorage, BucketLimiter} from "./LRTSquaredStorage.sol";

contract LRTSquaredDummy is LRTSquaredStorage {
    using BucketLimiter for BucketLimiter.Limit;
    
     function getEIP712Storage() private pure returns (EIP712Storage storage $) {
        assembly {
            $.slot := 0xa16a46d94261c7517cc8ff89f61c0ce93598e3c849801011dee649a6a557d100
        }
    }

    function getERC20Storage() private pure returns (ERC20Storage storage $) {
        assembly {
            $.slot := 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00
        }
    }

    function setInfo(string memory name_, string memory symbol_) external onlyGovernor {
        ERC20Storage storage $ = getERC20Storage();
        $._name = name_;
        $._symbol = symbol_;


        EIP712Storage storage $$ = getEIP712Storage();
        $$._name = name_;
        $$._version = "3";
    }
}