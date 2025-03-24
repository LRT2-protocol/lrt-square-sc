// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {CumulativeMerkleDrop} from "../src/merkle-drop/CumulativeMerkleDrop.sol";
import {UUPSProxy} from "../src/UUPSProxy.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import "../utils/GnosisHelpers.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {UUPSUpgradeable, Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract GenerateMainnetMerkleUpgradeTransactions is Utils, GnosisHelpers {

    address constant NEW_MERKLE_DROP_IMPL = 0x5E226B1De8b0F387d7C77f78CBa2571D2a1be511;

    function run() public {

        ChainConfig memory config = getChainConfig("1");
        ChainConfig memory swellConfig = getChainConfig("1923");

        string memory MainnetJson = _getGnosisHeader("1");

        // upgrade implementation and initialize layerzero
        bytes memory upgradeAndInitLZHexData = abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, NEW_MERKLE_DROP_IMPL, abi.encodeWithSelector(CumulativeMerkleDrop.initializeLayerZero.selector, 1));
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(config.cumulativeMerkleDrop, upgradeAndInitLZHexData, false));

        // add swell as a peer
        bytes memory addSwellHexData = abi.encodeWithSelector(CumulativeMerkleDrop.addChain.selector, swellConfig.eid, 170_000, toBytes32(swellConfig.cumulativeMerkleDrop));
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(config.cumulativeMerkleDrop, addSwellHexData, false));

        // make canadian ledger the delegate
        bytes memory setDelegateHexData = abi.encodeWithSelector(ILayerZeroEndpointV2.setDelegate.selector, OPERATING_ADMIN_ADDRESS);
        MainnetJson = string.concat(MainnetJson, _getGnosisTransaction(config.cumulativeMerkleDrop, setDelegateHexData, true));

        // write to file
        vm.writeJson(MainnetJson, "./output/MainnetMerkleUpgradeTransactions.json");
    }
}
