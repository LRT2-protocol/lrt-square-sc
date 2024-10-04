// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LRTSquare} from "../src/LRTSquare.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract TestLRTSquare is Utils {
    using SafeERC20 for IERC20;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Start broadcast with deployer as the signer
        vm.startBroadcast(deployerPrivateKey);

        ChainConfig memory config = getChainConfig(vm.toString(block.chainid)); 
        IERC20 eigen = IERC20(config.eigen);
        IERC20 ethfi = IERC20(config.ethfi);

        string memory deployments = readDeploymentFile();

        LRTSquare lrtSquare = LRTSquare(
            stdJson.readAddress(
                deployments,
                string.concat(".", "addresses", ".", "lrtSquareProxy")
            )
        );

        eigen.forceApprove(address(lrtSquare), 1000 ether);
        ethfi.forceApprove(address(lrtSquare), 1000 ether);

        address[] memory depositors = new address[](1);
        depositors[0] = deployer;

        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;

        lrtSquare.setDepositors(depositors, isDepositor);

        address[] memory tokens = new address[](1);
        tokens[0] = address(eigen);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;
        lrtSquare.deposit(tokens, amounts, deployer);

        vm.stopBroadcast();
    }
}