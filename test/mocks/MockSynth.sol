// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "../../src/ERC20.sol";

/// @title simplified mock synth token for testing
/// @author jaredborders
/// @author flocast
/// @custom:version v0.0.1
contract MockSynth is ERC20 {

    /// @notice construct a new tokenized mock synth
    /// @param name_ name of the token
    /// @param symbol_ symbol of the token
    constructor(
        string memory name_,
        string memory symbol_
    )
        ERC20(name_, symbol_)
    {}

    /// @notice allows any caller to mint tokens
    /// @dev for testing purposes only
    function mint(address to_, uint256 amount_) public {
        _mint(to_, amount_);
    }

}
