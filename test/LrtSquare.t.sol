// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "forge-std/console2.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "src/LrtSquare.sol";
import "src/UUPSProxy.sol";
import "src/interfaces/IPriceProvider.sol";
import "src/PriceProvider.sol";

contract ERC20Mintable is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract LrtSquareTest is Test {
    LrtSquare public lrtSquare;

    ERC20Mintable[] public tokens;
    IPriceProvider[] public priceProviders;

    address public owner = vm.addr(1);
    address public alice = vm.addr(2);
    address public bob = vm.addr(3);

    address public merkleDistributor = vm.addr(1000);

    function setUp() public {
        vm.startPrank(owner);
        lrtSquare = LrtSquare(address(new UUPSProxy(address(new LrtSquare()), "")));
        lrtSquare.initialize("LrtSquare", "LRT");

        tokens.push(new ERC20Mintable("Token1", "TK1"));
        tokens.push(new ERC20Mintable("Token2", "TK2"));
        tokens.push(new ERC20Mintable("Token3", "TK3"));

        priceProviders.push(IPriceProvider(address(new PriceProvider())));
        priceProviders.push(IPriceProvider(address(new PriceProvider())));
        priceProviders.push(IPriceProvider(address(new PriceProvider())));

        priceProviders[0].setPrice(100 * 1e6); // 100 USD per 1 fullt decimal unit amount
        priceProviders[1].setPrice(10 * 1e6); // 10 USD per 1 fullt decimal unit amount
        priceProviders[2].setPrice(1 * 1e6); // 1 USD per 1 fullt decimal unit amount

        tokens[0].mint(owner, 100 ether);
        tokens[1].mint(owner, 100 ether);
        tokens[2].mint(owner, 100 ether);

        vm.stopPrank();
    }

    function test_mint() public {
        vm.expectRevert();
        vm.prank(alice); // alice == 0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF
        lrtSquare.mint(alice, 100 ether);

        vm.startPrank(owner);
        assertEq(lrtSquare.balanceOf(alice), 0);
        lrtSquare.mint(alice, 100 ether);
        assertEq(lrtSquare.balanceOf(alice), 100 ether);
        vm.stopPrank();
    }

    function test_registerToken() public {
        vm.expectRevert();
        lrtSquare.registerToken(address(tokens[0]), priceProviders[0]);

        vm.expectRevert("TOKEN_NOT_REGISTERED");
        assertEq(lrtSquare.assetOf(alice, address(tokens[0])), 0);

        vm.startPrank(owner);
        assertEq(lrtSquare.isTokenRegistered(address(tokens[0])), false);
        lrtSquare.registerToken(address(tokens[0]), priceProviders[0]);
        assertEq(lrtSquare.isTokenRegistered(address(tokens[0])), true);
        vm.stopPrank();
    }

    function test_distributeRewards_to_alice() public {
        vm.prank(owner);
        ERC20Mintable(address(tokens[0])).approve(address(lrtSquare), 10 ether);

        address[] memory _tokens = new address[](1);
        uint256[] memory _amounts = new uint256[](1);
        _tokens[0] = address(tokens[0]);
        _amounts[0] = 10 ether;
        address recipient = alice;

        vm.expectRevert();
        lrtSquare.deposit(_tokens, _amounts, recipient);

        vm.startPrank(owner);

        // Fail if not registered
        vm.expectRevert("TOKEN_NOT_REGISTERED");
        lrtSquare.deposit(_tokens, _amounts, recipient);

        lrtSquare.registerToken(address(tokens[0]), priceProviders[0]);

        assertEq(lrtSquare.balanceOf(alice), 0);

        // deposit 10 * 100 USD worth of tokens[0]
        // mint 1000 * 1e6 wei LRT^2 tokens
        lrtSquare.deposit(_tokens, _amounts, recipient);

        assertApproxEqAbs(lrtSquare.balanceOf(alice), 1000 * 1e6, 10 gwei);
        assertApproxEqAbs(lrtSquare.assetOf(alice, address(tokens[0])), 10 ether, 10 gwei);
        vm.stopPrank();

        (address[] memory assets, uint256[] memory assetAmounts) = lrtSquare.totalAssets();
        assertEq(assets.length, 1);
        assertEq(assetAmounts.length, 1);
        assertEq(assets[0], address(tokens[0]));
        assertApproxEqAbs(assetAmounts[0], 10 ether, 10);
    }

    function test_avs_rewards_scenario_1() public {
        address merkleDistributor = vm.addr(1007);

        vm.startPrank(owner);
        lrtSquare.registerToken(address(tokens[0]), priceProviders[0]);
        lrtSquare.registerToken(address(tokens[1]), priceProviders[1]);
        priceProviders[0].setPrice(200 * 1e6);
        priceProviders[1].setPrice(20 * 1e6);

        assertApproxEqAbs(lrtSquare.totalAssetsValueInUsd(), 0, 0);

        // 1. At week-0, ether.fi receives an AVS reward 'tokens[0]'
        // Assume that only alice was holding 1 weETH
        // tokens[0] rewards amount is 100 ether
        //
        // Perform `distributeRewards`
        // - ether.fi sends the 'tokens[o]' rewards 100 ether to the LrtSquare vault
        // - ether.fi mints LRT^2 tokens 1 ether to merkleDistributor. merkleDistributor will distribute the LrtSquare to Alice
        tokens[0].mint(owner, 100 ether);
        tokens[0].approve(address(lrtSquare), 100 ether);
        {
            address[] memory assets = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = address(tokens[0]);
            amounts[0] = 100 ether;
            assertApproxEqAbs(lrtSquare.previewDeposit(assets, amounts), 20000 * 1e6, 1); // 100 * 200 = 20000 USDC worth
            lrtSquare.deposit(assets, amounts, merkleDistributor);
            // 1 ether LRT^2 == {tokens[0]: 100 ether}
        }

        assertApproxEqAbs(lrtSquare.totalAssetsValueInUsd(), 100 * 200 * 1e6, 1);
        assertEq(lrtSquare.totalSupply(), 100 * priceProviders[0].getPriceInUsd()); // initial mint

        // 2. At week-1, ether.fi receives rewards
        // Assume that {alice, bob} were holding 1 weETH
        // tokens[0] rewards amount is 200 ether
        tokens[0].mint(owner, 200 ether);
        tokens[0].approve(address(lrtSquare), 200 ether);
        {
            address[] memory assets = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = address(tokens[0]);
            amounts[0] = 200 ether;

            assertApproxEqAbs(lrtSquare.previewDeposit(assets, amounts), 40000 * 1e6, 1); // 200 * 200 = 40000 USDC worth
            lrtSquare.deposit(assets, amounts, merkleDistributor);
            // (1 + 2) ether LRT^2 == {tokens[0]: 100 + 200 ether}
            // --> 1 ether LRT^2 == {tokens[0]: 100 ether}
        }

        assertApproxEqAbs(lrtSquare.totalAssetsValueInUsd(), (100 + 200) * 200 * 1e6, 1);

        // 3. At week-3, ether.fi receives rewards
        // Assume that {alice, bob} were holding 1 weETH
        // tokens[0] rewards amount is 100 ether
        tokens[0].mint(owner, 100 ether);
        tokens[0].approve(address(lrtSquare), 100 ether);
        {
            address[] memory assets = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = address(tokens[0]);
            amounts[0] = 100 ether;

            // lrtSquare.deposit(assets, amounts, 2 ether, merkleDistributor);
            /// @dev this will be unfair distribution to the existing holders of LRT^2
            // (1 + 2 + 2) ether LRT^2 == {tokens[0]: 100 + 200 + 100 ether}
            // After 'distributeRewards'. the value of LRT^2 token has decreased
            // - from 1 ether LRT^2 == {tokens[0]: 100 ether}
            // - to 1 ether LRT^2 == {tokens[0]: 80 ether}

            // (1 + 2 + x) ether LRT^2 == {tokens[0]: 100 + 200 + 100 ether}
            // What should be 'x' to make it fair distribution; keep the current LRT^2 token's value the same after 'distributeRewards'
            // 100 ether = (100 + 200 + 100) ether / (1 + 2 + x)
            // => x = (100 + 200 + 100) / 100 - (1 + 2) = 1
            assertApproxEqAbs(lrtSquare.previewDeposit(assets, amounts), 20000 * 1e6, 1); // 100 * 200 = 20000 USDC worth
            lrtSquare.deposit(assets, amounts, merkleDistributor);
            // (1 + 2 + 1) ether LRT^2 == {tokens[0]: 100 + 200 + 100 ether}
            // --> 1 ether LRT^2 == {tokens[0]: 100 ether}
        }

        assertApproxEqAbs(lrtSquare.totalAssetsValueInUsd(), (100 + 200 + 100) * 200 * 1e6, 1);

        // 4. At week-3, ether.fi receives rewards from one more AVS
        // Assume that {alice, bob} were holding 1 weETH
        tokens[0].mint(owner, 100 ether);
        tokens[1].mint(owner, 10 ether);
        tokens[0].approve(address(lrtSquare), 100 ether);
        tokens[1].approve(address(lrtSquare), 10 ether);
        {
            address[] memory assets = new address[](2);
            uint256[] memory amounts = new uint256[](2);
            assets[0] = address(tokens[0]);
            assets[1] = address(tokens[1]);
            amounts[0] = 100 ether;
            amounts[1] = 10 ether;

            // We must ensure that the value per LRT^2 token remains the same before/after the deposit of AVS rewards + miting new shares
            //
            // Here's the breakdown using actual values:
            // Currently:
            // - the vault contract currently has 300 token0
            // - the token0 is worth 200 USDC each
            // - therefore, the vault has 60,000 USDC (300 ether * 200 USDC/ether) worth of token0
            // Newly:
            // - we add 100 token0 (20,000 USDC) and 10 token1 (200 USDC) to the vault
            // - we mint new shares equivalent to the proportion of the increase
            //

            // To maintain the value of each share, new shares equivalent to the proportion of the increase must be minted.
            // Execute 'distributeRewards' operation
            assertApproxEqAbs(lrtSquare.previewDeposit(assets, amounts), 20200 * 1e6, 1); // 100 * 200 + 10 * 20 = 20200 USDC worth
            lrtSquare.deposit(assets, amounts, merkleDistributor);
        }

        assertApproxEqAbs(lrtSquare.totalAssetsValueInUsd(), (100 + 200 + 100 + 100) * 200 * 1e6 + 10 * 20 * 1e6, 1);
        lrtSquare.totalSupply();
        vm.stopPrank();
    }
}
