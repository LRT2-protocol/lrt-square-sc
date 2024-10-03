// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LRTSquare, Governable} from "../src/LRTSquare.sol";
import {UUPSProxy} from "../src/UUPSProxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {PriceProvider} from "../src/PriceProvider.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {Swapper1InchV6} from "../src/Swapper1InchV6.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";

contract DeployLRTSquare is Utils {
    using SafeERC20 for IERC20;
    
    string chainId;
    LRTSquare public lrtSquare;

    address[] public tokens;
    PriceProvider public priceProvider;

    address owner;
    address rebalancer;
    address pauser;
    address swapRouter1InchV6;
    Swapper1InchV6 swapper;

    address ethfi;
    address eigen;

    uint64[] tokenPositionWeightLimits;

    uint128 percentageRateLimit = 5_000_000_000; // 500%

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        chainId = vm.toString(block.chainid);
        ChainConfig memory config = getChainConfig(chainId);

        owner = config.owner;
        rebalancer = config.rebalancer;
        pauser = config.pauser;
        ethfi = config.ethfi;
        eigen = config.eigen;
        swapRouter1InchV6 = config.swapRouter1InchV6;

        swapper = new Swapper1InchV6(swapRouter1InchV6, tokens);

        address lrtSquareImpl = address(new LRTSquare());
        lrtSquare = LRTSquare(address(new UUPSProxy(lrtSquareImpl, "")));
        lrtSquare.initialize(
            "LrtSquare",
            "LRT2",
            deployer,
            pauser,
            rebalancer, 
            address(swapper),
            percentageRateLimit
        );

        tokens.push(ethfi); 
        tokens.push(eigen);
        tokens.push(ETH);

        tokenPositionWeightLimits.push(lrtSquare.HUNDRED_PERCENT_LIMIT());
        tokenPositionWeightLimits.push(lrtSquare.HUNDRED_PERCENT_LIMIT());        
        tokenPositionWeightLimits.push(lrtSquare.HUNDRED_PERCENT_LIMIT());        
        
        PriceProvider.Config[] memory priceProviderConfig = new PriceProvider.Config[](tokens.length);
        
        priceProviderConfig[0] = PriceProvider.Config({
            oracle: config.ethfiChainlinkOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(config.ethfiChainlinkOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false
        });
       
        priceProviderConfig[1] = PriceProvider.Config({
            oracle: config.eigenChainlinkOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(config.eigenChainlinkOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false
        });
       
        priceProviderConfig[2] = PriceProvider.Config({
            oracle: config.ethUsdChainlinkOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(config.ethUsdChainlinkOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false
        });

        priceProvider = new PriceProvider(deployer, tokens, priceProviderConfig);

        lrtSquare.updatePriceProvider(address(priceProvider));
        
        for (uint256 i = 0; i < tokens.length; ) {
            lrtSquare.registerToken(tokens[i], tokenPositionWeightLimits[i]);
            unchecked {
                ++i;
            }
        }

        lrtSquare.whitelistRebalacingOutputToken(ETH, true);

        // lrtSquare.transferGovernance(owner);

        string memory parentObject = "parent object";

        string memory deployedAddresses = "addresses";

        vm.serializeAddress(deployedAddresses, "lrtSquareProxt", address(lrtSquare));
        vm.serializeAddress(deployedAddresses, "lrtSquareImpl", lrtSquareImpl);
        vm.serializeAddress(deployedAddresses, "priceProvider", address(priceProvider));
        vm.serializeAddress(
            deployedAddresses,
            "priceProvider",
            address(priceProvider)
        );
        vm.serializeAddress(deployedAddresses, "owner", address(owner));
        vm.serializeAddress(
            deployedAddresses,
            "rebalancer",
            address(rebalancer)
        );
        vm.serializeAddress(
            deployedAddresses,
            "pauser",
            address(pauser)
        );

        string memory addressOutput = vm.serializeAddress(
            deployedAddresses,
            "swapper",
            address(swapper)
        );

        // serialize all the data
        string memory finalJson = vm.serializeString(
            parentObject,
            deployedAddresses,
            addressOutput
        );

        writeDeploymentFile(finalJson);

        vm.stopBroadcast();
    }
}
