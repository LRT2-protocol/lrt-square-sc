// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {CumulativeMerkleDrop} from "../src/merkle-drop/CumulativeMerkleDrop.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSProxy} from "../src/UUPSProxy.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import "../utils/GnosisHelpers.sol";

contract GenerateTransactionsAddBaseArb is Utils, GnosisHelpers {

    function run() public {

        ChainConfig memory mainnetConfig = getChainConfig("1");
        ChainConfig memory swellConfig = getChainConfig("1923");
        ChainConfig memory arbitrumConfig = getChainConfig("42161");
        ChainConfig memory baseConfig = getChainConfig("8453");

        /// accept ownership of cumulative merkle drop {base, arbitrum}

        string memory BaseJson = _getGnosisHeader("8453");

        bytes memory acceptOwnershipHexData = abi.encodeWithSelector(AccessControlDefaultAdminRulesUpgradeable.acceptDefaultAdminTransfer.selector);
        BaseJson = string.concat(BaseJson, _getGnosisTransaction(baseConfig.cumulativeMerkleDrop, acceptOwnershipHexData, true));

        vm.writeJson(BaseJson, "./output/BaseAcceptOwnership.json");

        string memory ArbitrumJson = _getGnosisHeader("42161");

        acceptOwnershipHexData = abi.encodeWithSelector(AccessControlDefaultAdminRulesUpgradeable.acceptDefaultAdminTransfer.selector);
        ArbitrumJson = string.concat(ArbitrumJson, _getGnosisTransaction(arbitrumConfig.cumulativeMerkleDrop, acceptOwnershipHexData, true));

        vm.writeJson(ArbitrumJson, "./output/ArbitrumAcceptOwnership.json");

        /// set peer transactions {mainnet, swell}

        string memory MainnetJson = _getGnosisHeader("1");

        bytes memory addArbitrumHexData = abi.encodeWithSelector(CumulativeMerkleDrop.addChain.selector, arbitrumConfig.eid, 170_000, toBytes32(arbitrumConfig.cumulativeMerkleDrop));
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(mainnetConfig.cumulativeMerkleDrop, addArbitrumHexData, false));

        bytes memory addBaseHexData = abi.encodeWithSelector(CumulativeMerkleDrop.addChain.selector, baseConfig.eid, 170_000, toBytes32(baseConfig.cumulativeMerkleDrop));
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(mainnetConfig.cumulativeMerkleDrop, addBaseHexData, true));

        vm.writeJson(MainnetJson, "./output/MainnetSetPeerTransactions.json");

        string memory SwellJson = _getGnosisHeader("1923");

        SwellJson = string.concat(SwellJson, _getGnosisTransaction(swellConfig.cumulativeMerkleDrop, addArbitrumHexData, false));
        SwellJson = string.concat(SwellJson, _getGnosisTransaction(swellConfig.cumulativeMerkleDrop, addBaseHexData, true));

        vm.writeJson(SwellJson, "./output/SwellSetPeerTransactions.json");
    }
}
