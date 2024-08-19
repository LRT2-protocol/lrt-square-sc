// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

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

contract LrtSquare is Initializable, ERC20VotesUpgradeable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct TokenInfo {
        bool registered;
        bool whitelisted;
    }

    mapping(address => TokenInfo) public tokenInfos;
    address[] public tokens;

    event TokenRegistered(address token);
    event TokenWhitelistUpdated(address token, bool whitelisted);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function mint(address to, uint256 shareToMint) external onlyOwner {
        _mint(to, shareToMint);
    }

    function registerToken(address _token, bool _whitelisted) external onlyOwner {
        require(!tokenInfos[_token].registered, "TOKEN_ALREADY_REGISTERED");

        tokenInfos[_token] = TokenInfo({registered: true, whitelisted: _whitelisted});
        
        emit TokenRegistered(_token);
        emit TokenWhitelistUpdated(_token, _whitelisted);
    }

    function updateWhitelist(address token) external onlyOwner {
        require(!isTokenRegistered[token], "TOKEN_ALREADY_REGISTERED");

        isTokenRegistered[token] = true;
        tokens.push(token);
    }

    /// @notice Deposit rewards to the contract and mint share tokens to the recipient.
    /// @param _tokens addresses of ERC20 tokens to deposit
    /// @param amounts amounts of tokens to deposit
    /// @param shareToMint amount of share token (= LRT^2 token) to mint
    /// @param recipientForMintedShare recipient of the minted share token
    function distributeRewards(address[] memory _tokens, uint256[] memory amounts, uint256 shareToMint, address recipientForMintedShare) external onlyOwner {
        require(_tokens.length == amounts.length, "INVALID_INPUT");

        for (uint256 i = 0; i < _tokens.length; i++) {
            require(isTokenRegistered[_tokens[i]], "TOKEN_NOT_REGISTERED");

            IERC20(_tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);
        }

        if (recipientForMintedShare != address(0)) {
            _mint(recipientForMintedShare, shareToMint);
        }
    }

    /// @notice Redeem the underlying assets proportionate to the share of the caller.
    /// @param vaultShares amount of vault share token to redeem the underlying assets
    function redeem(uint256 vaultShares) external {
        require(balanceOf(msg.sender) >= vaultShares, "INSUFFICIENT_SHARE");

        (address[] memory assets, uint256[] memory assetAmounts) = assetsForVaultShares(vaultShares);

        _burn(msg.sender, vaultShares);

        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).safeTransfer(msg.sender, assetAmounts[i]);
        }
    }

    function assetOf(address user, address token) external view returns (uint256) {
        return assetForVaultShares(balanceOf(user), token);
    }

    function assetsOf(address user) external view returns (address[] memory, uint256[] memory) {
        return assetsForVaultShares(balanceOf(user));
    }

    function assetForVaultShares(uint256 vaultShares, address rewardsToken) public view returns (uint256) {
        require(isTokenRegistered[rewardsToken], "TOKEN_NOT_REGISTERED");
        require(totalSupply() > 0, "ZERO_SUPPLY");

        return _convertToAssetAmount(rewardsToken, vaultShares, Math.Rounding.Zero);
    }

    function assetsForVaultShares(uint256 share) public view returns (address[] memory, uint256[] memory) {
        require(totalSupply() > 0, "ZERO_SUPPLY");

        address[] memory assets = new address[](tokens.length);
        uint256[] memory assetAmounts = new uint256[](tokens.length);
        uint256 cnt = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isTokenRegistered[tokens[i]]) {
                continue;
            }
            assets[cnt] = tokens[i];
            assetAmounts[cnt] = assetForVaultShares(share, tokens[i]);
            cnt++;
        }

        assembly {
            mstore(assets, cnt)
            mstore(assetAmounts, cnt)
        }

        return (assets, assetAmounts);
    }

    function totalAssets() external view returns (address[] memory, uint256[] memory) {
        require(totalSupply() > 0, "ZERO_SUPPLY");

        address[] memory assets = new address[](tokens.length);
        uint256[] memory assetAmounts = new uint256[](tokens.length);
        uint256 cnt = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isTokenRegistered[tokens[i]]) {
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


    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssetAmount(address assetToken, uint256 vaultShares, Math.Rounding rounding) internal view virtual returns (uint256) {
        return vaultShares.mulDiv(IERC20(assetToken).balanceOf(address(this)) + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }
}
