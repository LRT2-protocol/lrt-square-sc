// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BoringVaultPriceProvider} from "../src/BoringVaultPriceProvider.sol";
import {Utils, ChainConfig} from "./Utils.sol";

contract DeployBoringVaultPriceProvider is Utils {
    address owner = 0xF46D3734564ef9a5a16fC3B1216831a28f78e2B5;
    address priceProvider = 0x2B90103cdc9Bba6c0dBCAaF961F0B5b1920F19E3;

    address eEigen = 0xE77076518A813616315EaAba6cA8e595E845EeE9;
    address sEthFi = 0x86B5780b606940Eb59A062aA85a07959518c0161;
    address eigen = 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83;
    address ethFi = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;

    BoringVaultPriceProvider boringVaultPriceProvider;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address[] memory vaultTokens = new address[](2);
        vaultTokens[0] = eEigen;
        vaultTokens[1] = sEthFi;

        address[] memory underlyingTokens = new address[](2);
        underlyingTokens[0] = eigen;
        underlyingTokens[1] = ethFi;

        uint8[] memory priceDecimals = new uint8[](2);
        priceDecimals[0] = 18;
        priceDecimals[1] = 18;

        boringVaultPriceProvider = new BoringVaultPriceProvider(owner, priceProvider, vaultTokens, underlyingTokens, priceDecimals);
        vm.stopBroadcast();
    }
}