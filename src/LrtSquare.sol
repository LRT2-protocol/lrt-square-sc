// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IPriceProvider} from "src/interfaces/IPriceProvider.sol";
import {Governable} from "./governance/Governable.sol";
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
    UUPSUpgradeable
{
    using BucketLimiter for BucketLimiter.Limit;
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct TokenInfo {
        bool registered;
        bool whitelisted;
        uint64 maxPercentageInVault;
    }

    mapping(address => TokenInfo) public tokenInfos;
    mapping(address => bool) public depositor;
    address[] public tokens;
    address public priceProvider;
    BucketLimiter.Limit private rateLimit;
    address public rebalancer;
    mapping(address swapOutputTokens => bool isWhitelisted) public isValidRebalanceOutputToken;
    uint256 public maxAcceptableSlippageForRebalancing; // in 18 decimals
    address public swapper; 

    uint64 public constant HUNDRED_PERCENT_LIMIT = 1_000_000_000;

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
    event RefillRateUpdated(uint64 oldRate, uint64 newRate);
    event RateLimitCapacityUpdated(uint64 oldCapacity, uint64 newCapacity);
    event TokenMaxPercentageLimitUpdated(uint64 oldPercentage, uint64 newPercentage);
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
    error RateLimitExceeded();
    error RateLimitRefillRateCannotBeGreaterThanCapacity();
    error PercentageCannotBeGreaterThanHundred();
    error TokenMaxPercentageBreached();
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
        address __governor,
        address __rebalancer,
        address __swapper
    ) public initializer {
        __ERC20_init(__name, __symbol);
        __ERC20Permit_init(__name);
        __UUPSUpgradeable_init();

        _setGovernor(__governor);
        rebalancer = __rebalancer;
        swapper = __swapper;

        // 1_000_000_000 = 100% for limiter
        // Limit = 3_000_000_000 -> 300% of total suppply, refill rate -> 1_000_000 -> 0.1%, so will be refilled in 3000 sec (50 mins)
        rateLimit = BucketLimiter.create(3_000_000_000, 1_000_000);
        emit RateLimitCapacityUpdated(0, 3_000_000_000);
        emit RefillRateUpdated(0, 1_000_000);

        // 0.5%
        maxAcceptableSlippageForRebalancing = 0.995 ether;
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

        isValidRebalanceOutputToken[_token] = _shouldWhitelist;
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
        if (!isValidRebalanceOutputToken[_toAsset]) revert NotAValidRebalanceOutputToken();
        
        uint256 vaultTotalValueBefore = getVaultTokenValuesInEth(totalSupply());
        uint256 toAssetAmountBefore = IERC20(_toAsset).balanceOf(address(this));
        IERC20(_fromAsset).safeTransfer(swapper, _fromAssetAmount);
        uint256 outAmount = ISwapper(swapper).swap(_fromAsset, _toAsset, _fromAssetAmount, _minToAssetAmount, _data);

        uint256 vaultTotalValueAfter = getVaultTokenValuesInEth(totalSupply());
        uint256 toAssetAmountAfter = IERC20(_toAsset).balanceOf(address(this));

        if (toAssetAmountAfter - toAssetAmountBefore < _minToAssetAmount) revert InsufficientTokensReceivedFromSwapper();
        if (vaultTotalValueAfter < vaultTotalValueBefore) {
            uint256 slippageApplicableInPercentage = ((vaultTotalValueBefore - vaultTotalValueAfter) * 100 ether) / vaultTotalValueBefore;
            if (slippageApplicableInPercentage > maxAcceptableSlippageForRebalancing) revert ApplicableSlippageGreaterThanMaxLimit();
        }

        emit Rebalance(_fromAsset, _toAsset, _fromAssetAmount, outAmount);
    }

    function registerToken(address _token, uint64 _maxPercentageInVault) external onlyGovernor {
        if (_token == address(0)) revert InvalidValue();
        if (isTokenRegistered(_token)) revert TokenAlreadyRegistered();
        if (IPriceProvider(priceProvider).getPriceInEth(_token) == 0)
            revert PriceProviderNotConfigured();
        if (_maxPercentageInVault > HUNDRED_PERCENT_LIMIT) revert PercentageCannotBeGreaterThanHundred();

        tokenInfos[_token] = TokenInfo({registered: true, whitelisted: true, maxPercentageInVault: _maxPercentageInVault});
        tokens.push(_token);

        emit TokenRegistered(_token);
        emit TokenWhitelisted(_token, true);
    }

    function setRebalancer(address account) external onlyGovernor {
        if (account == address(0)) revert InvalidValue();
        emit RebalancerSet(rebalancer, account);
        rebalancer = account;
    }

    function setMaxAcceptableSlippageForRebalancing(uint256 maxSlippage) external onlyRebalancer {
        if (maxSlippage == 0) revert InvalidValue();
        emit MaxSlippageForRebalanceSet(maxAcceptableSlippageForRebalancing, maxSlippage);
        maxAcceptableSlippageForRebalancing = maxSlippage;
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

    function updateMaxPercentageInVault(address _token, uint64 _maxPercentageInVault) external onlyGovernor {
        if (_token == address(0)) revert InvalidValue();
        if (!isTokenRegistered(_token)) revert TokenNotRegistered();
        if (_maxPercentageInVault > HUNDRED_PERCENT_LIMIT) revert PercentageCannotBeGreaterThanHundred();
        emit TokenMaxPercentageLimitUpdated(tokenInfos[_token].maxPercentageInVault, _maxPercentageInVault);
        tokenInfos[_token].maxPercentageInVault = _maxPercentageInVault;
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
    ) external onlyDepositors {
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

        _checkPercentagesInVault();

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

        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).safeTransfer(msg.sender, assetAmounts[i]);
        }

        emit Redeem(msg.sender, vaultShares, assets, assetAmounts);
    }

    function previewDeposit(
        address[] memory _tokens,
        uint256[] memory _amounts
    ) public view returns (uint256) {
        uint256 rewardsValueInEth = getAvsTokenValuesInEth(_tokens, _amounts);
        return _convertToShares(rewardsValueInEth, Math.Rounding.Floor);
    }

    function assetOf(
        address user,
        address avsToken
    ) external view returns (uint256) {
        return assetForVaultShares(balanceOf(user), avsToken);
    }

    function assetsOf(
        address user
    ) external view returns (address[] memory, uint256[] memory) {
        return assetsForVaultShares(balanceOf(user));
    }

    function assetForVaultShares(
        uint256 vaultShares,
        address avsToken
    ) public view returns (uint256) {
        if (!isTokenRegistered(avsToken)) revert TokenNotRegistered();
        if (totalSupply() == 0) revert TotalSupplyZero();

        return
            _convertToAssetAmount(avsToken, vaultShares, Math.Rounding.Floor);
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

        assembly {
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

        assembly {
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

    function getAvsTokenValuesInEth(
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

    function getAvsTokenTotalValuesInEth(
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
        uint256 totalValue = getAvsTokenValuesInEth(assets, assetAmounts);
        return (totalValue * vaultTokenShares) / totalSupply;
    }

    function getPercentagesInVault() public view returns (uint64[] memory) {
        uint256 len = tokens.length;
        uint64[] memory percentagesInVault = new uint64[](len);
        uint256 vaultTotalValue = getVaultTokenValuesInEth(totalSupply());

        for (uint256 i = 0; i < len; ) {
            uint256 valueOfTokenInVault = getAvsTokenTotalValuesInEth(tokens[i]);
            percentagesInVault[i] = SafeCast.toUint64((valueOfTokenInVault * HUNDRED_PERCENT_LIMIT) / vaultTotalValue);
            unchecked {
                ++i;
            }
        }

        return percentagesInVault;
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

    function _checkPercentagesInVault() internal view {
        uint256 len = tokens.length;
        uint64[] memory percentagesInVault = new uint64[](len);
        uint256 vaultTotalValue = getVaultTokenValuesInEth(totalSupply());

        if(vaultTotalValue == 0) return;

        for (uint256 i = 0; i < len; ) {
            uint256 valueOfTokenInVault = getAvsTokenTotalValuesInEth(tokens[i]);
            percentagesInVault[i] = SafeCast.toUint64((valueOfTokenInVault * HUNDRED_PERCENT_LIMIT) / vaultTotalValue);
            if (percentagesInVault[i] > tokenInfos[tokens[i]].maxPercentageInVault) revert TokenMaxPercentageBreached();
            unchecked {
                ++i;
            }
        }
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
