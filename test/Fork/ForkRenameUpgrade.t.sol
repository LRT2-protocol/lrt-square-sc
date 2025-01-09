// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Utils} from "../Utils.sol";
import {IKING} from "../../src/interfaces/IKING.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PriceProvider} from "../../src/PriceProvider.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {KINGStorage, Governable} from "../../src/KING/KINGStorage.sol";
import {KINGAdmin} from "../../src/KING/KINGAdmin.sol";
import {KINGInitializer} from "../../src/KING/KINGInitializer.sol";
import {KINGDummy} from "../../src/KING/KINGDummy.sol";
import {KINGCore} from "../../src/KING/KINGCore.sol";
import {console} from "forge-std/console.sol";

contract ForkRenameUpgrade is Utils {
    using SafeERC20 for IERC20;

    IKING king = IKING(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);
    IERC20Metadata kingToken = IERC20Metadata(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);
    uint256 tvl;
    string name;
    string symbol;

    function setUp() public {
        console.log("Setting up test...");
        string memory mainnet = "https://eth-pokt.nodies.app";
        vm.createSelectFork(mainnet);
        console.log("Fork created successfully on URL: %s", mainnet);

        // Fetch initial KING contract details
        (tvl,) = king.tvl();
        console.log("Initial TVL: %d", tvl);

        symbol = kingToken.symbol();
        name = kingToken.name();
        console.log("Initial Token Symbol: %s", symbol);
        console.log("Initial Token Name: %s", name);

        address kingDummyImpl = address(new KINGDummy());
        address kingAdminImpl = address(new KINGAdmin());
        console.log("KING Dummy Implementation Address: %s", kingDummyImpl);
        console.log("KING Admin Implementation Address: %s", kingAdminImpl);

        // Start prank as governor
        address governor = king.governor();
        console.log("Governor Address: %s", governor);
        vm.startPrank(governor);

        // Upgrade KING to dummy implementation
        try KINGCore(address(king)).upgradeToAndCall(kingDummyImpl, "") {
            console.log("Upgrade to KINGDummy successful");
        } catch Error(string memory reason) {
            console.log("Upgrade to KINGDummy failed: %s", reason);
            revert(reason);
        }

        // // Update KING details
        string memory newName = "KING";
        string memory newSymbol = "KING";

        try KINGDummy(address(king)).setInfo(newName, newSymbol) {
            console.log("KINGDummy setInfo successful");
        } catch Error(string memory reason) {
            console.log("KINGDummy setInfo failed: %s", reason);
            revert(reason);
        }

        // Upgrade to KINGCore implementation
        address kingCoreImpl = address(new KINGCore());
        console.log("KING Core Implementation Address: %s", kingCoreImpl);

        try KINGCore(address(king)).upgradeToAndCall(kingCoreImpl, "") {
            console.log("Upgrade to KINGCore successful");
        } catch Error(string memory reason) {
            console.log("Upgrade to KINGCore failed: %s", reason);
            revert(reason);
        }

        // Set admin implementation
        try KINGCore(address(king)).setAdminImpl(kingAdminImpl) {
            console.log("Admin implementation set successfully");
        } catch Error(string memory reason) {
            console.log("Setting Admin Implementation failed: %s", reason);
            revert(reason);
        }

        vm.stopPrank();
    }

    function test_Deploy() public view {
        //Check name and symbol changed
        assertNotEq(symbol, kingToken.symbol());
        assertNotEq(name, kingToken.name());

        //Check new name and symbol
        assertEq("KING", kingToken.symbol());
        assertEq("KING", kingToken.name());

        //Check TVL or other state variables remain the same
        (uint256 newTvl,) = king.tvl();
        assertEq(newTvl, tvl);
    }
}
