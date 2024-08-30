// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ERC20PermitUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {IPriceProvider} from "src/interfaces/IPriceProvider.sol";

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
    ERC20PermitUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct TokenInfo {
        bool registered;
        bool whitelisted;
        IPriceProvider priceProvider;
    }

    address public governor;
    mapping(address => TokenInfo) public tokenInfos;
    mapping(address => bool) public depositor;
    address[] public tokens;

    event TokenRegistered(address token);
    event TokenUpdated(
        address token,
        bool whitelisted,
        IPriceProvider priceProvider
    );
    event GovernorSet(address oldGovernor, address newGovernor);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        address _governor
    ) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        governor = _governor;
    }

    function mint(address to, uint256 shareToMint) external onlyOwner {
        _mint(to, shareToMint);
    }

    function registerToken(
        address _token,
        IPriceProvider _priceProvider
    ) external onlyGovernor {
        require(!isTokenRegistered(_token), "TOKEN_ALREADY_REGISTERED");

        tokenInfos[_token] = TokenInfo({
            registered: true,
            whitelisted: true,
            priceProvider: _priceProvider
        });
        tokens.push(_token);

        emit TokenRegistered(_token);
        emit TokenUpdated(_token, true, _priceProvider);
    }

    function updateWhitelist(
        address _token,
        bool _whitelist
    ) external onlyGovernor {
        require(isTokenRegistered(_token), "TOKEN_NOT_REGISTERED");

        tokenInfos[_token].whitelisted = _whitelist;

        emit TokenUpdated(_token, _whitelist, tokenInfos[_token].priceProvider);
    }

    function setDepositors(
        address[] memory depositors,
        bool[] memory isDepositor
    ) external onlyGovernor {
        uint256 len = depositors.length;
        require(len == isDepositor.length, "ARRAY_LENGTH_MISMATCH");
        for (uint256 i = 0; i < len; ) {
            depositor[depositors[i]] = isDepositor[i];

            unchecked {
                ++i;
            }
        }
    }

    function setGovernor(address _governor) external onlyGovernor {
        emit GovernorSet(governor, _governor);
        governor = _governor;
    }

    function updatePriceProvider(
        address _token,
        IPriceProvider _priceProvider
    ) external onlyGovernor {
        require(isTokenRegistered(_token), "TOKEN_NOT_REGISTERED");

        tokenInfos[_token].priceProvider = _priceProvider;

        emit TokenUpdated(
            _token,
            tokenInfos[_token].whitelisted,
            _priceProvider
        );
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
        require(_tokens.length == _amounts.length, "INVALID_INPUT");
        require(_receiver != address(0), "INVALID_RECIPIENT");

        bool initial_deposit = (totalSupply() == 0);
        uint256 before_VaultTokenValue = getVaultTokenValuesInUsd(
            1 * 10 ** decimals()
        );

        uint256 shareToMint = previewDeposit(_tokens, _amounts);
        _deposit(_tokens, _amounts, shareToMint, _receiver);

        uint256 after_VaultTokenValue = getVaultTokenValuesInUsd(
            1 * 10 ** decimals()
        );

        if (!initial_deposit) {
            require(
                before_VaultTokenValue == after_VaultTokenValue,
                "VAULT_TOKEN_VALUE_CHANGED"
            );
        }
    }

    /// @notice Redeem the underlying assets proportionate to the share of the caller.
    /// @param vaultShares amount of vault share token to redeem the underlying assets
    function redeem(uint256 vaultShares) external {
        require(balanceOf(msg.sender) >= vaultShares, "INSUFFICIENT_SHARE");

        (
            address[] memory assets,
            uint256[] memory assetAmounts
        ) = assetsForVaultShares(vaultShares);

        _burn(msg.sender, vaultShares);

        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).safeTransfer(msg.sender, assetAmounts[i]);
        }
    }

    function previewDeposit(
        address[] memory _tokens,
        uint256[] memory amounts
    ) public view returns (uint256) {
        uint256 rewardsValueInUsd = getAvsTokenValuesInUsd(_tokens, amounts);
        return _convertToShares(rewardsValueInUsd, Math.Rounding.Floor);
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
        require(isTokenRegistered(avsToken), "TOKEN_NOT_REGISTERED");
        require(totalSupply() > 0, "ZERO_SUPPLY");

        return
            _convertToAssetAmount(avsToken, vaultShares, Math.Rounding.Floor);
    }

    function assetsForVaultShares(
        uint256 vaultShare
    ) public view returns (address[] memory, uint256[] memory) {
        require(totalSupply() > 0, "ZERO_SUPPLY");

        address[] memory assets = new address[](tokens.length);
        uint256[] memory assetAmounts = new uint256[](tokens.length);
        uint256 cnt = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isTokenRegistered(tokens[i])) {
                continue;
            }
            assets[cnt] = tokens[i];
            assetAmounts[cnt] = assetForVaultShares(vaultShare, tokens[i]);
            cnt++;
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
        address[] memory assets = new address[](tokens.length);
        uint256[] memory assetAmounts = new uint256[](tokens.length);
        uint256 cnt = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isTokenWhitelisted(tokens[i])) {
                continue;
            }
            assets[cnt] = tokens[i];
            assetAmounts[cnt] = IERC20(tokens[i]).balanceOf(address(this));
            cnt++;
        }

        assembly {
            mstore(assets, cnt)
            mstore(assetAmounts, cnt)
        }

        return (assets, assetAmounts);
    }

    function totalAssetsValueInUsd() external view returns (uint256) {
        (
            address[] memory assets,
            uint256[] memory assetAmounts
        ) = totalAssets();

        uint256 totalValue = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            totalValue +=
                (assetAmounts[i] *
                    tokenInfos[assets[i]].priceProvider.getPriceInUsd()) /
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

    function getAvsTokenValuesInUsd(
        address[] memory _tokens,
        uint256[] memory amounts
    ) public view returns (uint256) {
        uint256 total_usd = 0;
        for (uint256 i = 0; i < _tokens.length; i++) {
            require(isTokenRegistered(_tokens[i]), "TOKEN_NOT_REGISTERED");
            require(isTokenWhitelisted(_tokens[i]), "TOKEN_NOT_WHITELISTED");
            TokenInfo memory tokenInfo = tokenInfos[_tokens[i]];

            uint256 tokenValueInUSDC = tokenInfo.priceProvider.getPriceInUsd();
            total_usd +=
                (amounts[i] * tokenValueInUSDC) /
                10 ** _getDecimals(_tokens[i]);
        }
        return total_usd;
    }

    function getVaultTokenValuesInUsd(
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
        uint256 totalValue = getAvsTokenValuesInUsd(assets, assetAmounts);
        return (totalValue * vaultTokenShares) / totalSupply;
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
            require(isTokenRegistered(_tokens[i]), "TOKEN_NOT_REGISTERED");

            IERC20(_tokens[i]).safeTransferFrom(
                msg.sender,
                address(this),
                amounts[i]
            );
        }

        _mint(recipientForMintedShare, shareToMint);
    }

    function _convertToShares(
        uint256 valueInUsd,
        Math.Rounding rounding
    ) public view virtual returns (uint256) {
        return
            valueInUsd.mulDiv(
                totalSupply() + 10 ** _decimalsOffset(),
                getVaultTokenValuesInUsd(totalSupply()) + 1,
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

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    modifier onlyGovernor() {
        _onlyGovernor();
        _;
    }

    function _onlyGovernor() internal view {
        require(msg.sender == governor, "ONLY_GOVERNOR");
    }

    modifier onlyDepositors() {
        _onlyDepositors();
        _;
    }

    function _onlyDepositors() internal view {
        require(depositor[msg.sender], "ONLY_DEPOSITORS");
    }
}
