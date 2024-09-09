// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IPriceProvider} from "src/interfaces/IPriceProvider.sol";
import {Governable} from "./governance/Governable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {BucketLimiter} from "./libraries/BucketLimiter.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ISwapper} from "./interfaces/ISwapper.sol";

/*
    AVSs pay out rewards to stakers in their ERC20 tokens.
    The LrtSquare contract consolidates AVS rewards into a single ERC20 token 
    It is designed to address the inefficiencies of collecting small, scattered rewards, 
    which can be costly and cumbersome for users. 
    
    LrtSquare enables LRT protocols to deposit AVS rewards, issue share tokens to stakers, 
    and allows users to redeem the underlying assets proportionate to their shares.
    This setup reduces transaction costs and simplifies the reward collection process, 
    benefiting users with smaller stakes who might prefer managing/trading their share tokens directly, 
    while larger holders have the option to redeem and potentially arbitrage.
*/
contract LrtSquare is
    Initializable,
    Governable,
    ERC20PermitUpgradeable,
    PausableUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
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

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    mapping(address => TokenInfo) public tokenInfos;
    // only whitelisted depositors can deposit tokens into the vault
    mapping(address => bool) public depositor;
    // address of accepted tokens
    address[] public tokens;
    // address of the price provider
    address public priceProvider;
    // rate limit on deposit amount
    BucketLimiter.Limit private rateLimit;
    // address of the rebalancer
    address public rebalancer;
    // tokens that are whitelisted as swap output tokens can only be the output of rebalancing
    mapping(address swapOutputTokens => bool isWhitelisted) public isWhitelistedRebalanceOutputToken;
    // max slippage acceptable when we rebalance (in 18 decimals)
    uint256 public maxSlippageForRebalancing; 
    // Swapper is a helper contract that helps us swap funds in the vault and rebalance 
    address public swapper; 

    uint64 public constant HUNDRED_PERCENT_LIMIT = 1_000_000_000;

    uint256 public depositForCommunityPause;
    uint256 public communityPauseDepositedAmt;

    event TokenRegistered(address token);
    event TokenWhitelisted(address token, bool whitelisted);
    event GovernorSet(address oldGovernor, address newGovernor);
    event PriceProviderSet(address oldPriceProvider, address newPriceProvider);
    event DepositorsSet(address[] accounts, bool[] isDepositor);
    event Deposit(
        address indexed sender,
        address indexed recipient,
        uint256 sharesMinted,
        address[] tokens,
        uint256[] amounts
    );
    event Redeem(
        address indexed account,
        uint256 sharesRedeemed,
        address[] tokens,
        uint256[] amounts
    );
    event CommunityPauseDepositSet(uint256 oldAmount, uint256 newAmount);
    event CommunityPause(address indexed pauser);
    event CommunityPauseAmountWithdrawal(
        address indexed withdrawer,
        uint256 amount
    );
    event RefillRateUpdated(uint64 oldRate, uint64 newRate);
    event RateLimitCapacityUpdated(uint64 oldCapacity, uint64 newCapacity);
    event TokenMaxPositionWeightLimitUpdated(uint64 oldLimit, uint64 newLimit);
    event RebalancerSet(address oldRebalancer, address newRebalancer);
    event MaxSlippageForRebalanceSet(uint256 oldMaxSlippage, uint256 newMaxSlippage);
    event WhitelistRebalanceOutputToken(address token, bool whitelisted);
    event SwapperSet(address oldSwapper, address newSwapper);
    event Rebalance(address fromAsset, address toAsset, uint256 fromAssetAmount,uint256 toAssetAmount);

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
    error NotAValidRebalanceOutputToken();
    error InsufficientTokensReceivedFromSwapper();
    error ApplicableSlippageGreaterThanMaxLimit();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory __name,
        string memory __symbol,
        uint48 __accessControlDelay,
        address __governor,
        address __pauser,
        address __rebalancer,
        address __swapper
    ) public initializer {
        __ERC20_init(__name, __symbol);
        __ERC20Permit_init(__name);
        __UUPSUpgradeable_init();
        __AccessControlDefaultAdminRules_init(__accessControlDelay, __governor);
        _grantRole(PAUSER_ROLE, __pauser);

        _setGovernor(__governor);
        rebalancer = __rebalancer;
        swapper = __swapper;

        // 1_000_000_000 = 100% for limiter
        // Limit = 3_000_000_000 -> 300% of total suppply, refill rate -> 1_000_000 -> 0.1%, so will be refilled in 3000 sec (50 mins)
        rateLimit = BucketLimiter.create(3_000_000_000, 1_000_000);
        emit RateLimitCapacityUpdated(0, 3_000_000_000);
        emit RefillRateUpdated(0, 1_000_000);

        // 0.5%
        maxSlippageForRebalancing = 0.995 ether;
    }

    function mint(address to, uint256 shareToMint) external onlyGovernor {
        _mint(to, shareToMint);
    }

    function getRateLimit() external view returns (BucketLimiter.Limit memory) {
        return rateLimit.getCurrent();
    } 

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
        
        uint256 vaultTotalValueBefore = getVaultTokenValuesInEth(totalSupply());
        uint256 toAssetAmountBefore = IERC20(_toAsset).balanceOf(address(this));
        IERC20(_fromAsset).safeTransfer(swapper, _fromAssetAmount);
        uint256 outAmount = ISwapper(swapper).swap(_fromAsset, _toAsset, _fromAssetAmount, _minToAssetAmount, _data);

        uint256 vaultTotalValueAfter = getVaultTokenValuesInEth(totalSupply());
        uint256 toAssetAmountAfter = IERC20(_toAsset).balanceOf(address(this));

        if (toAssetAmountAfter - toAssetAmountBefore < _minToAssetAmount) revert InsufficientTokensReceivedFromSwapper();
        if (vaultTotalValueAfter < vaultTotalValueBefore) {
            uint256 slippageApplicableInPercentage = ((vaultTotalValueBefore - vaultTotalValueAfter) * 100 * 1 ether) / vaultTotalValueBefore;
            if (slippageApplicableInPercentage > maxSlippageForRebalancing) revert ApplicableSlippageGreaterThanMaxLimit();
        }

        emit Rebalance(_fromAsset, _toAsset, _fromAssetAmount, outAmount);
    }

    function registerToken(address _token, uint64 _positionWeightLimit) external onlyGovernor {
    if (_token == address(0)) revert InvalidValue();
        if (isTokenRegistered(_token)) revert TokenAlreadyRegistered();
        if (IPriceProvider(priceProvider).getPriceInEth(_token) == 0)
            revert PriceProviderNotConfigured();
        if (_positionWeightLimit > HUNDRED_PERCENT_LIMIT) revert WeightLimitCannotBeGreaterThanHundred();

        tokenInfos[_token] = TokenInfo({registered: true, whitelisted: true, positionWeightLimit: _positionWeightLimit});
        tokens.push(_token);

        emit TokenRegistered(_token);
        emit TokenWhitelisted(_token, true);
    }

    function setRebalancer(address account) external onlyGovernor {
        if (account == address(0)) revert InvalidValue();
        emit RebalancerSet(rebalancer, account);
        rebalancer = account;
    }

    function setMaxSlippageForRebalancing(uint256 maxSlippage) external onlyRebalancer {
        if (maxSlippage == 0) revert InvalidValue();
        emit MaxSlippageForRebalanceSet(maxSlippageForRebalancing, maxSlippage);
        maxSlippageForRebalancing = maxSlippage;
    }
    
    function updateWhitelist(
        address _token,
        bool _whitelist
    ) external onlyGovernor {
        if (_token == address(0)) revert InvalidValue();
        if (!isTokenRegistered(_token)) revert TokenNotRegistered();
        tokenInfos[_token].whitelisted = _whitelist;
        emit TokenWhitelisted(_token, _whitelist);
    }

    function updateTokenPositionWeightLimit(address _token, uint64 _TokenPositionWeightLimit) external onlyGovernor {
        if (_token == address(0)) revert InvalidValue();
        if (!isTokenRegistered(_token)) revert TokenNotRegistered();
        if (_TokenPositionWeightLimit > HUNDRED_PERCENT_LIMIT) revert WeightLimitCannotBeGreaterThanHundred();
        emit TokenMaxPositionWeightLimitUpdated(tokenInfos[_token].positionWeightLimit, _TokenPositionWeightLimit);
        tokenInfos[_token].positionWeightLimit = _TokenPositionWeightLimit;
    }

    function setDepositors(
        address[] memory depositors,
        bool[] memory isDepositor
    ) external onlyGovernor {
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


    function setRefillRatePerSecond(uint64 refillRate) external onlyGovernor {
        BucketLimiter.Limit memory limit = rateLimit.getCurrent();
        if (refillRate > limit.capacity) revert RateLimitRefillRateCannotBeGreaterThanCapacity();
        emit RefillRateUpdated(limit.refillRate, refillRate);
        rateLimit.refillRate = refillRate;
    }
    
    function setRateLimitCapacity(uint64 capacity) external onlyGovernor {
        emit RateLimitCapacityUpdated(rateLimit.capacity, capacity);
        rateLimit.capacity = capacity;
    }


    /// @notice Deposit rewards to the contract and mint share tokens to the recipient.
    /// @param _tokens addresses of ERC20 tokens to deposit
    /// @param _amounts amounts of tokens to deposit
    /// @param _receiver recipient of the minted share token
    function deposit(
        address[] memory _tokens,
        uint256[] memory _amounts,
        address _receiver
    ) external whenNotPaused onlyDepositors {
        if (_tokens.length != _amounts.length) revert ArrayLengthMismatch();
        if (_receiver == address(0)) revert InvalidRecipient();

        bool initial_deposit = (totalSupply() == 0);
        uint256 before_VaultTokenValue = getVaultTokenValuesInEth(
            1 * 10 ** decimals()
        );

        uint256 totalSupplyBeforeDeposit = totalSupply();
        uint256 shareToMint = previewDeposit(_tokens, _amounts);
        // check rate limit
        if (totalSupplyBeforeDeposit !=0) {
            uint64 amountForLimit = SafeCast.toUint64((shareToMint * HUNDRED_PERCENT_LIMIT) / totalSupplyBeforeDeposit);
            if(!rateLimit.consume(amountForLimit)) revert RateLimitExceeded();
        } 
        
        _deposit(_tokens, _amounts, shareToMint, _receiver);

        _verifyPositionLimits();

        uint256 after_VaultTokenValue = getVaultTokenValuesInEth(
            1 * 10 ** decimals()
        );

        if (!initial_deposit && before_VaultTokenValue != after_VaultTokenValue)
            revert VaultTokenValueChanged();

        emit Deposit(msg.sender, _receiver, shareToMint, _tokens, _amounts);
    }

    /// @notice Redeem the underlying assets proportionate to the share of the caller.
    /// @param vaultShares amount of vault share token to redeem the underlying assets
    function redeem(uint256 vaultShares) external {
        if (balanceOf(msg.sender) < vaultShares) revert InsufficientShares();

        (
            address[] memory assets,
            uint256[] memory assetAmounts
        ) = assetsForVaultShares(vaultShares);

        _burn(msg.sender, vaultShares);

        for (uint256 i = 0; i < assets.length; i++) 
            if (assetAmounts[i] > 0) IERC20(assets[i]).safeTransfer(msg.sender, assetAmounts[i]);

        emit Redeem(msg.sender, vaultShares, assets, assetAmounts);
    }

    function previewDeposit(
        address[] memory _tokens,
        uint256[] memory _amounts
    ) public view returns (uint256) {
        uint256 rewardsValueInEth = getTokenValuesInEth(_tokens, _amounts);
        return _convertToShares(rewardsValueInEth, Math.Rounding.Floor);
    }

    function assetOf(
        address user,
        address token
    ) external view returns (uint256) {
        return assetForVaultShares(balanceOf(user), token);
    }

    function assetsOf(
        address user
    ) external view returns (address[] memory, uint256[] memory) {
        return assetsForVaultShares(balanceOf(user));
    }

    function assetForVaultShares(
        uint256 vaultShares,
        address token
    ) public view returns (uint256) {
        if (!isTokenRegistered(token)) revert TokenNotRegistered();
        if (totalSupply() == 0) revert TotalSupplyZero();

        return
            _convertToAssetAmount(token, vaultShares, Math.Rounding.Floor);
    }

    function assetsForVaultShares(
        uint256 vaultShare
    ) public view returns (address[] memory, uint256[] memory) {
        if (totalSupply() == 0) revert TotalSupplyZero();
        uint256 len = tokens.length;
        address[] memory assets = new address[](len);
        uint256[] memory assetAmounts = new uint256[](len);
        uint256 cnt = 0;
        for (uint256 i = 0; i < len; ) {
            if (!isTokenRegistered(tokens[i])) {
                unchecked {
                    ++i;
                }
                continue;
            }

            assets[cnt] = tokens[i];
            assetAmounts[cnt] = assetForVaultShares(vaultShare, tokens[i]);

            unchecked {
                ++cnt;
                ++i;
            }
        }

        assembly ("memory-safe") {
            mstore(assets, cnt)
            mstore(assetAmounts, cnt)
        }

        return (assets, assetAmounts);
    }

    function totalAssets()
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256 len = tokens.length;
        address[] memory assets = new address[](len);
        uint256[] memory assetAmounts = new uint256[](len);
        uint256 cnt = 0;
        for (uint256 i = 0; i < len; ) {
            if (!isTokenWhitelisted(tokens[i])) {
                unchecked {
                    ++i;
                }

                continue;
            }

            assets[cnt] = tokens[i];
            assetAmounts[cnt] = IERC20(tokens[i]).balanceOf(address(this));

            unchecked {
                ++i;
                ++cnt;
            }
        }

        assembly ("memory-safe") {
            mstore(assets, cnt)
            mstore(assetAmounts, cnt)
        }

        return (assets, assetAmounts);
    }

    function totalAssetsValueInEth() external view returns (uint256) {
        (
            address[] memory assets,
            uint256[] memory assetAmounts
        ) = totalAssets();

        uint256 totalValue = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            totalValue +=
                (assetAmounts[i] *
                    IPriceProvider(priceProvider).getPriceInEth(assets[i])) /
                10 ** _getDecimals(assets[i]);
        }

        return totalValue;
    }

    function isTokenRegistered(address token) public view returns (bool) {
        return tokenInfos[token].registered;
    }

    function isTokenWhitelisted(address token) public view returns (bool) {
        return tokenInfos[token].whitelisted;
    }

    function getTokenValuesInEth(
        address[] memory _tokens,
        uint256[] memory _amounts
    ) public view returns (uint256) {
        uint256 total_eth = 0;
        uint256 len = _tokens.length;

        if (len != _amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < _tokens.length; i++) {
            if (!isTokenRegistered(_tokens[i])) revert TokenNotRegistered();
            if (!isTokenWhitelisted(_tokens[i])) revert TokenNotWhitelisted();

            uint256 price = IPriceProvider(priceProvider).getPriceInEth(
                _tokens[i]
            );
            if (price == 0) revert PriceProviderFailed();

            total_eth +=
                (_amounts[i] *
                    IPriceProvider(priceProvider).getPriceInEth(_tokens[i])) /
                10 ** _getDecimals(_tokens[i]);
        }
        return total_eth;
    }

    function getTokenTotalValuesInEth(
        address token
    ) public view returns (uint256) {
        if (!isTokenRegistered(token)) revert TokenNotRegistered();
        if (!isTokenWhitelisted(token)) revert TokenNotWhitelisted();

        uint256 price = IPriceProvider(priceProvider).getPriceInEth(
            token
        );
        if (price == 0) revert PriceProviderFailed();

        return (IERC20(token).balanceOf(address(this)) * IPriceProvider(priceProvider).getPriceInEth(token)) / 10 ** _getDecimals(token);
    }

    function getVaultTokenValuesInEth(
        uint256 vaultTokenShares
    ) public view returns (uint256) {
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            return 0;
        }

        (
            address[] memory assets,
            uint256[] memory assetAmounts
        ) = totalAssets();
        uint256 totalValue = getTokenValuesInEth(assets, assetAmounts);
        return (totalValue * vaultTokenShares) / totalSupply;
    }

    function communityPause() external payable whenNotPaused {
        if (depositForCommunityPause == 0) revert CommunityPauseDepositNotSet();
        if (msg.value != depositForCommunityPause)
            revert IncorrectAmountOfEtherSent();

        _pause();
        communityPauseDepositedAmt = msg.value;
        emit CommunityPause(msg.sender);
    }

    function pause() external onlyRole(PAUSER_ROLE) whenNotPaused {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) whenPaused {
        uint256 amount = communityPauseDepositedAmt;
        if (amount != 0) {
            communityPauseDepositedAmt = 0;
            _withdrawEth(msg.sender, amount);
            emit CommunityPauseAmountWithdrawal(msg.sender, amount);
        }

        _unpause();
    }

    function withdrawCommunityDepositedPauseAmount()
        public
        onlyRole(PAUSER_ROLE)
    {
        uint256 amount = communityPauseDepositedAmt;

        if (amount == 0) revert NoCommunityPauseDepositAvailable();
        communityPauseDepositedAmt = 0;
        _withdrawEth(msg.sender, amount);

        emit CommunityPauseAmountWithdrawal(msg.sender, amount);
    }

    function setCommunityPauseDepositAmount(
        uint256 amount
    ) external onlyGovernor {
        emit CommunityPauseDepositSet(depositForCommunityPause, amount);
        depositForCommunityPause = amount;
    }
    function positionWeightLimit() public view returns (address[] memory, uint64[] memory) {
        uint256 len = tokens.length;
        uint64[] memory positionWeightLimits = new uint64[](len);
        uint256 vaultTotalValue = getVaultTokenValuesInEth(totalSupply());

        for (uint256 i = 0; i < len; ) {
            positionWeightLimits[i] = _getPositionWeight(tokens[i], vaultTotalValue);
            unchecked {
                ++i;
            }
        }

        return (tokens, positionWeightLimits);
    }

    function getPositionWeight(address token) public view returns (uint64) {
        uint256 vaultTotalValue = getVaultTokenValuesInEth(totalSupply());
        return _getPositionWeight(token, vaultTotalValue);
    }

    function _getPositionWeight(address token, uint256 vaultTotalValue) internal view returns (uint64) {
        uint256 valueOfTokenInVault = getTokenTotalValuesInEth(token);
        return SafeCast.toUint64((valueOfTokenInVault * HUNDRED_PERCENT_LIMIT) / vaultTotalValue);
    }


    /// @notice Deposit rewards to the contract and mint share tokens to the recipient.
    /// @param _tokens addresses of ERC20 tokens to deposit
    /// @param amounts amounts of tokens to deposit
    /// @param shareToMint amount of share token (= LRT^2 token) to mint
    /// @param recipientForMintedShare recipient of the minted share token
    function _deposit(
        address[] memory _tokens,
        uint256[] memory amounts,
        uint256 shareToMint,
        address recipientForMintedShare
    ) internal {
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (!isTokenRegistered(_tokens[i])) revert TokenNotRegistered();

            IERC20(_tokens[i]).safeTransferFrom(
                msg.sender,
                address(this),
                amounts[i]
            );
        }

        _mint(recipientForMintedShare, shareToMint);
    }

    function _convertToShares(
        uint256 valueInEth,
        Math.Rounding rounding
    ) public view virtual returns (uint256) {
        uint256 _totalSupply = totalSupply();
        return
            valueInEth.mulDiv(
                _totalSupply + 10 ** _decimalsOffset(),
                getVaultTokenValuesInEth(_totalSupply) + 1,
                rounding
            );
    }

    function _convertToAssetAmount(
        address assetToken,
        uint256 vaultShares,
        Math.Rounding rounding
    ) internal view virtual returns (uint256) {
        return
            vaultShares.mulDiv(
                IERC20(assetToken).balanceOf(address(this)) + 1,
                totalSupply() + 10 ** _decimalsOffset(),
                rounding
            );
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }

    function _getDecimals(address erc20) internal view returns (uint8) {
        return IERC20Metadata(erc20).decimals();
    }

    function _verifyPositionLimits() internal view {
        uint256 len = tokens.length;
        uint64[] memory positionWeightLimits = new uint64[](len);
        uint256 vaultTotalValue = getVaultTokenValuesInEth(totalSupply());

        if(vaultTotalValue == 0) return;

        for (uint256 i = 0; i < len; ) {
            positionWeightLimits[i] = _getPositionWeight(tokens[i], vaultTotalValue);
            if (positionWeightLimits[i] > tokenInfos[tokens[i]].positionWeightLimit) revert TokenWeightLimitBreached(); {
                ++i;
            }
        }
    }

    function _withdrawEth(address recipient, uint256 amount) internal {
        (bool success, ) = payable(recipient).call{value: amount}("");
        if (!success) revert EtherTransferFailed();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyGovernor {}

    modifier onlyDepositors() {
        _onlyDepositors();
        _;
    }

    function _onlyDepositors() internal view {
        if (!depositor[msg.sender]) revert OnlyDepositors();
    }

    modifier onlyRebalancer() {
        _onlyRebalancer();
        _;
    }

    function _onlyRebalancer() internal view {
        if (rebalancer != msg.sender) revert OnlyRebalancer();
    }
}
