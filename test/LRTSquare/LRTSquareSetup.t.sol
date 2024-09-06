// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {LrtSquare, Governable} from "../../src/LrtSquare.sol";
import {UUPSProxy} from "src/UUPSProxy.sol";
import {MockPriceProvider} from "../../src/mocks/MockPriceProvider.sol";
import {GovernanceToken} from "../../src/governance/GovernanceToken.sol";
import {LRTSquareGovernor} from "../../src/governance/Governance.sol";
import {Timelock} from "../../src/governance/Timelock.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

interface IPriceProvider {
    /// @notice Get the price of the token in ETH (18 decimals) for the token amount = 1 * 10 ** token.decimals()
    function getPriceInEth(address token) external view returns (uint256);

    /// @notice Get the decimals of the price provider (6 decimals)
    function decimals() external pure returns (uint8);

    /// @notice Set the price of the token in ETH (18 decimals)
    function setPrice(address token, uint256 price) external;
}

contract LRTSquareTestSetup is Test {
    using SafeERC20 for IERC20;

    LrtSquare public lrtSquare;

    MockERC20[] public tokens;
    IPriceProvider public priceProvider;

    uint256 totalSupply = 1e9 ether;
    address public owner = vm.addr(1);
    address public alice = vm.addr(2);
    address public bob = vm.addr(3);

    address public merkleDistributor = vm.addr(1000);

    GovernanceToken govToken;
    LRTSquareGovernor governance;
    Timelock timelock;

    uint256[] tokenPrices;

    uint8[] tokenDecimals;

    function setUp() public virtual {
        vm.startPrank(owner);

        address[] memory proposers;
        address[] memory executors;
        address admin = owner;
        govToken = new GovernanceToken("GovToken", "GTK", totalSupply);
        timelock = new Timelock(proposers, executors, admin);
        governance = new LRTSquareGovernor(IVotes(address(govToken)), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governance));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), admin);

        lrtSquare = LrtSquare(
            address(new UUPSProxy(address(new LrtSquare()), ""))
        );
        lrtSquare.initialize("LrtSquare", "LRT", address(timelock));

        tokenDecimals.push(18);
        tokenDecimals.push(12);
        tokenDecimals.push(6);

        tokenPrices.push(0.1 ether);
        tokenPrices.push(0.5 ether);
        tokenPrices.push(0.01 ether);

        tokens.push(new MockERC20("Token1", "TK1", tokenDecimals[0]));
        tokens.push(new MockERC20("Token2", "TK2", tokenDecimals[1]));
        tokens.push(new MockERC20("Token3", "TK3", tokenDecimals[2]));

        priceProvider = IPriceProvider(address(new MockPriceProvider()));

        priceProvider.setPrice(address(tokens[0]), tokenPrices[0]);
        priceProvider.setPrice(address(tokens[1]), tokenPrices[1]);
        priceProvider.setPrice(address(tokens[2]), tokenPrices[2]);

        tokens[0].mint(owner, 100 ether);
        tokens[1].mint(owner, 100 ether);
        tokens[2].mint(owner, 100 ether);
        vm.stopPrank();

        vm.prank(address(timelock));
        lrtSquare.updatePriceProvider(address(priceProvider));
    }

    function _registerToken(address token, bytes memory revertData) internal {
        string memory description = string(
            abi.encodePacked(
                "Proposal: Register token: ",
                vm.toString(token),
                " at time ",
                vm.toString(block.timestamp)
            )
        );

        bytes memory data = abi.encodeWithSelector(
            LrtSquare.registerToken.selector,
            token
        );

        _executeGovernance(data, description, revertData);
    }

    function _updateWhitelist(
        address token,
        bool whitelist,
        bytes memory revertData
    ) internal {
        string memory description = string(
            abi.encodePacked(
                "Proposal: Whitelist token: ",
                vm.toString(token),
                ", whitelist value: ",
                vm.toString(whitelist),
                " at time ",
                vm.toString(block.timestamp)
            )
        );
        bytes memory data = abi.encodeWithSelector(
            LrtSquare.updateWhitelist.selector,
            token,
            whitelist
        );

        _executeGovernance(data, description, revertData);
    }

    function _updatePriceProvider(
        address _priceProvider,
        bytes memory revertData
    ) internal {
        string memory description = string(
            abi.encodePacked(
                "Proposal: Update price provider: ",
                vm.toString(_priceProvider),
                " at time ",
                vm.toString(block.timestamp)
            )
        );
        bytes memory data = abi.encodeWithSelector(
            LrtSquare.updatePriceProvider.selector,
            _priceProvider
        );

        _executeGovernance(data, description, revertData);
    }

    function _setDepositors(
        address[] memory depositors,
        bool[] memory isDepositor,
        bytes memory revertData
    ) internal {
        string memory description = "Proposal: Set depositors";

        bytes memory data = abi.encodeWithSelector(
            LrtSquare.setDepositors.selector,
            depositors,
            isDepositor
        );

        _executeGovernance(data, description, revertData);
    }

    function _executeGovernance(
        bytes memory data,
        string memory description,
        bytes memory revertData
    ) internal {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        bytes32 descriptionHash = keccak256(bytes(description));

        targets[0] = address(lrtSquare);
        values[0] = 0;
        calldatas[0] = data;

        uint256 proposalId = governance.hashProposal(
            targets,
            values,
            calldatas,
            descriptionHash
        );

        uint256 votingDelay = governance.votingDelay();

        vm.startPrank(owner);
        govToken.delegate(owner);

        vm.roll(block.number + 100);
        governance.propose(targets, values, calldatas, description);

        uint256 currentBlock = block.number;
        uint256 votingStart = currentBlock + votingDelay + 1;
        uint256 proposalDeadline = governance.proposalDeadline(proposalId) + 1;

        vm.roll(votingStart);
        governance.castVote(proposalId, 1);

        vm.roll(proposalDeadline);
        governance.queue(targets, values, calldatas, descriptionHash);

        bytes32 id = timelock.hashOperationBatch(
            targets,
            values,
            calldatas,
            0,
            _timelockSalt(descriptionHash)
        );

        uint256 executeTimestamp = timelock.getTimestamp(id) + 1;

        vm.warp(executeTimestamp);
        if (revertData.length > 0) vm.expectRevert(revertData);
        governance.execute(targets, values, calldatas, descriptionHash);

        vm.stopPrank();
    }

    function _timelockSalt(
        bytes32 descriptionHash
    ) private view returns (bytes32) {
        return bytes20(address(governance)) ^ descriptionHash;
    }

    function _getAvsTokenValuesInEth(
        uint256[] memory _tokenIndices,
        uint256[] memory _amounts
    ) internal view returns (uint256) {
        uint256 totalAmt = 0;
        for (uint256 i = 0; i < _tokenIndices.length; ) {
            totalAmt += (_amounts[i] * tokenPrices[i]) / 10 ** tokenDecimals[i];
            unchecked {
                ++i;
            }
        }

        return totalAmt;
    }

    function _getAssetForVaultShares(
        uint256 vaultShare,
        address asset
    ) internal view returns (uint256) {
        return
            (vaultShare * (IERC20(asset).balanceOf(address(lrtSquare)) + 1)) /
            (lrtSquare.totalSupply() + 1);
    }

    function _getSharesForEth(
        uint256 valueInEth
    ) internal view returns (uint256) {
        uint256 _totalSupply = lrtSquare.totalSupply();
        uint256 _vaultTokenValuesInEth = lrtSquare.getVaultTokenValuesInEth(
            _totalSupply
        );

        return (valueInEth * (_totalSupply + 1)) / (_vaultTokenValuesInEth + 1);
    }
}
