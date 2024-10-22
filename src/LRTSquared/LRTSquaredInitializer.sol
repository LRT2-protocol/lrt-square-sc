// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredStorage, BucketLimiter} from "./LRTSquaredStorage.sol";

contract LRTSquaredInitializer is LRTSquaredStorage {
    using BucketLimiter for BucketLimiter.Limit;
    
    function initialize(
        string memory __name,
        string memory __symbol,
        address __governor,
        address __pauser,
        address __rebalancer,
        address __swapper,
        address __priceProvider,
        uint128 __percentageLimit,
        uint256 __depositForCommunityPause,
        Fee memory __fee
    ) public initializer {
        __ERC20_init(__name, __symbol);
        __ERC20Permit_init(__name);
        __UUPSUpgradeable_init();

        _setGovernor(__governor);
        rebalancer = __rebalancer;
        swapper = __swapper;
        pauser[__pauser] = true;
        priceProvider = __priceProvider;

        // Initially allows 1000 ether in an hour with refill rate of 0.01 ether per seconds -> Max 1 hour -> 1036 shares
        // Updates every 1 hour -> new limit becomes percentageLimit * totalSupply
        rateLimit = RateLimit({
            limit: BucketLimiter.create(1000 ether, 0.01 ether),
            timePeriod: 3600, 
            renewTimestamp: uint64(block.timestamp + 3600),
            percentageLimit: __percentageLimit
        });
        depositForCommunityPause = __depositForCommunityPause;
        _setFee(__fee);

        emit PauserSet(__pauser, true);
        emit RebalancerSet(address(0), __rebalancer);
        emit SwapperSet(address(0), __swapper);
        emit PriceProviderSet(address(0), __priceProvider);
        emit PercentageRateLimitUpdated(0, __percentageLimit);
        emit RefillRateUpdated(0, 0.01 ether);
        emit CommunityPauseDepositSet(0, __depositForCommunityPause);

        // 0.5%
        maxSlippageForRebalancing = 0.995 ether;
    }
}