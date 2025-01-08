// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import {Utils} from "../Utils.sol";
// import {IKING} from "../../src/interfaces/IKING.sol";
// import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {PriceProvider} from "../../src/PriceProvider.sol";
// import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
// import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
// bytes32 constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

// struct Permit {
//     address owner;
//     address spender;
//     uint256 value;
//     uint256 nonce;
//     uint256 deadline;
// }

// contract ForkKINGSqaureNameUpgradeTest is Utils {
//     using SafeERC20 for IERC20;

//     IKING king = IKING(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);
//     string newName = "KING";
//     function setUp() public {
//         string memory mainnet = "https://eth-pokt.nodies.app";
//         vm.createSelectFork(mainnet);

//         address newImpl = address(new KING());
//         vm.startPrank(king.governor());
//         king.upgradeToAndCall(newImpl, "");
//         king.updateName(newName);
//         vm.stopPrank();
//     }

//     function test_Name() public view {
//         assertEq(king.name(), newName);
//     }

//     function test_PermitName() public {
//         bytes32 TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
//         bytes32 DOMAIN_SEPARATOR = keccak256(abi.encode(TYPE_HASH, keccak256(bytes(newName)), keccak256(bytes("2")), 1, address(king)));

//         assertEq(king.DOMAIN_SEPARATOR(), DOMAIN_SEPARATOR);

//         uint256 amount = 10 ether;
//         uint256 deadline = type(uint256).max;

//         (address alice, uint256 alicePk) = makeAddrAndKey("alice");
//         address bob = makeAddr("bob");
//         Permit memory permit = Permit({
//             owner: alice,
//             spender: bob,
//             value: amount,
//             nonce: 0,
//             deadline: deadline
//         });

//         bytes32 digest = getTypedDataHash(DOMAIN_SEPARATOR, permit);
//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

//         king.permit(permit.owner, permit.spender, permit.value, deadline, v, r, s);

//         assertEq(king.allowance(alice, bob), amount);
//     }

//     // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
//     function getTypedDataHash(
//         bytes32 DOMAIN_SEPARATOR,
//         Permit memory _permit
//     ) internal pure returns (bytes32) {
//         return
//             keccak256(
//                 abi.encodePacked(
//                     "\x19\x01",
//                     DOMAIN_SEPARATOR,
//                     getStructHash(_permit)
//                 )
//             );
//     }

//     // computes the hash of a permit
//     function getStructHash(
//         Permit memory _permit
//     ) internal pure returns (bytes32) {
//         return
//             keccak256(
//                 abi.encode(
//                     PERMIT_TYPEHASH,
//                     _permit.owner,
//                     _permit.spender,
//                     _permit.value,
//                     _permit.nonce,
//                     _permit.deadline
//                 )
//             );
//     }

// }