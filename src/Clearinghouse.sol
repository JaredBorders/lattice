// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20 as Synth} from "./ERC20.sol";

contract Clearinghouse {

    function transfer(
        Synth synth_,
        uint256 quantity_,
        address from_,
        address to_
    )
        public
    {
        synth_.transferFrom(from_, to_, quantity_);
    }

    function synthesize(Synth synth_, uint256 quantity_, address to_) public {}
    function desynthesize(
        Synth synth_,
        uint256 quantity_,
        address from_
    )
        public
    {}

}
