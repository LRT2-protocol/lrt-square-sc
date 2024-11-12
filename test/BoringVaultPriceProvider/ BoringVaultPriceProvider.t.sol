// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {PriceProvider} from "../../src/PriceProvider.sol";
import {BoringVaultPriceProvider, Ownable} from "../../src/BoringVaultPriceProvider.sol";

contract BoringVaultPriceProviderTest is Test {
    address owner = 0xF46D3734564ef9a5a16fC3B1216831a28f78e2B5;
    PriceProvider priceProvider = PriceProvider(0x2B90103cdc9Bba6c0dBCAaF961F0B5b1920F19E3);

    address eEigen = 0xE77076518A813616315EaAba6cA8e595E845EeE9;
    address sEthFi = 0x86B5780b606940Eb59A062aA85a07959518c0161;
    address eigen = 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83;
    address ethFi = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;
    
    BoringVaultPriceProvider boringVaultPriceProvider;

    function setUp() public {
        string memory mainnet = "https://eth-pokt.nodies.app";
        vm.createSelectFork(mainnet);

        vm.startPrank(owner);
        
        address[] memory vaultTokens = new address[](2);
        vaultTokens[0] = eEigen;
        vaultTokens[1] = sEthFi;

        address[] memory underlyingTokens = new address[](2);
        underlyingTokens[0] = eigen;
        underlyingTokens[1] = ethFi;

        uint8[] memory priceDecimals = new uint8[](2);
        priceDecimals[0] = 18;
        priceDecimals[1] = 18;

        boringVaultPriceProvider = new BoringVaultPriceProvider(owner, address(priceProvider), vaultTokens, underlyingTokens, priceDecimals);

        vm.stopPrank();
    }

    function test_VerifyDeployBoringVault() public view {
        assertEq(boringVaultPriceProvider.decimals(eEigen), 18);
        assertEq(boringVaultPriceProvider.decimals(sEthFi), 18);
        assertEq(boringVaultPriceProvider.vaultTokenToUnderlyingToken(eEigen), eigen);
        assertEq(boringVaultPriceProvider.vaultTokenToUnderlyingToken(sEthFi), ethFi);
    }

    function test_CanGetThePriceInEth() public view {
        assertGt(boringVaultPriceProvider.getPriceInEth(eEigen), 0);
        assertGt(boringVaultPriceProvider.getPriceInEth(sEthFi), 0);
    }

    function test_RevertsForTokensWhoseUnderlyingTokenIsNotSet() public {
        vm.prank(owner);
        vm.expectRevert(BoringVaultPriceProvider.TokenUnderlyingAssetNotSet.selector);
        boringVaultPriceProvider.getPriceInEth(eigen);
    }

    function test_CannotSetUnderlyingTokenIfPriceProviderIsNotConfigured() public {
        address[] memory vaultTokens = new address[](1);
        vaultTokens[0] = eigen;

        address[] memory underlyingTokens = new address[](1);
        underlyingTokens[0] = eEigen;

        uint8[] memory priceDecimals = new uint8[](1);
        priceDecimals[0] = 18;

        vm.prank(owner);
        vm.expectRevert(PriceProvider.TokenOracleNotSet.selector);
        boringVaultPriceProvider.setVaultTokenToUnderlyingToken(vaultTokens, underlyingTokens, priceDecimals);
    }

    function test_CannotSetZeroAddressAsVaultTokenOrUnderlyingToken() public {
        address[] memory vaultTokens = new address[](1);
        vaultTokens[0] = address(0);

        address[] memory underlyingTokens = new address[](1);
        underlyingTokens[0] = eigen;

        uint8[] memory priceDecimals = new uint8[](1);
        priceDecimals[0] = 18;
        
        vm.prank(owner);
        vm.expectRevert(BoringVaultPriceProvider.TokenCannotBeZeroAddress.selector);
        boringVaultPriceProvider.setVaultTokenToUnderlyingToken(vaultTokens, underlyingTokens, priceDecimals);
        
        vaultTokens[0] = eEigen;
        underlyingTokens[0] = address(0);
        vm.prank(owner);
        vm.expectRevert(BoringVaultPriceProvider.TokenCannotBeZeroAddress.selector);
        boringVaultPriceProvider.setVaultTokenToUnderlyingToken(vaultTokens, underlyingTokens, priceDecimals);
    }

    function test_OnlyOwnerCanSetVaultTokenToUnderlyingToken() public {
        address[] memory vaultTokens = new address[](2);
        vaultTokens[0] = eEigen;
        vaultTokens[1] = sEthFi;

        address[] memory underlyingTokens = new address[](2);
        underlyingTokens[0] = eigen;
        underlyingTokens[1] = ethFi;

        uint8[] memory priceDecimals = new uint8[](2);
        priceDecimals[0] = 18;
        priceDecimals[1] = 18;

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));
        boringVaultPriceProvider.setVaultTokenToUnderlyingToken(vaultTokens, underlyingTokens, priceDecimals);
    }

    function test_CanSetPriceProvider() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BoringVaultPriceProvider.PriceProviderSet(address(priceProvider), address(1));
        boringVaultPriceProvider.setPriceProvider(address(1));

        assertEq(address(boringVaultPriceProvider.priceProvider()), address(1));
    }

    function test_OnlyOwnerCanSetPriceProvider() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));
        boringVaultPriceProvider.setPriceProvider(address(1));
    }

    function test_CannotSetZeroAddressAsPriceProvider() public {
        vm.prank(owner);
        vm.expectRevert(BoringVaultPriceProvider.PriceProviderCannotBeZeroAddress.selector);
        boringVaultPriceProvider.setPriceProvider(address(0));
    }
}