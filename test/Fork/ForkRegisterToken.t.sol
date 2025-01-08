// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import {Utils} from "../Utils.sol";
// import {IKING} from "../../src/interfaces/IKING.sol";
// import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {PriceProvider} from "../../src/PriceProvider.sol";
// import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";

// contract ForkRegisterTokenTest is Utils {
//     using SafeERC20 for IERC20;

//     address alice = makeAddr("alice");
//     IKING king = IKING(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);
//     PriceProvider priceProvider = PriceProvider(0x2B90103cdc9Bba6c0dBCAaF961F0B5b1920F19E3);
//     address newToken = 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB;
//     address tokenOracle = 0x19678515847d8DE85034dAD0390e09c3048d31cd;
//     uint64 tokenPositionWeightLimit = HUNDRED_PERCENT_LIMIT;

//     function setUp() public {
//         string memory mainnet = "https://eth-pokt.nodies.app";
//         vm.createSelectFork(mainnet);

//         address[] memory tokens = new address[](1);
//         tokens[0] = newToken;
        
//         PriceProvider.Config[] memory configs = new PriceProvider.Config[](1);
//         configs[0] = PriceProvider.Config({
//             oracle: tokenOracle,
//             priceFunctionCalldata: hex"",
//             isChainlinkType: true,
//             oraclePriceDecimals: IAggregatorV3(tokenOracle).decimals(),
//             maxStaleness: 2 days,
//             dataType: PriceProvider.ReturnType.Int256,
//             isBaseTokenEth: false
//         });
//         vm.prank(priceProvider.governor());
//         priceProvider.setTokenConfig(tokens, configs);

//         vm.prank(king.governor());
//         king.registerToken(newToken, tokenPositionWeightLimit);

//         address[] memory depositors = new address[](1);
//         depositors[0] = alice;
//         bool[] memory shouldWhitelist = new bool[](1);
//         shouldWhitelist[0] = true;

//         vm.prank(king.governor());
//         king.setDepositors(depositors, shouldWhitelist);
//     }

//     function test_CanDeposit() public {
//         deal(newToken, alice, 1 ether);
//         uint256 amountToDeposit = 0.001 ether;

//         address[] memory tokens = new address[](1);
//         tokens[0] = newToken;
//         uint256[] memory amounts = new uint256[](1);
//         amounts[0] = amountToDeposit;

//         uint256 aliceBalBefore = king.balanceOf(alice);

//         vm.startPrank(alice);
//         IERC20(newToken).forceApprove(address(king), amountToDeposit);
//         king.deposit(tokens, amounts, alice);
//         vm.stopPrank();

//         uint256 aliceBalAfter = king.balanceOf(alice);
//         assertGt(aliceBalAfter, aliceBalBefore);
//     }
// }