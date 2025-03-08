// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "../../src/ERC20.sol";

/// @title simplified mock synth token for testing
contract MockSynth is ERC20 {

    constructor(
        string memory name_,
        string memory symbol_
    )
        ERC20(name_, symbol_)
    {}

    // Public mint function - anyone can mint tokens for testing purposes
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

}
