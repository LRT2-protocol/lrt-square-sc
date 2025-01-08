// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BucketLimiter} from "../libraries/BucketLimiter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IKING is IERC20 {
    struct TokenInfo {
        bool registered;
        bool whitelisted;
        uint64 positionWeightLimit;
    }

    struct RateLimit {
        BucketLimiter.Limit limit;
        uint64 timePeriod;
        uint64 renewTimestamp;
        uint128 percentageLimit;
    }

    struct Fee {
        address treasury;
        uint48 depositFeeInBps;
        uint48 redeemFeeInBps;
    }

    struct StrategyConfig {
        address strategyAdapter;
        uint96 maxSlippageInBps;
    }

    event TokenRegistered(address token);
    event TokenWhitelisted(address token, bool whitelisted);
    event PriceProviderSet(address oldPriceProvider, address newPriceProvider);
    event DepositorsSet(address[] accounts, bool[] isDepositor);
    event Deposit(address indexed sender, address indexed recipient, uint256 sharesMinted, uint256 fee, address[] tokens, uint256[] amounts);
    event Redeem(address indexed account, uint256 sharesRedeemed, uint256 fee, address[] tokens, uint256[] amounts);
    event CommunityPauseDepositSet(uint256 oldAmount, uint256 newAmount);
    event CommunityPause(address indexed pauser);
    event CommunityPauseAmountWithdrawal(address indexed recipient, uint256 amount);
    event RefillRateUpdated(uint128 oldRate, uint128 newRate);
    event PercentageRateLimitUpdated(uint128 oldPercentage, uint128 newPercentage);
    event RateLimitTimePeriodUpdated(uint64 oldTimePeriod, uint64 newTimePeriod);
    event TokenMaxPositionWeightLimitUpdated(uint64 oldLimit, uint64 newLimit);
    event RebalancerSet(address oldRebalancer, address newRebalancer);
    event PauserSet(address pauser, bool isPauser);
    event MaxSlippageForRebalanceSet(uint256 oldMaxSlippage, uint256 newMaxSlippage);
    event WhitelistRebalanceOutputToken(address token, bool whitelisted);
    event SwapperSet(address oldSwapper, address newSwapper);
    event Rebalance(address fromAsset, address toAsset, uint256 fromAssetAmount,uint256 toAssetAmount);
    event FeeSet(Fee oldFee, Fee newFee);
    event TreasurySet(address oldTreasury, address newTreasury);
    event StrategyConfigSet(address indexed token, address indexed strategyAdapter, uint96 maxSlippageInBps);

    error TokenAlreadyRegistered();
    error TokenNotWhitelisted();
    error TokenNotRegistered();
    error ArrayLengthMismatch();
    error InvalidValue();
    error InvalidRecipient();
    error VaultTokenValueChanged();
    error InsufficientShares();
    error TotalSupplyZero();
    error OnlyDepositors();
    error PriceProviderNotConfigured();
    error PriceProviderFailed();
    error CommunityPauseDepositNotSet();
    error IncorrectAmountOfEtherSent();
    error EtherTransferFailed();
    error NoCommunityPauseDepositAvailable();
    error RateLimitExceeded();
    error RateLimitRefillRateCannotBeGreaterThanCapacity();
    error WeightLimitCannotBeGreaterThanHundred();
    error TokenWeightLimitBreached();
    error OnlyRebalancer();
    error OnlyPauser();
    error NotAValidRebalanceOutputToken();
    error InsufficientTokensReceivedFromSwapper();
    error ApplicableSlippageGreaterThanMaxLimit();
    error AlreadyInSameState();
    error StrategyAdapterCannotBeAddressZero();
    error SlippageCannotBeGreaterThanMaxLimit();
    error AmountCannotBeZero();
    error TokenStrategyConfigNotSet();
    error StrategyReturnTokenCannotBeAddressZero();
    error StrategyReturnTokenNotRegistered();
    error PriceProviderNotConfiguredForStrategyReturnToken();

    function HUNDRED_PERCENT_LIMIT() external pure returns (uint64);
    function HUNDRED_PERCENT_IN_BPS() external pure returns (uint64);
    function MAX_SLIPPAGE_FOR_STRATEGY_IN_BPS() external pure returns (uint256);
    function tokenInfos(address token) external view returns (TokenInfo memory);
    function depositor(address account) external view returns (bool);
    function tokens(uint256 index) external view returns (address);
    function allTokens() external view returns (address[] memory);
    function priceProvider() external view returns (address);
    function rebalancer() external view returns (address);
    function isWhitelistedRebalanceOutputToken(address token) external view returns (bool);
    function maxSlippageForRebalancing() external view returns (uint256);
    function swapper() external view returns (address);
    function pauser(address account) external view returns (bool);
    function depositForCommunityPause() external view returns (uint256);
    function communityPauseDepositedAmt() external view returns (uint256);
    function fee() external view returns (Fee memory);
    function tokenStrategyConfig(address token) external view returns (StrategyConfig memory);
    function getRateLimit() external view returns (RateLimit memory);
    function whitelistRebalacingOutputToken(address _token, bool _shouldWhitelist) external;
    function setFee(Fee memory _fee) external;
    function setTreasuryAddress(address treasury) external;
    function setSwapper(address _swapper) external;
    function rebalance(address _fromAsset, address _toAsset, uint256 _fromAssetAmount, uint256 _minToAssetAmount, bytes calldata _data) external;
    function registerToken(address _token, uint64 _positionWeightLimit) external;
    function setRebalancer(address account) external;
    function setPauser(address account, bool isPauser) external;
    function setMaxSlippageForRebalancing(uint256 maxSlippage) external;
    function updateWhitelist(address _token, bool _whitelist) external;
    function updateTokenPositionWeightLimit(address _token, uint64 _TokenPositionWeightLimit) external;
    function setDepositors(address[] memory depositors, bool[] memory isDepositor) external;
    function updatePriceProvider(address _priceProvider) external;
    function setRateLimitConfig(uint128 __percentageLimit, uint64 __timePeriod, uint128 __refillRate) external;
    function setRateLimitTimePeriod(uint64 __timePeriod) external;
    function setRefillRatePerSecond(uint64 __refillRate) external;
    function setPercentageRateLimit(uint128 __percentageLimit) external;
    function setTokenStrategyConfig(address token, StrategyConfig memory strategyConfig) external;
    function depositToStrategy(address token, uint256 amount) external;
    function deposit(address[] memory _tokens, uint256[] memory _amounts, address _receiver) external;
    function redeem(uint256 vaultShares) external;
    function previewDeposit(address[] memory _tokens, uint256[] memory _amounts) external view returns (uint256, uint256);
    function previewRedeem(uint256 vaultShares) external view returns (address[] memory, uint256[] memory, uint256);
    function assetOf(address user, address token) external view returns (uint256);
    function assetsOf(address user) external view returns (address[] memory, uint256[] memory);
    function assetForVaultShares(uint256 vaultShares, address token) external view returns (uint256);
    function assetsForVaultShares(uint256 vaultShare) external view returns (address[] memory, uint256[] memory);
    function totalAssets() external view returns (address[] memory, uint256[] memory);
    function tvl() external view returns (uint256, uint256);
    function isTokenRegistered(address token) external view returns (bool);
    function isTokenWhitelisted(address token) external view returns (bool);
    function getTokenValuesInEth(address[] memory _tokens, uint256[] memory _amounts) external view returns (uint256);
    function getTokenTotalValuesInEth(address token) external view returns (uint256);
    function fairValueOf(uint256 vaultTokenShares) external view returns (uint256, uint256);
    function communityPause() external payable;
    function pause() external;
    function unpause() external;
    function withdrawCommunityDepositedPauseAmount() external;
    function setCommunityPauseDepositAmount(uint256 amount) external;
    function positionWeightLimit() external view returns (address[] memory, uint64[] memory);
    function getPositionWeight(address token) external view returns (uint64);
    function paused() external view returns (bool);
    function governor() external view returns (address);
    function transferGovernance(address _newGovernor) external;
}
