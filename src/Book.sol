// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Price} from "./types/Price.sol";
import {Queue} from "./Queue.sol";

contract Book {

    using Queue for Queue.T;

    address sBID;
    address sASK;

    enum KIND {
        Market,
        Limit
    }

    enum SIDE {
        Bid,
        Ask
    }

    struct Order {
        KIND kind;
        SIDE side;
        Price price;
        uint256 quantity;
    }

    struct Level {
        uint256 bidDepth;
        uint256 askDepth;
        Queue.T bids;
        Queue.T asks;
    }

    mapping(Price tick => Level level) internal levels;

    function depth(Price tick_)
        public
        view
        returns (uint256 bids, uint256 asks)
    {}

    function place(Order calldata order_) public {}

    function remove() public {}

    function fill() public {}

}
