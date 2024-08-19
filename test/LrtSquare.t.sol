// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "forge-std/console2.sol";
import "forge-std/console.sol";

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

import "../src/LrtSquare.sol";
import "../src/UUPSProxy.sol";

contract ERC20Mintable is ERC20Upgradeable {
    function initialize(string memory name, string memory symbol) public {
        super.initialize(name, symbol);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract LrtSquareTest is Test {
    
    LrtSquare public lrtSquare;

    ERC20PresetMinterPauser[] public tokens;

    address public owner = vm.addr(1);
    address public alice = vm.addr(2);
    address public bob = vm.addr(3);

    address public merkleDistributor = vm.addr(1000); 

    function setUp() public {
        vm.startPrank(owner);
        lrtSquare = LrtSquare(address(new UUPSProxy(address(new LrtSquare()), "")));
        lrtSquare.initialize("LrtSquare", "LRT");

        tokens.push(new ERC20PresetMinterPauser("Token1", "TK1"));
        tokens.push(new ERC20PresetMinterPauser("Token2", "TK2"));
        tokens.push(new ERC20PresetMinterPauser("Token3", "TK3"));

        tokens[0].mint(owner, 100 ether);
        tokens[1].mint(owner, 100 ether);
        tokens[2].mint(owner, 100 ether);

        vm.stopPrank();
    }

    function test_mint() public {
        vm.expectRevert("Ownable: caller is not the owner");
        lrtSquare.mint(alice, 100 ether);

        vm.startPrank(owner);
        assertEq(lrtSquare.balanceOf(alice), 0);
        lrtSquare.mint(alice, 100 ether);
        assertEq(lrtSquare.balanceOf(alice), 100 ether);
        vm.stopPrank();
    }

    function test_registerToken() public {
        vm.expectRevert("Ownable: caller is not the owner");
        lrtSquare.registerToken(address(tokens[0]));

        vm.expectRevert("TOKEN_NOT_REGISTERED");
        assertEq(lrtSquare.assetOf(alice, address(tokens[0])), 0);

        vm.startPrank(owner);
        assertEq(lrtSquare.isTokenRegistered(address(tokens[0])), false);
        lrtSquare.registerToken(address(tokens[0]));
        assertEq(lrtSquare.isTokenRegistered(address(tokens[0])), true);
        vm.stopPrank();
    }

    function test_distributeRewards_to_alice() public {
        vm.prank(owner);
        ERC20PresetMinterPauser(address(tokens[0])).approve(address(lrtSquare), 10 ether);

        address[] memory _tokens = new address[](1);
        uint256[] memory _amounts = new uint256[](1);
        _tokens[0] = address(tokens[0]);
        _amounts[0] = 10 ether;
        uint256 share = 1 ether;
        address recipient = alice;

        vm.expectRevert("Ownable: caller is not the owner");
        lrtSquare.distributeRewards(_tokens, _amounts, share, recipient);

        vm.startPrank(owner);

        // Fail if not registered
        vm.expectRevert("TOKEN_NOT_REGISTERED");
        lrtSquare.distributeRewards(_tokens, _amounts, share, recipient);
    
        lrtSquare.registerToken(address(tokens[0]));

        assertEq(lrtSquare.balanceOf(alice), 0);

        lrtSquare.distributeRewards(_tokens, _amounts, share, recipient);

        assertEq(lrtSquare.balanceOf(alice), 1 ether);
        assertApproxEqAbs(lrtSquare.assetOf(alice, address(tokens[0])), 10 ether, 10);
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
        lrtSquare.registerToken(address(tokens[0]));
        lrtSquare.registerToken(address(tokens[1]));

        // 1. At week-0, ether.fi receives an AVS reward 'tokens[0]'
        // Assume that only alice was holding 1 weETH
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
            lrtSquare.distributeRewards(assets, amounts, 1 ether, merkleDistributor);
            // 1 ether LRT^2 == {tokens[0]: 100 ether}
        }

        // 2. At week-1, ether.fi receives rewards
        // Assume that {alice, bob} were holding 1 weETH
        tokens[0].mint(owner, 200 ether);
        tokens[0].approve(address(lrtSquare), 200 ether);
        {
            address[] memory assets = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = address(tokens[0]);
            amounts[0] = 200 ether;
            lrtSquare.distributeRewards(assets, amounts, 2 ether, merkleDistributor);
            // (1 + 2) ether LRT^2 == {tokens[0]: 100 + 200 ether} 
            // --> 1 ether LRT^2 == {tokens[0]: 100 ether}
        }

        // 3. At week-3, ether.fi receives rewards
        // Assume that {alice, bob} were holding 1 weETH
        // but AVS rewards amount has decreased to 100 ether
        tokens[0].mint(owner, 100 ether);
        tokens[0].approve(address(lrtSquare), 100 ether);
        {
            address[] memory assets = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = address(tokens[0]);
            amounts[0] = 100 ether;

            // lrtSquare.distributeRewards(assets, amounts, 2 ether, merkleDistributor);
            /// @dev this will be unfair distribution to the existing holders of LRT^2
            // (1 + 2 + 2) ether LRT^2 == {tokens[0]: 100 + 200 + 100 ether}
            // After 'distributeRewards'. the value of LRT^2 token has decreased
            // - from 1 ether LRT^2 == {tokens[0]: 100 ether} 
            // - to 1 ether LRT^2 == {tokens[0]: 80 ether}

            // (1 + 2 + x) ether LRT^2 == {tokens[0]: 100 + 200 + 100 ether}
            // What should be 'x' to make it fair distribution; keep the current LRT^2 token's value the same after 'distributeRewards'
            // 100 ether = (100 + 200 + 100) ether / (1 + 2 + x)
            // => x = (100 + 200 + 100) / 100 - (1 + 2) = 1
            uint256 x = 1 ether;
            lrtSquare.distributeRewards(assets, amounts, x, merkleDistributor);
            // (1 + 2 + 1) ether LRT^2 == {tokens[0]: 100 + 200 + 100 ether}
            // --> 1 ether LRT^2 == {tokens[0]: 100 ether}
        }

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
            uint256 new_lrtSquare_tokens_to_mint = calculateVaultShareToMintForRewardsToDistribute(assets, amounts);

            // Execute 'distributeRewards' operation
            uint256 beforeTokenVaultValue = calculateVaultTokenValue(1 ether);
            lrtSquare.distributeRewards(assets, amounts, new_lrtSquare_tokens_to_mint, merkleDistributor);
            assertApproxEqAbs(beforeTokenVaultValue, calculateVaultTokenValue(1 ether), 1);
        }
        vm.stopPrank();
    }

    function calculateVaultShareToMintForRewardsToDistribute(address[] memory _tokens, uint256[] memory amounts) internal view returns (uint256) {
        uint256 total_new_rewards_in_usdc = calculateTokensValueInUSDC(_tokens, amounts);
        uint256 total_current_lrtSquare_value_in_usdc = calculateVaultTokenValue(lrtSquare.totalSupply());
        uint256 total_lrtSquare_supply = lrtSquare.totalSupply();
        return (total_new_rewards_in_usdc * total_lrtSquare_supply) / total_current_lrtSquare_value_in_usdc;
    }

    function calculateVaultTokenValue(uint256 shares) internal view returns (uint256) {
        (address[] memory assets, uint256[] memory assetAmounts) = lrtSquare.totalAssets();
        uint256 totalValue = calculateTokensValueInUSDC(assets, assetAmounts);
        uint256 totalSupply = lrtSquare.totalSupply();
        return totalValue * shares / totalSupply;
    }

    function calculateTokensValueInUSDC(address[] memory _tokens, uint256[] memory amounts) internal view returns (uint256) {
        uint256 total_new_rewards_in_usdc = 0;
        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 tokenValueInUSDC = queryAvsTokenValue(_tokens[i]);
            total_new_rewards_in_usdc += amounts[i] * tokenValueInUSDC / 10 ** ERC20(_tokens[i]).decimals();
        }
        return total_new_rewards_in_usdc;
    }

    // Utility function to get current USD value of a token, assuming integration with an oracle or other price feed
    function queryAvsTokenValue(address token) internal view returns (uint256) {
        // Placeholder for an actual oracle call
        if (token == address(tokens[0])) {
            return 200; // Assume each token is worth 200 USDC
        } else if (token == address(tokens[1])) {
            return 20;  // Assume each token is worth 20 USDC
        }
        return 0;
    }

}