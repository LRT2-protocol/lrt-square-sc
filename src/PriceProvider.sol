// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IPriceProvider} from "./interfaces/IPriceProvider.sol";
import {Governable} from "./governance/Governable.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract PriceProvider is IPriceProvider, Governable {
    using Math for uint256;

    enum ReturnType {
        Int256,
        Uint256
    }

    struct Config {
        address oracle;
        bytes priceFunctionCalldata;
        bool isChainlinkType;
        uint8 oraclePriceDecimals;
        uint24 maxStaleness;
        ReturnType dataType;
        bool isBaseTokenEth;
    }

    // ETH to USD price
    address public constant ETH_USD_ORACLE_SELECTOR =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    mapping(address token => Config tokenConfig) public tokenConfig;

    event TokenConfigSet(address[] tokens, Config[] configs);

    error TokenOracleNotSet();
    error PriceOracleFailed();
    error InvalidPrice();
    error OraclePriceTooOld();

    constructor(
        address __governor,
        address[] memory __tokens,
        Config[] memory __configs
    ) Governable() {
        _setTokenConfig(__tokens, __configs);
        _setGovernor(__governor);
    }

    function setTokenConfig(
        address[] memory _tokens,
        Config[] memory _configs
    ) external onlyGovernor {
        _setTokenConfig(_tokens, _configs);
    }

    function getPriceInEth(address token) external view returns (uint256) {
        if (token == ETH_USD_ORACLE_SELECTOR) return 1 ether;

        (uint256 price, bool isBaseEth, uint8 priceDecimals) = _getPrice(token);

        if (!isBaseEth) {
            (uint256 ethUsdPrice, uint8 ethPriceDecimals) = getEthUsdPrice();

            return
                price.mulDiv(
                    10 ** (ethPriceDecimals + decimals()),
                    ethUsdPrice * 10 ** priceDecimals,
                    Math.Rounding.Floor
                );
        }

        return
            price.mulDiv(
                10 ** decimals(),
                10 ** priceDecimals,
                Math.Rounding.Floor
            );
    }

    function getEthUsdPrice() public view returns (uint256, uint8) {
        (uint256 price, , uint8 priceDecimals) = _getPrice(
            ETH_USD_ORACLE_SELECTOR
        );
        return (price, priceDecimals);
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function _getPrice(
        address token
    ) internal view returns (uint256, bool, uint8) {
        Config memory config = tokenConfig[token];
        if (config.oracle == address(0)) revert TokenOracleNotSet();

        if (config.isChainlinkType) {
            (, int256 priceInt256, , uint256 updatedAt, ) = IAggregatorV3(
                config.oracle
            ).latestRoundData();

            if (block.timestamp > updatedAt + config.maxStaleness)
                revert OraclePriceTooOld();
            if (priceInt256 <= 0) revert InvalidPrice();

            return (
                uint256(priceInt256),
                config.isBaseTokenEth,
                config.oraclePriceDecimals
            );
        }

        (bool success, bytes memory data) = address(config.oracle).staticcall(
            config.priceFunctionCalldata
        );

        if (!success) revert PriceOracleFailed();

        uint256 price;
        if (config.dataType == ReturnType.Int256) {
            int256 priceInt256 = abi.decode(data, (int256));
            if (priceInt256 <= 0) revert InvalidPrice();
            price = uint256(priceInt256);
        } else price = abi.decode(data, (uint256));

        return (price, config.isBaseTokenEth, config.oraclePriceDecimals);
    }

    function _setTokenConfig(
        address[] memory _tokens,
        Config[] memory _configs
    ) internal {
        uint256 len = _tokens.length;
        require(len == _configs.length, "ARRAY_LENGTH_MISMATCH");

        for (uint256 i = 0; i < len; ) {
            tokenConfig[_tokens[i]] = _configs[i];
            unchecked {
                ++i;
            }
        }

        emit TokenConfigSet(_tokens, _configs);
    }
}
