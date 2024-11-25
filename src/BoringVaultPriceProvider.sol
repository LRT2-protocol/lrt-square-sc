// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPriceProvider} from "./interfaces/IPriceProvider.sol";

interface BeforeTransferHook {}

interface IBoringVault {
    function hook() external view returns (BeforeTransferHook);
}

interface ITellerWithMultiAssetSupport {
    function accountant() external view returns (IAccountant);
}

interface IAccountant {
    function getRateInQuoteSafe(ERC20 quote) external view returns (uint256 rateInQuote);
}

contract BoringVaultPriceProvider is Ownable {
    using Math for uint256;

    IPriceProvider public priceProvider;
    mapping (address token => address underlyingToken) public vaultTokenToUnderlyingToken;
    mapping (address token => uint8 priceDecimals) public decimals;

    event VaultTokenToUnderlyingTokenSet(address indexed vaultToken, address indexed underlyingToken, uint8 priceDecimals);
    event PriceProviderSet(address indexed oldProvider, address indexed newProvider);

    error ArrayLengthMismatch();
    error TokenCannotBeZeroAddress();
    error PriceProviderCannotBeZeroAddress();
    error PriceProviderNotConfigured();
    error TokenUnderlyingAssetNotSet();

    constructor(
        address _owner, 
        address _priceProvider, 
        address[] memory vaultTokens, 
        address[] memory underlyingTokens, 
        uint8[] memory priceDecimals
    ) Ownable(_owner) {
        priceProvider = IPriceProvider(_priceProvider);
        _setVaultTokenToUnderlyingToken(vaultTokens, underlyingTokens, priceDecimals);
    }

    function getPriceInEth(address token) external view returns (uint256) {
        if (vaultTokenToUnderlyingToken[token] == address(0)) revert TokenUnderlyingAssetNotSet();
        ITellerWithMultiAssetSupport teller = ITellerWithMultiAssetSupport(address(IBoringVault(token).hook()));
        IAccountant accountant = teller.accountant();
        uint256 exchangeRate = accountant.getRateInQuoteSafe(ERC20(vaultTokenToUnderlyingToken[token]));
        uint256 underlyingTokenPriceInEth = priceProvider.getPriceInEth(vaultTokenToUnderlyingToken[token]);
        return underlyingTokenPriceInEth.mulDiv(exchangeRate, 1 ether);
    }

    function setVaultTokenToUnderlyingToken(
        address[] memory vaultTokens, 
        address[] memory underlyingTokens, 
        uint8[] memory priceDecimals
    ) external onlyOwner {
        _setVaultTokenToUnderlyingToken(vaultTokens, underlyingTokens, priceDecimals);
    }

    function setPriceProvider(address _priceProvider) external onlyOwner {
        if (_priceProvider == address(0)) revert PriceProviderCannotBeZeroAddress();
        emit PriceProviderSet(address(priceProvider), _priceProvider);
        priceProvider = IPriceProvider(_priceProvider);
    }

    function _setVaultTokenToUnderlyingToken(address[] memory vaultTokens, address[] memory underlyingTokens, uint8[] memory priceDecimals) internal {
        uint256 len = vaultTokens.length;
        if (len != underlyingTokens.length && len != priceDecimals.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < len; ) {
            if (vaultTokens[i] == address(0) || underlyingTokens[i] == address(0)) revert TokenCannotBeZeroAddress();
            if (priceProvider.getPriceInEth(underlyingTokens[i]) == 0) revert PriceProviderNotConfigured();

            vaultTokenToUnderlyingToken[vaultTokens[i]] = underlyingTokens[i];
            decimals[vaultTokens[i]] = priceDecimals[i]; 
            emit VaultTokenToUnderlyingTokenSet(vaultTokens[i], underlyingTokens[i], priceDecimals[i]);

            unchecked {
                ++i;
            }
        }
    }
}