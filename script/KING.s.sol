// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IKING} from "../src/interfaces/IKING.sol";
import {KINGStorage, Governable} from "../src/KING/KINGStorage.sol";
import {KINGAdmin} from "../src/KING/KINGAdmin.sol";
import {KINGInitializer} from "../src/KING/KINGInitializer.sol";
import {KINGCore} from "../src/KING/KINGCore.sol";
import {UUPSProxy} from "../src/UUPSProxy.sol";
import {PriceProvider} from "../src/PriceProvider.sol";
import {Utils, ChainConfig} from "./Utils.sol";
import {Swapper1InchV6} from "../src/Swapper1InchV6.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";

contract DeployKING is Utils {
    using SafeERC20 for IERC20;
    
    string chainId;
    IKING public king;

    address[] public tokens;
    PriceProvider public priceProvider;

    address owner;
    address rebalancer;
    address swapRouter1InchV6;
    Swapper1InchV6 swapper;

    address ethfi;
    address eigen;

    uint64[] tokenPositionWeightLimits;

    uint128 percentageRateLimit = 10_000_000_000; // 1000%
    uint256 communityPauseDepositAmt = 4 ether;
    KINGStorage.Fee fee;

    address depositor = 0xF46D3734564ef9a5a16fC3B1216831a28f78e2B5;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        chainId = vm.toString(block.chainid);
        ChainConfig memory config = getChainConfig(chainId);

        owner = config.owner;
        rebalancer = config.rebalancer;
        address[] memory pauser = config.pauser;
        ethfi = config.ethfi;
        eigen = config.eigen;
        swapRouter1InchV6 = config.swapRouter1InchV6;

        swapper = new Swapper1InchV6(swapRouter1InchV6);

        fee = KINGStorage.Fee({
            treasury: config.treasury,
            depositFeeInBps: config.depositFeeInBps,
            redeemFeeInBps: config.redeemFeeInBps
        });

        tokens.push(eigen);
        tokens.push(ETH);

        tokenPositionWeightLimits.push(HUNDRED_PERCENT_LIMIT);
        tokenPositionWeightLimits.push(HUNDRED_PERCENT_LIMIT);        
        
        PriceProvider.Config[] memory priceProviderConfig = new PriceProvider.Config[](tokens.length);
       
        priceProviderConfig[0] = PriceProvider.Config({
            oracle: config.eigenChainlinkOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(config.eigenChainlinkOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false
        });
       
        priceProviderConfig[1] = PriceProvider.Config({
            oracle: config.ethUsdChainlinkOracle,
            priceFunctionCalldata: hex"",
            isChainlinkType: true,
            oraclePriceDecimals: IAggregatorV3(config.ethUsdChainlinkOracle).decimals(),
            maxStaleness: 1 days,
            dataType: PriceProvider.ReturnType.Int256,
            isBaseTokenEth: false
        });
       
        address priceProviderImpl = address(new PriceProvider());
        priceProvider = PriceProvider(
            address(
                new UUPSProxy(
                    priceProviderImpl, 
                    abi.encodeWithSelector(
                        PriceProvider.initialize.selector,
                        owner,
                        tokens,
                        priceProviderConfig
                    )
                )
            )
        );

        address kingCoreImpl = address(new KINGCore());
        address kingAdminImpl = address(new KINGAdmin());
        address kingInitializer = address(new KINGInitializer());
        address kingProxy = address(new UUPSProxy(kingInitializer, ""));
        king = IKING(kingProxy);

        KINGInitializer(address(king)).initialize(
            "KING",
            "KING2",
            deployer,
            pauser[0],
            rebalancer, 
            address(swapper),
            address(priceProvider),
            percentageRateLimit,
            communityPauseDepositAmt,
            fee
        );

        KINGCore(address(king)).upgradeToAndCall(kingCoreImpl, "");
        KINGCore(address(king)).setAdminImpl(kingAdminImpl);

        king.setPauser(pauser[1], true);
        
        tokens.pop();
        tokenPositionWeightLimits.pop();

        for (uint256 i = 0; i < tokens.length; ) {
            king.registerToken(tokens[i], tokenPositionWeightLimits[i]);
            unchecked {
                ++i;
            }
        }

        king.transferGovernance(owner);

        string memory parentObject = "parent object";

        string memory deployedAddresses = "addresses";

        vm.serializeAddress(deployedAddresses, "kingProxy", address(king));
        vm.serializeAddress(deployedAddresses, "kingCore", kingCoreImpl);
        vm.serializeAddress(deployedAddresses, "kingAdmin", kingAdminImpl);
        vm.serializeAddress(deployedAddresses, "kingInitializer", kingInitializer);
        vm.serializeAddress(deployedAddresses, "priceProvider", address(priceProvider));
        vm.serializeAddress(
            deployedAddresses,
            "priceProviderProxy",
            address(priceProvider)
        );
        vm.serializeAddress(
            deployedAddresses,
            "priceProviderImpl",
            priceProviderImpl
        );
        vm.serializeAddress(deployedAddresses, "owner", address(owner));
        vm.serializeAddress(
            deployedAddresses,
            "rebalancer",
            address(rebalancer)
        );
        vm.serializeAddress(
            deployedAddresses,
            "pauser0",
            address(pauser[0])
        );
        vm.serializeAddress(
            deployedAddresses,
            "pauser1",
            address(pauser[1])
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
