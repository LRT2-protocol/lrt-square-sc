// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredStorage, SafeERC20, IERC20, Math, BucketLimiter, IPriceProvider} from "./LRTSquaredStorage.sol";

contract LRTSquaredCore is LRTSquaredStorage {
    using BucketLimiter for BucketLimiter.Limit;
    using SafeERC20 for IERC20;
    using Math for uint256;

    function getRateLimit() external view returns (RateLimit memory) {
        RateLimit memory _rateLimit = rateLimit;
        _rateLimit.limit.getCurrent();
        return _rateLimit;
    }

    /// @notice Deposit rewards to the contract and mint share tokens to the recipient.
    /// @param _tokens addresses of ERC20 tokens to deposit
    /// @param _amounts amounts of tokens to deposit
    /// @param _receiver recipient of the minted share token
    function deposit(
        address[] memory _tokens,
        uint256[] memory _amounts,
        address _receiver
    ) external whenNotPaused onlyDepositors updateRateLimit {
        if (_tokens.length != _amounts.length) revert ArrayLengthMismatch();
        if (_receiver == address(0)) revert InvalidRecipient();

        bool initialDeposit = (totalSupply() == 0);
        uint256 vaultTokenValueBefore = _getVaultTokenValuesInEth(
            1 * 10 ** decimals()
        );

        (uint256 shareToMint, uint256 depositFee) = previewDeposit(_tokens, _amounts);        
        // if initial deposit, set renew timestamp to new timestamp
        if (initialDeposit) rateLimit.renewTimestamp = uint64(block.timestamp + rateLimit.timePeriod);
        // check rate limit
        if(!rateLimit.limit.consume(uint128(shareToMint + depositFee))) revert RateLimitExceeded();
        
        _deposit(_tokens, _amounts, shareToMint, depositFee, _receiver);

        _verifyPositionLimits();

        uint256 vaultTokenValueAfter = _getVaultTokenValuesInEth(
            1 * 10 ** decimals()
        );

        if (!initialDeposit && vaultTokenValueBefore > vaultTokenValueAfter) revert VaultTokenValueChanged();
        
        emit Deposit(msg.sender, _receiver, shareToMint, depositFee, _tokens, _amounts);
    }

    /// @notice Redeem the underlying assets proportionate to the share of the caller.
    /// @param vaultShares amount of vault share token to redeem the underlying assets
    function redeem(uint256 vaultShares) external {
        if (balanceOf(msg.sender) < vaultShares) revert InsufficientShares();
        
        (address[] memory assets, uint256[] memory assetAmounts, uint256 feeForRedemption) = previewRedeem(vaultShares);
        if (feeForRedemption != 0) _transfer(msg.sender, _fee.treasury, feeForRedemption);
        _burn(msg.sender, vaultShares - feeForRedemption);

        for (uint256 i = 0; i < assets.length; i++) 
            if (assetAmounts[i] > 0) IERC20(assets[i]).safeTransfer(msg.sender, assetAmounts[i]);

        emit Redeem(msg.sender, vaultShares, feeForRedemption, assets, assetAmounts);
    }

    function previewDeposit(address[] memory _tokens, uint256[] memory _amounts) public view returns (uint256, uint256) {
        uint256 rewardsValueInEth = getTokenValuesInEth(_tokens, _amounts);
        uint256 shareToMint = _convertToShares(rewardsValueInEth, Math.Rounding.Floor);
        uint256 feeForDeposit = shareToMint.mulDiv(_fee.depositFeeInBps, HUNDRED_PERCENT_IN_BPS);

        return (shareToMint - feeForDeposit, feeForDeposit);
    }

    function previewRedeem(uint256 vaultShares) public view returns (address[] memory, uint256[] memory, uint256) {
        uint256 feeForRedemption = vaultShares.mulDiv(_fee.redeemFeeInBps, HUNDRED_PERCENT_IN_BPS);
        (address[] memory assets, uint256[] memory assetAmounts) = assetsForVaultShares(vaultShares - feeForRedemption);

        return (assets, assetAmounts, feeForRedemption);
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

        return _convertToAssetAmount(token, vaultShares, Math.Rounding.Floor);
    }

    function assetsForVaultShares(
        uint256 vaultShare
    ) public view returns (address[] memory, uint256[] memory) {
        if (totalSupply() == 0) revert TotalSupplyZero();
        address[] memory assets = tokens;
        uint256 len = assets.length;
        uint256[] memory assetAmounts = new uint256[](len);
        for (uint256 i = 0; i < len; ) {
            assetAmounts[i] = assetForVaultShares(vaultShare, assets[i]);

            unchecked {
                ++i;
            }
        }

        return (assets, assetAmounts);
    }

    function tvl() external view returns (uint256, uint256) {
        (
            address[] memory assets,
            uint256[] memory assetAmounts
        ) = totalAssets();

        uint256 totalValue = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            totalValue +=
                (assetAmounts[i] * IPriceProvider(priceProvider).getPriceInEth(assets[i])) /
                    10 ** _getDecimals(assets[i]);
        }

        (uint256 ethUsdPrice, uint8 ethUsdDecimals) = IPriceProvider(priceProvider).getEthUsdPrice();
        uint256 totalValueInUsd = totalValue * ethUsdPrice / 10 ** ethUsdDecimals;

        return (totalValue, totalValueInUsd);
    }

    function fairValueOf(uint256 vaultTokenShares) external view returns (uint256, uint256) {
        uint256 valueInEth = _getVaultTokenValuesInEth(vaultTokenShares);
        (uint256 ethUsdPrice, uint8 ethUsdPriceDecimals) = IPriceProvider(priceProvider).getEthUsdPrice();
        if (ethUsdPrice == 0) revert PriceProviderFailed();
        uint256 valueInUsd = valueInEth * ethUsdPrice / 10 **  ethUsdPriceDecimals;

        return (valueInEth, valueInUsd);
    }

    function communityPause() external payable whenNotPaused {
        if (depositForCommunityPause == 0) revert CommunityPauseDepositNotSet();
        if (msg.value != depositForCommunityPause)
            revert IncorrectAmountOfEtherSent();

        _pause();
        communityPauseDepositedAmt = msg.value;
        emit CommunityPause(msg.sender);
    }

    function withdrawCommunityDepositedPauseAmount() external {
        uint256 amount = communityPauseDepositedAmt;

        if (amount == 0) revert NoCommunityPauseDepositAvailable();
        communityPauseDepositedAmt = 0;
        _withdrawEth(governor(), amount);

        emit CommunityPauseAmountWithdrawal(governor(), amount);
    }

    function positionWeightLimit() public view returns (address[] memory, uint64[] memory) {
        uint256 len = tokens.length;
        uint64[] memory positionWeightLimits = new uint64[](len);
        uint256 vaultTotalValue = _getVaultTokenValuesInEth(totalSupply());

        for (uint256 i = 0; i < len; ) {
            positionWeightLimits[i] = _getPositionWeight(tokens[i], vaultTotalValue);
            unchecked {
                ++i;
            }
        }

        return (tokens, positionWeightLimits);
    }

    function getPositionWeight(address token) public view returns (uint64) {
        if (!isTokenRegistered(token)) revert TokenNotRegistered();
        uint256 vaultTotalValue = _getVaultTokenValuesInEth(totalSupply());
        return _getPositionWeight(token, vaultTotalValue);
    }


    /// @notice Deposit rewards to the contract and mint share tokens to the recipient.
    /// @param _tokens addresses of ERC20 tokens to deposit
    /// @param amounts amounts of tokens to deposit
    /// @param shareToMint amount of share token (= LRT^2 token) to mint
    /// @param depositFee fee to mint to the treasury 
    /// @param recipientForMintedShare recipient of the minted share token
    function _deposit(
        address[] memory _tokens,
        uint256[] memory amounts,
        uint256 shareToMint,
        uint256 depositFee,
        address recipientForMintedShare
    ) internal {
        for (uint256 i = 0; i < _tokens.length; ) {
            if (!isTokenWhitelisted(_tokens[i])) revert TokenNotWhitelisted(); 
            IERC20(_tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);

            unchecked {
                ++i;
            }
        }

        if (depositFee != 0) _mint(_fee.treasury, depositFee);
        _mint(recipientForMintedShare, shareToMint);
    }

    function _convertToShares(
        uint256 valueInEth,
        Math.Rounding rounding
    ) public view virtual returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return valueInEth;

        return valueInEth.mulDiv(_totalSupply, _getVaultTokenValuesInEth(_totalSupply), rounding);
    }

    function _convertToAssetAmount(
        address assetToken,
        uint256 vaultShares,
        Math.Rounding rounding
    ) internal view virtual returns (uint256) {
        uint256 bal = IERC20(assetToken).balanceOf(address(this));
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) _totalSupply = 1;
        if (bal == 0) bal = 1;

        return vaultShares.mulDiv(bal, _totalSupply, rounding);
    }

    modifier onlyDepositors() {
        _onlyDepositors();
        _;
    }

    function _onlyDepositors() internal view {
        if (!depositor[msg.sender]) revert OnlyDepositors();
    }

    modifier updateRateLimit {
        _updateRateLimit();
        _;
    }

    function _updateRateLimit() internal {
        uint256 _totalSupply = totalSupply();
        if(_totalSupply == 0) return;
        
        // If total supply = 0, can't mint anything since new rate limit which is a percentage of total supply would be 0
        if (block.timestamp > rateLimit.renewTimestamp) {
            uint128 capactity = uint128(_totalSupply.mulDiv(rateLimit.percentageLimit, HUNDRED_PERCENT_LIMIT));
            rateLimit.limit = BucketLimiter.create(capactity, rateLimit.limit.refillRate);
            rateLimit.renewTimestamp = uint64(block.timestamp + rateLimit.timePeriod);
        }
    }

    /**
     * @dev Falldown to the admin implementation
     * @notice This is a catch all for all functions not declared in core
     */
    // solhint-disable-next-line no-complex-fallback
    fallback() external {
        bytes32 slot = adminImplPosition;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(
                gas(),
                sload(slot),
                0,
                calldatasize(),
                0,
                0
            )

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
} 