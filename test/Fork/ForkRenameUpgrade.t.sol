// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Utils} from "../Utils.sol";
import {ILRTSquared} from "../../src/interfaces/ILRTSquared.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PriceProvider} from "../../src/PriceProvider.sol";
import {IAggregatorV3} from "../../src/interfaces/IAggregatorV3.sol";
import {LRTSquaredStorage, Governable} from "../../src/LRTSquared/LRTSquaredStorage.sol";
import {LRTSquaredAdmin} from "../../src/LRTSquared/LRTSquaredAdmin.sol";
import {LRTSquaredInitializer} from "../../src/LRTSquared/LRTSquaredInitializer.sol";
import {LRTSquaredDummy} from "../../src/LRTSquared/LRTSquaredDummy.sol";
import {LRTSquaredCore} from "../../src/LRTSquared/LRTSquaredCore.sol";
import {console} from "forge-std/console.sol";

contract ForkRenameUpgrade is Utils {
    using SafeERC20 for IERC20;

    ILRTSquared lrtSquared = ILRTSquared(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);
    IERC20Metadata lrtSquaredToken = IERC20Metadata(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);
    uint256 tvl;
    string name;
    string symbol;

    function setUp() public {
        console.log("Setting up test...");
        string memory mainnet = "https://eth-pokt.nodies.app";
        vm.createSelectFork(mainnet);
        console.log("Fork created successfully on URL: %s", mainnet);

        // Fetch initial LRTSquared contract details
        (tvl,) = lrtSquared.tvl();
        console.log("Initial TVL: %d", tvl);

        symbol = lrtSquaredToken.symbol();
        name = lrtSquaredToken.name();
        console.log("Initial Token Symbol: %s", symbol);
        console.log("Initial Token Name: %s", name);

        address lrtSquaredDummyImpl = address(new LRTSquaredDummy());

        console.log("LRTSquared Dummy Implementation Address: %s", lrtSquaredDummyImpl);

        // Start prank as governor
        address governor = lrtSquared.governor();
        console.log("Governor Address: %s", governor);
        vm.startPrank(governor);

        // Upgrade LRT to dummy implementation
        try LRTSquaredAdmin(address(lrtSquared)).upgradeToAndCall(lrtSquaredDummyImpl, "") {
            console.log("Upgrade to LRTSquaredDummy successful");
        } catch Error(string memory reason) {
            console.log("Upgrade to LRTSquaredDummy failed: %s", reason);
            revert(reason);
        }

        string memory newName = "King Protocol";
        string memory newSymbol = "KING";

        try LRTSquaredDummy(address(lrtSquared)).setInfo(newName, newSymbol) {
            console.log("LRTSquaredDummyDummy setInfo successful");
        } catch Error(string memory reason) {
            console.log("LRTSquaredDummyDummy setInfo failed: %s", reason);
            revert(reason);
        }

        address lrtSquaredCoreImpl = address(new LRTSquaredCore());
        console.log("LRTSquared Core Implementation Address: %s", lrtSquaredCoreImpl);

        try LRTSquaredCore(address(lrtSquared)).upgradeToAndCall(lrtSquaredCoreImpl, "") {
            console.log("Upgrade to LRTSquaredCore successful");
        } catch Error(string memory reason) {
            console.log("Upgrade to LRTSquaredCore failed: %s", reason);
            revert(reason);
        }


        vm.stopPrank();
    }

    function test_Deploy() public view {
        //Check name and symbol changed
        assertNotEq(symbol, lrtSquaredToken.symbol());
        assertNotEq(name, lrtSquaredToken.name());

        //Check new name and symbol
        assertEq("KING", lrtSquaredToken.symbol());
        assertEq("King Protocol", lrtSquaredToken.name());

        //Check TVL or other state variables remain the same
        (uint256 newTvl,) = lrtSquared.tvl();
        assertEq(newTvl, tvl);
    }
}
