// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

struct ChainConfig {
    address owner;
    address rebalancer;
    address pauser;
    address ethfi;
    address eigen;
    address ethfiChainlinkOracle;
    address eigenChainlinkOracle;
    address ethUsdChainlinkOracle;
    address swapRouter1InchV6;
}

contract Utils is Script {
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
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

        return
            ChainConfig({
                owner: owner,
                rebalancer: rebalancer,
                pauser: pauser,
                ethfi: ethfi,
                eigen: eigen,
                ethfiChainlinkOracle: ethfiChainlinkOracle,
                eigenChainlinkOracle: eigenChainlinkOracle,
                ethUsdChainlinkOracle: ethUsdChainlinkOracle,
                swapRouter1InchV6: swapRouter1InchV6
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
}
