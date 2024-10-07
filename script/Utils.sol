// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

struct ChainConfig {
    address owner;
    address treasury;
    address rebalancer;
    address pauser;
    address ethfi;
    address eigen;
    address ethfiChainlinkOracle;
    address eigenChainlinkOracle;
    address ethUsdChainlinkOracle;
    address swapRouter1InchV6;
    uint48 depositFeeInBps;
    uint48 redeemFeeInBps;
}

contract Utils is Script {
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint64 public constant HUNDRED_PERCENT_LIMIT = 1_000_000_000;

    function getChainConfig(
        string memory chainId
    ) internal view returns (ChainConfig memory) {
        string memory dir = string.concat(
            vm.projectRoot(),
            "/deployments/fixtures/"
        );
        string memory file = string.concat("fixture", ".json");

        string memory inputJson = vm.readFile(string.concat(dir, file));

        address owner = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "owner")
        );

        address treasury = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "treasury")
        );

        address rebalancer = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "rebalancer")
        );

        address pauser = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "pauser")
        );
        
        address ethfi = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "ethfi")
        );
        
        address eigen = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "eigen")
        );
        
        address ethfiChainlinkOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "ethfiChainlinkOracle")
        );
        
        address eigenChainlinkOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "eigenChainlinkOracle")
        );
        
        address ethUsdChainlinkOracle = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "ethUsdChainlinkOracle")
        );

        address swapRouter1InchV6 = stdJson.readAddress(
            inputJson,
            string.concat(".", chainId, ".", "swapRouter1InchV6")
        );

        uint48 depositFeeInBps = uint48(stdJson.readUint(
            inputJson, 
            string.concat(".", chainId, ".", "depositFeeInBps")
        ));

        uint48 redeemFeeInBps = uint48(stdJson.readUint(
            inputJson, 
            string.concat(".", chainId, ".", "redeemFeeInBps")
        ));

        return
            ChainConfig({
                owner: owner,
                treasury: treasury,
                rebalancer: rebalancer,
                pauser: pauser,
                ethfi: ethfi,
                eigen: eigen,
                ethfiChainlinkOracle: ethfiChainlinkOracle,
                eigenChainlinkOracle: eigenChainlinkOracle,
                ethUsdChainlinkOracle: ethUsdChainlinkOracle,
                swapRouter1InchV6: swapRouter1InchV6,
                depositFeeInBps: depositFeeInBps,
                redeemFeeInBps: redeemFeeInBps
            });
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
}
