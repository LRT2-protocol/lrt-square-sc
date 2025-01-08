// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20PermitUpgradeableDummy} from "../dummy/ERC20/extensions/ERC20PermitUpgradeableDummy.sol";
import {UUPSUpgradeable, Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IPriceProvider} from "src/interfaces/IPriceProvider.sol";
import {Governable} from "../governance/Governable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {BucketLimiter} from "../libraries/BucketLimiter.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";

/*
    AVSs pay out rewards to stakers in their ERC20 tokens.
    The KING contract consolidates AVS rewards into a single ERC20 token 
    It is designed to address the inefficiencies of collecting small, scattered rewards, 
    which can be costly and cumbersome for users. 
    
    KING enables KING protocols to deposit AVS rewards, issue share tokens to stakers, 
    and allows users to redeem the underlying assets proportionate to their shares.
    This setup reduces transaction costs and simplifies the reward collection process, 
    benefiting users with smaller stakes who might prefer managing/trading their share tokens directly, 
    while larger holders have the option to redeem and potentially arbitrage.
*/
contract KINGStorageDummy is
    Initializable,
    Governable,
    ERC20PermitUpgradeableDummy,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using BucketLimiter for BucketLimiter.Limit;
    using SafeERC20 for IERC20;
    using Math for uint256;

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

    uint64 public constant HUNDRED_PERCENT_LIMIT = 1_000_000_000;
    uint64 public constant HUNDRED_PERCENT_IN_BPS = 10000;

    mapping(address => TokenInfo) internal _tokenInfos; 
    // only whitelisted depositors can deposit tokens into the vault
    mapping(address => bool) public depositor; 
    // address of accepted tokens
    address[] public tokens;
    // address of the price provider
    address public priceProvider;
    // rate limit on deposit amount
    RateLimit internal rateLimit; 
    // address of the rebalancer
    address public rebalancer; 
    // tokens that are whitelisted as swap output tokens can only be the output of rebalancing
    mapping(address swapOutputTokens => bool isWhitelisted) public isWhitelistedRebalanceOutputToken; 
    // max slippage acceptable when we rebalance (in 18 decimals)
    uint256 public maxSlippageForRebalancing; 
    // Swapper is a helper contract that helps us swap funds in the vault and rebalance 
    address public swapper; 
    // Swapper is a helper contract that helps us swap funds in the vault and rebalance 
    mapping(address => bool) public pauser;
    // deposit amount for community pause in Eth
    uint256 public depositForCommunityPause;
    // deposited amount after community pause
    uint256 public communityPauseDepositedAmt;
    // fee struct
    Fee public fee;
    // strategy config for tokens
    mapping (address token => StrategyConfig strategyConfig) public tokenStrategyConfig;
    // max slippage for strategy = 1% 
    uint256 public constant MAX_SLIPPAGE_FOR_STRATEGY_IN_BPS = 100;
    // keccak256("KING.admin.impl");
    bytes32 constant adminImplPosition = 0x67f3bdb99ec85305417f06f626cf52c7dee7e44607664b5f1cce0af5d822472f;

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
    error SharesCannotBeZero();
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice set the implementation for the admin, this needs to be in a base class else we cannot set it
     * @param newImpl address of the implementation
     */
    function setAdminImpl(address newImpl) external onlyGovernor {
        bytes32 position = adminImplPosition;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(position, newImpl)
        }
    }

    function isTokenRegistered(address token) public view returns (bool) {
        return _tokenInfos[token].registered;
    }

    function isTokenWhitelisted(address token) public view returns (bool) {
        return _tokenInfos[token].whitelisted;
    }

    function allTokens() external view returns (address[] memory) {
        return tokens;
    }

    function tokenInfos(address token) external view returns (TokenInfo memory) {
        return _tokenInfos[token];
    }

    function _getVaultTokenValuesInEth(
        uint256 vaultTokenShares
    ) internal view returns (uint256) {
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) return 0;

        (
            address[] memory assets,
            uint256[] memory assetAmounts
        ) = totalAssets();

        uint256 totalValue = getTokenValuesInEth(assets, assetAmounts);
        return (totalValue * vaultTokenShares) / totalSupply;
    }

    function totalAssets()
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory assets = tokens;
        uint256 len = assets.length;
        uint256[] memory assetAmounts = new uint256[](len);
        for (uint256 i = 0; i < len; ) {
            assetAmounts[i] = IERC20(assets[i]).balanceOf(address(this));
            unchecked {
                ++i;
            }
        }

        return (assets, assetAmounts);
    }

    function getTokenValuesInEth(
        address[] memory _tokens,
        uint256[] memory _amounts
    ) public view returns (uint256) {
        uint256 total_eth = 0;
        uint256 len = _tokens.length;

        if (len != _amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < _tokens.length; ) {
            if (!isTokenRegistered(_tokens[i])) revert TokenNotRegistered();

            uint256 price = IPriceProvider(priceProvider).getPriceInEth(
                _tokens[i]
            );
            if (price == 0) revert PriceProviderFailed();
            total_eth += (_amounts[i] * price) / 10 ** _getDecimals(_tokens[i]);

            unchecked {
                ++i;
            }
        }
        return total_eth;
    }

    function getTokenTotalValuesInEth(
        address token
    ) public view returns (uint256) {
        uint256 price = IPriceProvider(priceProvider).getPriceInEth(
            token
        );
        if (price == 0) revert PriceProviderFailed();

        return (IERC20(token).balanceOf(address(this)) * IPriceProvider(priceProvider).getPriceInEth(token)) / 10 ** _getDecimals(token);
    }


    function _getDecimals(address erc20) internal view returns (uint8) {
        return IERC20Metadata(erc20).decimals();
    }

    function _verifyPositionLimits() internal view {
        uint256 len = tokens.length;
        uint256 vaultTotalValue = _getVaultTokenValuesInEth(totalSupply());

        if(vaultTotalValue == 0) return;

        for (uint256 i = 0; i < len; ) {
            if (_getPositionWeight(tokens[i], vaultTotalValue) > _tokenInfos[tokens[i]].positionWeightLimit) 
                revert TokenWeightLimitBreached(); 

            unchecked {
                ++i;
            }
        }
    }

    function _getPositionWeight(address token, uint256 vaultTotalValue) internal view returns (uint64) {
        uint256 valueOfTokenInVault = getTokenTotalValuesInEth(token);
        return SafeCast.toUint64((valueOfTokenInVault * HUNDRED_PERCENT_LIMIT) / vaultTotalValue);
    }

    function _withdrawEth(address recipient, uint256 amount) internal {
        (bool success, ) = payable(recipient).call{value: amount}("");
        if (!success) revert EtherTransferFailed();
    }

    function _setFee(Fee memory _fee) internal {
        if (
            _fee.treasury == address(0) || 
            _fee.depositFeeInBps > HUNDRED_PERCENT_IN_BPS || 
            _fee.redeemFeeInBps > HUNDRED_PERCENT_IN_BPS
        ) revert InvalidValue();
        
        emit FeeSet(fee, _fee);
        fee = _fee;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernor {}
}
