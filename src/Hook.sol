// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Exchange} from "./Exchange.sol";

/// @title programmatic liquidity hook
/// @dev specifies logic executed pre/post liquidity event
/// @author jaredborders
/// @custom:version v0.0.1
library Hook {

    /// @notice method called during hook dispatch
    /// @custom:PLACE method places a trade
    /// @custom:REMOVE method removes a trade identified the cid
    enum METHOD {
        PLACE,
        REMOVE
    }

    /// @notice operation to be executed
    /// @custom:method identifing the exchange operation to be executed
    /// @custom:parameters expected by the specified exchange operation
    struct Operation {
        METHOD method;
        bytes parameters;
    }

    /// @notice dispatches the operation to the exchange
    /// @dev reentrancy considerations expected to be handled by the exchange
    /// @param exchange_ upon which the operation is executed
    /// @param op_ defining the operation to be executed
    function _dispatch(Exchange exchange_, Operation memory op_) internal {
        if (op_.method == METHOD.PLACE) {
            exchange_.place(abi.decode(op_.parameters, (Exchange.Trade)));
            return;
        }

        if (op_.method == METHOD.REMOVE) {
            exchange_.remove(abi.decode(op_.parameters, (uint256)));
            return;
        }
    }

}
