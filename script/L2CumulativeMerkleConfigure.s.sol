// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {CumulativeMerkleDrop} from "../src/merkle-drop/CumulativeMerkleDrop.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UUPSProxy} from "../src/UUPSProxy.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {console} from "forge-std/console.sol";
import {GnosisHelpers} from "../utils/GnosisHelpers.sol";

contract ConfigureL2CumulativeMerkle is Utils {

    function run() public {

        vm.startBroadcast();

        ChainConfig memory config = getChainConfig(vm.toString(block.chainid));
        CumulativeMerkleDrop cumulativeMerkle = CumulativeMerkleDrop(payable(config.cumulativeMerkleDrop));

        for (uint256 i = 0; i < chainIds.length; i++) {
            ChainConfig memory peerConfig = getChainConfig(chainIds[i]);

            if (stringsEqual(vm.toString(block.chainid), chainIds[i])) {
                continue;
            }

            console.log("Adding chain %s", chainIds[i]);
            
            cumulativeMerkle.addChain(peerConfig.eid, 170_000, toBytes32(peerConfig.cumulativeMerkleDrop));

            SetConfigParam[] memory params = getDVNConfig(config.lzDVN, config.nethermindDVN, peerConfig.eid);

            IMessageLibManager(config.lzEndpoint).setConfig(address(cumulativeMerkle), config.sendLib, params);
            IMessageLibManager(config.lzEndpoint).setConfig(address(cumulativeMerkle), config.receiveLib, params);
        }

        cumulativeMerkle.grantRole(cumulativeMerkle.OPERATING_ADMIN_ROLE(), OPERATING_ADMIN_ADDRESS);

        vm.stopBroadcast();
    }
}
