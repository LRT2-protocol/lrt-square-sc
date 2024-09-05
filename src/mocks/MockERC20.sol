// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 __decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 _decimals
    ) ERC20(name_, symbol_) {
        __decimals = _decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return __decimals;
    }
}
