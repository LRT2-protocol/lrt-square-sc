// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

struct ChainConfig {
    address owner;
    address treasury;
    address rebalancer;
    address[] pauser;
    address ethfi;
    address eigen;
    // address ethfiChainlinkOracle;
    address eigenChainlinkOracle;
    address ethUsdChainlinkOracle;
    address swapRouter1InchV6;
    uint48 depositFeeInBps;
    uint48 redeemFeeInBps;
    address cumulativeDropOwner;
    address cumulativeDropPauser;
    address cumulativeMerkleDrop;
    address lrt2Token;
    address oftAdapter;
    address lzEndpoint;
    address sendLib;
    address receiveLib;
    address lzDVN;
    address nethermindDVN;
    uint32 eid;
}

contract Utils is Script {
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint64 public constant HUNDRED_PERCENT_LIMIT = 1_000_000_000;
    address public constant L2_CREATE3_DEPLOYER = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    address public constant OPERATING_ADMIN_ADDRESS = 0xd8F3803d8412e61e04F53e1C9394e13eC8b32550;

    string[] public chainIds = ["1", "1923", "8453", "42161"];

    function getChainConfig(
        string memory chainId
    ) internal view returns (ChainConfig memory) {
        string memory dir = string.concat(
            vm.projectRoot(),
            "/deployments/fixtures/"
        );
        string memory file = string.concat("fixture", ".json");

        string memory inputJson = vm.readFile(string.concat(dir, file));

        ChainConfig memory config;

        config.owner = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "owner")
        );

        config.treasury = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "treasury")
        );

        config.rebalancer = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "rebalancer")
        );

        config.pauser = stdJson.readAddressArray(
            inputJson,
            string.concat(".", chainId, ".", "pauser")
        );
        
        config.ethfi = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "ethfi")
        );
        
        config.eigen = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "eigen")
        );
        
        // config.ethfiChainlinkOracle = stdJson.readAddress(
        //     inputJson,
        //     string.concat(".", chainId, ".", "ethfiChainlinkOracle")
        // );
        
        config.eigenChainlinkOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "eigenChainlinkOracle")
        );
        
        config.ethUsdChainlinkOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "ethUsdChainlinkOracle")
        );

        config.swapRouter1InchV6 = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "swapRouter1InchV6")
        );

        config.depositFeeInBps = uint48(stdJson.readUint(
            inputJson, 
            string.concat(".", chainId, ".", "depositFeeInBps")
        ));

        config.redeemFeeInBps = uint48(stdJson.readUint(
            inputJson, 
            string.concat(".", chainId, ".", "redeemFeeInBps")
        ));

        config.cumulativeDropOwner = address(stdJson.readAddress(
            inputJson, 
            string.concat(".", chainId, ".", "cumulativeDropOwner")
        ));

        config.cumulativeDropPauser = address(stdJson.readAddress(
            inputJson, 
            string.concat(".", chainId, ".", "cumulativeDropPauser")
        ));

        config.cumulativeMerkleDrop = address(stdJson.readAddress(
            inputJson, 
            string.concat(".", chainId, ".", "cumulativeMerkleDrop")
        ));

        config.lrt2Token = address(stdJson.readAddress(
            inputJson, 
            string.concat(".", chainId, ".", "lrt2Token")
        ));

        config.oftAdapter = address(stdJson.readAddress(
            inputJson, 
            string.concat(".", chainId, ".", "oftAdapter")
        ));

        config.lzEndpoint = address(stdJson.readAddress(
            inputJson, 
            string.concat(".", chainId, ".", "lzEndpoint")
        ));

        config.sendLib = address(stdJson.readAddress(
            inputJson, 
            string.concat(".", chainId, ".", "sendLib")
        ));

        config.receiveLib = address(stdJson.readAddress(    
            inputJson, 
            string.concat(".", chainId, ".", "receiveLib")
        ));

        config.lzDVN = address(stdJson.readAddress(
            inputJson, 
            string.concat(".", chainId, ".", "lzDVN")
        ));

        config.nethermindDVN = address(stdJson.readAddress(
            inputJson, 
            string.concat(".", chainId, ".", "nethermindDVN")
        ));

        config.eid = uint32(stdJson.readUint(
            inputJson, 
            string.concat(".", chainId, ".", "eid")
        ));
        
        return config;
    }

    function readDeploymentFile() internal view returns (string memory) {
        string memory dir = string.concat(vm.projectRoot(), "/deployments/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat("deployments", ".json");
        return vm.readFile(string.concat(dir, chainDir, file));
    }

    function writeDeploymentFile(string memory output) internal {
        string memory dir = string.concat(vm.projectRoot(), "/deployments/");
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory file = string.concat("deployments", ".json");
        vm.writeJson(output, string.concat(dir, chainDir, file));
    }

    function getQuoteOneInch(
        string memory chainId,
        address from,
        address to,
        address srcToken,
        address dstToken,
        uint256 amount
    ) internal returns (bytes memory data) {
        string[] memory inputs = new string[](9);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "test/getQuote1Inch.ts";
        inputs[3] = chainId;
        inputs[4] = vm.toString(from);
        inputs[5] = vm.toString(to);
        inputs[6] = vm.toString(srcToken);
        inputs[7] = vm.toString(dstToken);
        inputs[8] = vm.toString(amount);

        return vm.ffi(inputs);
    }

    function toBytes32(address addressValue) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addressValue)));
    }

    // Set a base config
    function getDVNConfig(address lzDVN, address nethermindDVN, uint32 targetEid) internal pure returns (SetConfigParam[] memory) {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](2);
        if (lzDVN < nethermindDVN) {
            requiredDVNs[0] = lzDVN;
            requiredDVNs[1] = nethermindDVN;
        } else {
            requiredDVNs[0] = nethermindDVN;
            requiredDVNs[1] = lzDVN;
        }

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 15,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(targetEid, 2, abi.encode(ulnConfig));

        return params;
    }

    // Add this helper function for string comparison
    function stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
