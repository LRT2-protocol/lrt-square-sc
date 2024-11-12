// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredStorage, BucketLimiter, Math, SafeERC20, IERC20, IPriceProvider, ISwapper} from "./LRTSquaredStorage.sol";
import {BaseStrategy} from "../strategies/BaseStrategy.sol";

contract LRTSquaredAdmin is LRTSquaredStorage {
    using BucketLimiter for BucketLimiter.Limit;
    using SafeERC20 for IERC20;
    using Math for uint256;

    function whitelistRebalacingOutputToken(address _token, bool _shouldWhitelist) external onlyGovernor {
        if (_token == address(0)) revert InvalidValue();
        if (_shouldWhitelist) {
            if(!isTokenRegistered(_token)) revert TokenNotRegistered();
            if (IPriceProvider(priceProvider).getPriceInEth(_token) == 0)
                revert PriceProviderNotConfigured();
        }

        isWhitelistedRebalanceOutputToken[_token] = _shouldWhitelist;
        emit WhitelistRebalanceOutputToken(_token, _shouldWhitelist);
    }

    function setFee(Fee memory _fee) external onlyGovernor {
        _setFee(_fee);
    }

    function setTreasuryAddress(address treasury) external onlyGovernor {
        if (treasury == address(0)) revert InvalidValue();
        emit TreasurySet(fee.treasury, treasury);
        fee.treasury = treasury;
    }

    function setSwapper(address _swapper) external onlyGovernor {
        if (_swapper == address(0)) revert InvalidValue();
        emit SwapperSet(swapper, _swapper);
        swapper = _swapper;
    } 

    function rebalance(
        address _fromAsset,
        address _toAsset,
        uint256 _fromAssetAmount,
        uint256 _minToAssetAmount,
        bytes calldata _data
    ) external onlyRebalancer {
        if (!isTokenRegistered(_fromAsset) || !isTokenRegistered(_toAsset)) revert TokenNotRegistered();
        // Input token may have been removed from whitelist to pause deposits for that token
        if (!isTokenWhitelisted(_toAsset)) revert TokenNotWhitelisted();
        if (!isWhitelistedRebalanceOutputToken[_toAsset]) revert NotAValidRebalanceOutputToken();

        uint256 vaultTotalValueBefore = _getVaultTokenValuesInEth(totalSupply());
        uint256 toAssetAmountBefore = IERC20(_toAsset).balanceOf(address(this));
        IERC20(_fromAsset).safeTransfer(swapper, _fromAssetAmount);
        uint256 outAmount = ISwapper(swapper).swap(_fromAsset, _toAsset, _fromAssetAmount, _minToAssetAmount, _data);

        uint256 vaultTotalValueAfter = _getVaultTokenValuesInEth(totalSupply());
        uint256 toAssetAmountAfter = IERC20(_toAsset).balanceOf(address(this));

        if (toAssetAmountAfter - toAssetAmountBefore < _minToAssetAmount) revert InsufficientTokensReceivedFromSwapper();
        if (vaultTotalValueAfter < vaultTotalValueBefore) {
            uint256 minVaultTotalValueAfter = (vaultTotalValueBefore * maxSlippageForRebalancing) / 1 ether;
            if (vaultTotalValueAfter < minVaultTotalValueAfter) revert ApplicableSlippageGreaterThanMaxLimit();
        }

        _verifyPositionLimits();

        emit Rebalance(_fromAsset, _toAsset, _fromAssetAmount, outAmount);
    }

    function registerToken(address _token, uint64 _positionWeightLimit) external onlyGovernor {
        if (_token == address(0)) revert InvalidValue();
        if (isTokenRegistered(_token)) revert TokenAlreadyRegistered();
        if (IPriceProvider(priceProvider).getPriceInEth(_token) == 0)
            revert PriceProviderNotConfigured();
        if (_positionWeightLimit > HUNDRED_PERCENT_LIMIT) revert WeightLimitCannotBeGreaterThanHundred();

        _tokenInfos[_token] = TokenInfo({registered: true, whitelisted: true, positionWeightLimit: _positionWeightLimit});
        tokens.push(_token);

        emit TokenRegistered(_token);
        emit TokenWhitelisted(_token, true);
    }

    function setRebalancer(address account) external onlyGovernor {
        if (account == address(0)) revert InvalidValue();
        emit RebalancerSet(rebalancer, account);
        rebalancer = account;
    }

    function setPauser(address account, bool isPauser) external onlyGovernor {
        if (account == address(0)) revert InvalidValue();
        if (pauser[account] == isPauser) revert AlreadyInSameState();
        
        pauser[account] = isPauser;
        emit PauserSet(account, isPauser);
    }

    function setMaxSlippageForRebalancing(uint256 maxSlippage) external onlyRebalancer {
        if (maxSlippage == 0) revert InvalidValue();
        emit MaxSlippageForRebalanceSet(maxSlippageForRebalancing, maxSlippage);
        maxSlippageForRebalancing = maxSlippage;
    }
    
    function updateWhitelist(address _token, bool _whitelist) external onlyGovernor {
        if (_token == address(0)) revert InvalidValue();
        if (!isTokenRegistered(_token)) revert TokenNotRegistered();
        _tokenInfos[_token].whitelisted = _whitelist;
        emit TokenWhitelisted(_token, _whitelist);
    }

    function updateTokenPositionWeightLimit(address _token, uint64 _TokenPositionWeightLimit) external onlyGovernor {
        if (_token == address(0)) revert InvalidValue();
        if (!isTokenRegistered(_token)) revert TokenNotRegistered();
        if (_TokenPositionWeightLimit > HUNDRED_PERCENT_LIMIT) revert WeightLimitCannotBeGreaterThanHundred();
        emit TokenMaxPositionWeightLimitUpdated(_tokenInfos[_token].positionWeightLimit, _TokenPositionWeightLimit);
        _tokenInfos[_token].positionWeightLimit = _TokenPositionWeightLimit;
    }

    function setDepositors(address[] memory depositors, bool[] memory isDepositor) external onlyGovernor {
        uint256 len = depositors.length;
        if (len != isDepositor.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < len; ) {
            if (depositors[i] == address(0)) revert InvalidValue();
            depositor[depositors[i]] = isDepositor[i];

            unchecked {
                ++i;
            }
        }

        emit DepositorsSet(depositors, isDepositor);
    }

    function updatePriceProvider(address _priceProvider) external onlyGovernor {
        if (_priceProvider == address(0)) revert InvalidValue();
        emit PriceProviderSet(priceProvider, _priceProvider);
        priceProvider = _priceProvider;
    }

    function setRateLimitConfig(uint128 __percentageLimit, uint64 __timePeriod, uint128 __refillRate) external onlyGovernor {
        uint256 _totalSupply = totalSupply();
        uint128 capactity = uint128(_totalSupply.mulDiv(__percentageLimit, HUNDRED_PERCENT_LIMIT));
        rateLimit = RateLimit({
            limit: BucketLimiter.create(capactity, __refillRate),
            timePeriod: __timePeriod, 
            renewTimestamp: uint64(block.timestamp + __timePeriod),
            percentageLimit: __percentageLimit
        });
    }

    function setRateLimitTimePeriod(uint64 __timePeriod) external onlyGovernor {
        if (__timePeriod == 0) revert InvalidValue();
        emit RateLimitTimePeriodUpdated(rateLimit.timePeriod, __timePeriod);
        rateLimit.timePeriod = __timePeriod;
    }

    function setRefillRatePerSecond(uint64 __refillRate) external onlyGovernor {
        emit RefillRateUpdated(rateLimit.limit.refillRate, __refillRate);
        rateLimit.limit.setRefillRate(__refillRate);
    }
    
    function setPercentageRateLimit(uint128 __percentageLimit) external onlyGovernor {
        emit PercentageRateLimitUpdated(rateLimit.percentageLimit, __percentageLimit);
        rateLimit.percentageLimit = __percentageLimit;
    }

    function pause() external onlyPauser whenNotPaused {
        _pause();
    }

    function unpause() external onlyPauser whenPaused {
        uint256 amount = communityPauseDepositedAmt;
        if (amount != 0) {
            communityPauseDepositedAmt = 0;
            _withdrawEth(governor(), amount);
            emit CommunityPauseAmountWithdrawal(governor(), amount);
        }

        _unpause();
    }

    function setCommunityPauseDepositAmount(uint256 amount) external onlyGovernor {
        emit CommunityPauseDepositSet(depositForCommunityPause, amount);
        depositForCommunityPause = amount;
    }

    function setTokenStrategyConfig(address token, StrategyConfig memory strategyConfig) external onlyGovernor {
        if (token == address(0)) revert InvalidValue();
        if(!isTokenRegistered(token)) revert TokenNotRegistered();
        if (IPriceProvider(priceProvider).getPriceInEth(token) == 0) revert PriceProviderNotConfigured();

        if (strategyConfig.strategyAdapter == address(0)) revert StrategyAdapterCannotBeAddressZero();
        if (strategyConfig.maxSlippageInBps > MAX_SLIPPAGE_FOR_STRATEGY_IN_BPS) revert SlippageCannotBeGreaterThanMaxLimit();

        address returnToken = BaseStrategy(strategyConfig.strategyAdapter).returnToken();
        if (returnToken == address(0)) revert StrategyReturnTokenCannotBeAddressZero();
        if(!isTokenRegistered(returnToken)) revert StrategyReturnTokenNotRegistered();
        if (IPriceProvider(priceProvider).getPriceInEth(returnToken) == 0) revert PriceProviderNotConfiguredForStrategyReturnToken();

        tokenStrategyConfig[token] = strategyConfig;
        emit StrategyConfigSet(token, strategyConfig.strategyAdapter, strategyConfig.maxSlippageInBps);
    }

    function depositToStrategy(address token, uint256 amount) external onlyGovernor {
        if (amount == type(uint256).max) amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) revert AmountCannotBeZero();

        if (tokenStrategyConfig[token].strategyAdapter == address(0)) revert TokenStrategyConfigNotSet();
        delegateCall(
            tokenStrategyConfig[token].strategyAdapter, 
            abi.encodeWithSelector(BaseStrategy.deposit.selector, token, amount, tokenStrategyConfig[token].maxSlippageInBps)
        );
    }

    function delegateCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory result) {
        require(target != address(this), "delegatecall to self");

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Perform delegatecall to the target contract
            let success := delegatecall(
                gas(),
                target,
                add(data, 0x20),
                mload(data),
                0,
                0
            )

            // Get the size of the returned data
            let size := returndatasize()

            // Allocate memory for the return data
            result := mload(0x40)

            // Set the length of the return data
            mstore(result, size)

            // Copy the return data to the allocated memory
            returndatacopy(add(result, 0x20), 0, size)

            // Update the free memory pointer
            mstore(0x40, add(result, add(0x20, size)))

            if iszero(success) {
                revert(result, returndatasize())
            }
        }
    }

    modifier onlyRebalancer() {
        _onlyRebalancer();
        _;
    }

    function _onlyRebalancer() internal view {
        if (rebalancer != msg.sender) revert OnlyRebalancer();
    }

    modifier onlyPauser() {
        _onlyPauser();
        _;
    }

    function _onlyPauser() internal view {
        if (!pauser[msg.sender]) revert OnlyPauser();
    }
}