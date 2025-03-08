// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Clearinghouse} from "./Clearinghouse.sol";
import {ERC20 as Synth} from "./ERC20.sol";
import {Price} from "./Price.sol";
import {Queue} from "./Queue.sol";

/// @title minimal limit order book logic
/// @author jaredborders
/// @custom:version v0.0.1
contract Book {

    using Queue for Queue.T;

    Clearinghouse clearinghouse;

    Synth numeraire;
    Synth index;

    enum KIND {
        MARKET,
        LIMIT
    }

    enum SIDE {
        BID,
        ASK
    }

    enum STATUS {
        NULL,
        OPEN,
        PARTIAL,
        FILLED,
        CANCELLED
    }

    struct Order {
        uint256 id;
        address trader;
        KIND kind;
        SIDE side;
        Price price;
        uint256 quantity;
        uint256 remaining;
    }

    struct Level {
        uint256 bidDepth;
        uint256 askDepth;
        Queue.T bids;
        Queue.T asks;
    }

    uint256 private id;

    mapping(Price tick => Level level) internal levels;
    mapping(uint256 index => Order order) internal orders;
    mapping(uint256 index => STATUS status) internal statuses;
    mapping(uint256 index => address trader) internal traders;
    mapping(address trader => uint256 indices) internal trades;

    function depth(Price tick_)
        public
        view
        returns (uint256 bids, uint256 asks)
    {}

    function place(Order memory order_) public {
        Level storage level = levels[order_.price];

        order_.id = id;
        orders[id] = order_;
        statuses[id] = STATUS.OPEN;
        traders[id] = msg.sender;
        trades[msg.sender] = id;

        if (order_.kind == KIND.MARKET) {
            if (order_.side == SIDE.BID) {
                if (level.askDepth < order_.quantity) return;
                clearinghouse.transfer(
                    numeraire, order_.quantity, address(this)
                );
                fill(id);
            }

            if (order_.side == SIDE.ASK) {
                if (level.bidDepth < order_.quantity) return;
                clearinghouse.transfer(index, order_.quantity, address(this));
                fill(id);
            }
        }

        if (order_.kind == KIND.LIMIT) {
            if (order_.side == SIDE.BID) {
                clearinghouse.transfer(
                    numeraire, order_.quantity, address(this)
                );
                level.bids.enqueue(id);
                level.bidDepth += order_.quantity;
            }

            if (order_.side == SIDE.ASK) {
                clearinghouse.transfer(index, order_.quantity, address(this));
                level.asks.enqueue(id);
                level.askDepth += order_.quantity;
            }
        }

        id++;
    }

    /// @custom:todo
    function remove(uint256 orderId_) public {}

    function fill(uint256 orderId_) public view {
        Order storage order = orders[orderId_];
        Level storage level = levels[order.price];

        if (order.side == SIDE.BID) {
            // fill bid order with ask order(s)
            // - bid order status must be FILLED
            // - ask order status must be FILLED unless last ask order
            // - last ask order can be PARTIAL or FILLED
            do {
                uint256 askId = level.asks.peek();
                Order storage ask = orders[askId];

                /// @custom:todo

                if (__compareQuantity(order, ask) == 0) break;
                if (__compareQuantity(order, ask) == -1) break;
                if (__compareQuantity(order, ask) == 1) break;

                // filled ask orders must be dequeued/removed
                // if partial ask order:
                // - update ask order quantity
                // - update ask order status to PARTIAL
                // - do not dequeue ask order

                // ensure ask depth is updated following every fill
            } while (true);
        }

        if (order.side == SIDE.ASK) {
            // fill ask order with bid order(s)
            // - ask order status must be FILLED
            // - bid order status must be FILLED unless last bid order
            // - last bid order can be PARTIAL or FILLED
            do {
                uint256 bidId = level.bids.peek();
                Order storage bid = orders[bidId];

                /// @custom:todo

                if (__compareQuantity(bid, order) == 0) break;
                if (__compareQuantity(bid, order) == -1) break;
                if (__compareQuantity(bid, order) == 1) break;

                // filled bid orders must be dequeued/removed
                // if partial bid order:
                // - update bid order quantity
                // - update bid order status to PARTIAL
                // - do not dequeue bid order

                // ensure bid depth is updated following every fill
            } while (true);
        }

        // if filled order is market order:
        // - update order status to FILLED
        // - do not dequeue order (it was never enqueued)

        // if filled order is limit order:
        // - update order status to FILLED
        // - dequeue order
    }

    /// @custom:todo
    function __compareQuantity(
        Order memory bid_,
        Order memory ask_
    )
        private
        pure
        returns (int256)
    {
        if (bid_.quantity < ask_.quantity) return -1;
        if (bid_.quantity > ask_.quantity) return 1;
        return 0;
    }

}
