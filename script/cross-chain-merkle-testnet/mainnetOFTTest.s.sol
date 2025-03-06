// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {CumulativeMerkleDrop} from "../../src/merkle-drop/CumulativeMerkleDrop.sol";
import {UUPSProxy} from "../../src/UUPSProxy.sol";

import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {console} from "forge-std/console.sol";

contract DeploySepoliaMerkleDrop is Script {


    // forge script script/cross-chain-merkle-testnet/SepoliaDeployment.s.sol --rpc-url https://eth-sepolia.public.blastapi.io --via-ir
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // default to mainnet sepolia as the deployment is done on mainnet sepolia
        address DEPLOYMENT_LZ_ENDPOINT = MAINNET_SEPOLIA_LZ_ENDPOINT;
        uint32 DEPLOYMENT_PEER_EID = BASE_SEPOLIA_EID;
        address DEPLOYMENT_PEER_MERKLE = BASE_MERKLE;
        address DEPLOYMENT_SEND_LIB = MAINNET_SEPOLIA_SEND_LIB;
        address DEPLOYMENT_RECEIVE_LIB = MAINNET_SEPOLIA_RECEIVE_LIB;
        address KING_PROTOCOL_OWNER = 0xD0d7F8a5a86d8271ff87ff24145Cf40CEa9F7A39;
        address BASE_KING

        // 1. Deploy implementation
        address implementation = address(
            new CumulativeMerkleDrop(
                BASE_KING_TOKEN,
                DEPLOYMENT_LZ_ENDPOINT,
                OFT_ADAPTER
            )
        );

        // 2. Deploy proxy with implementation
        CumulativeMerkleDrop cumulativeMerkleDrop = CumulativeMerkleDrop(payable(address(
            new UUPSProxy(
                implementation,
                abi.encodeWithSelector(
                    CumulativeMerkleDrop.initialize.selector,
                    0,
                    KING_PROTOCOL_OWNER,
                    KING_PROTOCOL_OWNER
                )
            )
        )));

        // 3. Initialize LayerZero
        cumulativeMerkleDrop.initializeLayerZero();

        // 4. Grant admin role
        cumulativeMerkleDrop.grantRole(
            cumulativeMerkleDrop.OPERATING_ADMIN_ROLE(),
            KING_PROTOCOL_OWNER
        );

        // 5. Add mainnet chain as peer
        CumulativeMerkleDrop(payable(address(BASE_MERKLE))).addChain(
            DEPLOYMENT_PEER_EID,
            300_000, // gas limit
            bytes32(uint256(uint160(DEPLOYMENT_PEER_MERKLE)))
        );

        IMessageLibManager(DEPLOYMENT_LZ_ENDPOINT).setConfig(
            address(cumulativeMerkleDrop), 
            DEPLOYMENT_RECEIVE_LIB,
            getDVNConfig(DEPLOYMENT_PEER_EID)
        );
        IMessageLibManager(DEPLOYMENT_LZ_ENDPOINT).setConfig(
            address(cumulativeMerkleDrop), 
            DEPLOYMENT_SEND_LIB,
            getDVNConfig(DEPLOYMENT_PEER_EID)
        );

        vm.stopBroadcast();

        console.log("CumulativeMerkleDrop deployed to:", address(cumulativeMerkleDrop));
        console.log("Implementation deployed to:", implementation);

        address[] memory addresses = generateRandomAddresses(150);
        CumulativeMerkleDrop(payable(address(MAINNET_MERKLE))).batchSetClaimEid(addresses, BASE_SEPOLIA_EID);
    }

    function generateRandomAddresses(uint256 count) internal returns (address[] memory) {
        address[] memory addresses = new address[](count);
        
        for (uint256 i = 0; i < count; i++) {
            // Generate a random address using keccak256
            bytes32 hash = keccak256(abi.encodePacked(i));
            // Convert the first 20 bytes of the hash to an address
            addresses[i] = address(uint160(uint256(hash)));
        }
        
        return addresses;
    }

    function getDVNConfig(uint32 eid) internal view returns (SetConfigParam[] memory) {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = 0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193; // LZ DVN mainnet sepolia
        if (block.chainid == 84532) {
            requiredDVNs[0] = 0xe1a12515F9AB2764b887bF60B923Ca494EBbB2d6; // LZ DVN base sepolia
        }

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 15,
            requiredDVNCount: 1,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(eid, 2, abi.encode(ulnConfig));

        return params;
    }
}
