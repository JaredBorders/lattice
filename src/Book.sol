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

    struct Trade {
        address trader;
        KIND kind;
        SIDE side;
        Price price;
        uint256 quantity;
    }

    struct Order {
        uint256 id;
        Trade trade;
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
    mapping(address trader => uint256[] indices) internal trades;

    constructor(address clearinghouse_, address numeraire_, address index_) {
        clearinghouse = Clearinghouse(clearinghouse_);
        numeraire = Synth(numeraire_);
        index = Synth(index_);
    }

    function depth(Price tick_)
        public
        view
        returns (uint256 bids, uint256 asks)
    {
        Level storage level = levels[tick_];
        return (level.bidDepth, level.askDepth);
    }

    function place(Trade calldata trade_) public {
        // create reference to price level for given trade price
        Level storage level = levels[trade_.price];

        /// @custom:market orders are fill-or-kill; no partial fills
        if (trade_.kind == KIND.MARKET) {
            uint256 quantity = trade_.quantity;
            uint256 price = Price.unwrap(trade_.price);
            address trader = trade_.trader;

            /// @dev to fill, a bid must be matched with an ask
            if (trade_.side == SIDE.BID) {
                if (level.askDepth >= quantity / price) {
                    numeraire.transferFrom(trader, address(this), quantity);

                    fill(trade_);
                }
            }

            /// @dev to fill, an ask must be matched with a bid
            if (trade_.side == SIDE.ASK) {
                if (level.bidDepth >= quantity * price) {
                    index.transferFrom(trader, address(this), quantity);

                    fill(trade_);
                }
            }
        }

        /// @custom:limit orders are filled (partially or fully) when possible
        if (trade_.kind == KIND.LIMIT) {
            if (trade_.side == SIDE.BID) {
                level.bids.enqueue(id);
                level.bidDepth += trade_.quantity;
            }

            if (trade_.side == SIDE.ASK) {
                level.asks.enqueue(id);
                level.askDepth += trade_.quantity;
            }
        }

        id++;
    }

    function remove(uint256 orderId_) public {
        require(traders[orderId_] == msg.sender, "Not order owner");

        STATUS status = statuses[orderId_];

        require(
            status == STATUS.OPEN || status == STATUS.PARTIAL,
            "Order not removable"
        );

        Order storage order = orders[orderId_];
        Level storage level = levels[order.trade.price];

        statuses[orderId_] = STATUS.CANCELLED;

        if (order.trade.kind == KIND.LIMIT) {
            if (order.trade.side == SIDE.BID) {
                // Update bid depth
                level.bidDepth -= order.remaining;

                // Refund remaining numeraire tokens
                clearinghouse.transfer(
                    numeraire, order.remaining, address(this), msg.sender
                );
            }

            if (order.trade.side == SIDE.ASK) {
                // Update ask depth
                level.askDepth -= order.remaining;

                // Refund remaining index tokens
                clearinghouse.transfer(
                    index, order.remaining, address(this), msg.sender
                );
            }
        }
    }

    function fill(Trade calldata trade_) public view {}

    function fill(uint256 orderId_) public view {
        Order storage order = orders[orderId_];
        Level storage level = levels[order.trade.price];

        if (order.trade.side == SIDE.BID) {
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

        if (order.trade.side == SIDE.ASK) {
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
        if (bid_.trade.quantity < ask_.trade.quantity) return -1;
        if (bid_.trade.quantity > ask_.trade.quantity) return 1;
        return 0;
    }

}
