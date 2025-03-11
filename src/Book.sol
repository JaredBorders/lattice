// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20 as Synth} from "./ERC20.sol";
import {Queue} from "./Queue.sol";

/// @title minimal limit order book logic
/// @author jaredborders
/// @custom:version v0.0.1
contract Book {

    using Queue for Queue.T;

    Synth immutable numeraire;
    Synth immutable index;

    enum KIND {
        MARKET,
        LIMIT
    }

    enum SIDE {
        BID,
        ASK
    }

    enum PARTICIPANT {
        ANY,
        MAKER,
        TAKER
    }

    enum STATUS {
        NULL,
        OPEN,
        PARTIAL,
        FILLED,
        CANCELLED
    }

    struct Trade {
        KIND kind;
        SIDE side;
        uint256 price;
        uint256 quantity;
    }

    struct Order {
        uint256 id;
        address trader;
        STATUS status;
        KIND kind;
        SIDE side;
        uint256 price;
        uint256 quantity;
        uint256 remaining;
    }

    struct Level {
        uint256 bidDepth;
        uint256 askDepth;
        Queue.T bids;
        Queue.T asks;
    }

    /// @notice unique identifier for each order
    /// @dev incremented for each new order
    /// @custom:cid acronym for "current identifier"
    uint256 private cid;

    mapping(uint256 id => Order) internal orders;
    mapping(uint256 price => Level) internal levels;
    mapping(uint256 id => address trader) internal traders;
    mapping(address trader => uint256[] ids) internal trades;

    constructor(address numeraire_, address index_) {
        numeraire = Synth(numeraire_);
        index = Synth(index_);
    }

    function depth(uint256 price_)
        public
        view
        returns (uint256 bids, uint256 asks)
    {
        Level storage level = levels[price_];
        return (level.bidDepth, level.askDepth);
    }

    function place(Trade calldata trade_) public {
        if (trade_.quantity == 0) revert("Invalid quantity");
        if (trade_.price == 0) revert("Invalid price");

        if (trade_.kind == KIND.LIMIT) {
            if (trade_.side == SIDE.BID) {
                __placeBid(trade_);
            } else {
                __placeAsk(trade_);
            }
        }

        if (trade_.kind == KIND.MARKET) {
            if (trade_.side == SIDE.BID) {
                revert("Unsupported");
            } else {
                revert("Unsupported");
            }
        }
    }

    function remove(uint256 id_) public {
        require(traders[id_] == msg.sender, "Not order owner");
        require(orders[id_].status != STATUS.FILLED, "Order filled");
        require(orders[id_].status != STATUS.CANCELLED, "Order cancelled");
        require(orders[id_].kind != KIND.MARKET, "Market order");

        orders[id_].status = STATUS.CANCELLED;

        Order storage order = orders[id_];
        Level storage level = levels[order.price];

        // cache remaining quantity of order
        uint256 remaining = order.remaining;

        // zero out remaining quantity of order
        order.remaining = 0;

        if (order.side == SIDE.BID) {
            // reduce bid depth of current price level
            level.bidDepth -= remaining;

            /// @custom:settle remaining numeraire tokens
            numeraire.transfer(msg.sender, remaining);
        } else {
            //  reduce ask depth of current price level
            level.askDepth -= remaining;

            /// @custom:settle remaining index tokens
            index.transfer(msg.sender, remaining);
        }
    }

    // while there are asks at this price level,
    // fill the bid order with the ask order(s)
    // until the bid order is filled.
    //
    // if bid order was filled partially, update the bid order's
    // remaining quantity and enqueue bid order at this price level.
    //
    // if bid order was filled completely, update the bid order's
    // status to FILLED and do not enqueue bid order at this price level.
    //
    // if there are no asks at this price level, enqueue bid order.
    function __placeBid(Trade calldata trade_) private returns (uint256 id) {
        /// @dev immediately transfer numeraire tokens to contract
        numeraire.transferFrom(msg.sender, address(this), trade_.quantity);

        // create reference to price level in contract storage
        Level storage level = levels[trade_.price];

        // assign bid order id to current identifier then increment
        id = cid++;

        /// @notice create new bid order (in memory)
        /// @dev bid status is OPEN until filled or cancelled
        /// @dev initially, remaining quantity is equal to total quantity
        Order memory bid = Order({
            id: id,
            trader: msg.sender,
            status: STATUS.OPEN,
            kind: trade_.kind,
            side: trade_.side,
            price: trade_.price,
            quantity: trade_.quantity,
            remaining: trade_.quantity
        });

        uint256 p = bid.price;
        uint256 n = bid.quantity;
        uint256 i = n / p;

        while (!level.asks.isEmpty()) {
            uint256 askId = level.asks.peek();
            uint256 askRemaining = orders[askId].remaining;

            if (orders[askId].status == STATUS.CANCELLED) {
                level.asks.dequeue();
                continue;
            }

            if (i >= askRemaining) {
                // define amount of ask order filled
                uint256 askFilled = askRemaining;

                // decrement (i) to reflect bid quantity filled
                i -= askFilled;

                // reduce ask depth of current price level
                level.askDepth -= askFilled;

                // create reference to ask order
                Order storage ask = orders[askId];

                // update ask order status to FILLED
                ask.status = STATUS.FILLED;

                // update ask order remaining quantity to 0
                ask.remaining -= askFilled;

                // update bid order remaining quantity
                bid.remaining -= askFilled * p;

                // update bid order status to PARTIAL
                bid.status = STATUS.PARTIAL;

                /// @custom:settle
                numeraire.transfer(ask.trader, askFilled * p);
                index.transfer(msg.sender, askFilled);

                /// @custom:dequeue ask order
                level.asks.dequeue();
            } else {
                // define amount of ask order filled
                uint256 askFilled = i;

                // decrement (i) to reflect bid quantity filled
                i -= askFilled;

                // reduce ask depth of current price level
                level.askDepth -= askFilled;

                // create reference to ask order
                Order storage ask = orders[askId];

                // ensure ask order status is PARTIAL
                ask.status = STATUS.PARTIAL;

                // update ask order remaining quantity
                ask.remaining -= askFilled;

                // update bid order remaining quantity
                bid.remaining -= askFilled * p;

                // update bid order status to FILLED
                bid.status = STATUS.FILLED;

                /// @custom:settle
                numeraire.transfer(ask.trader, askFilled * p);
                index.transfer(msg.sender, askFilled);

                break;
            }
        }

        /// @dev if bid not fully filled, enqueue bid order
        if (bid.status != STATUS.FILLED) {
            level.bids.enqueue(id);
        }

        // update bid depth of current price level
        level.bidDepth += bid.remaining;

        // add storage reference to bid order
        orders[id] = bid;

        // add storage reference to trader responsible for bid order
        traders[id] = msg.sender;

        // add order id to the history of trades made by trader
        trades[msg.sender].push(id);
    }

    function __placeAsk(Trade calldata trade_) private returns (uint256 id) {
        /// @dev immediately transfer index tokens to contract
        index.transferFrom(msg.sender, address(this), trade_.quantity);

        // create reference to price level in contract storage
        Level storage level = levels[trade_.price];

        // assign ask order id to current identifier then increment
        id = cid++;

        /// @notice create new ask order (in memory)
        /// @dev ask status is OPEN until filled or cancelled
        /// @dev initially, remaining quantity is equal to total quantity
        Order memory ask = Order({
            id: id,
            trader: msg.sender,
            status: STATUS.OPEN,
            kind: trade_.kind,
            side: trade_.side,
            price: trade_.price,
            quantity: trade_.quantity,
            remaining: trade_.quantity
        });

        uint256 p = ask.price;
        uint256 i = ask.quantity;
        uint256 n = p * i;

        while (!level.bids.isEmpty()) {
            uint256 bidId = level.bids.peek();
            uint256 bidRemaining = orders[bidId].remaining;

            // if bid was previously cancelled, dequeue and continue
            if (orders[bidId].status == STATUS.CANCELLED) {
                level.bids.dequeue();
                continue;
            }

            // check if peeked bid can be filled completely by current ask
            if (n >= bidRemaining) {
                // define amount of bid order filled
                uint256 bidFilled = bidRemaining;

                // decrement (n) to reflect bid quantity filled
                n -= bidFilled;

                // reduce bid depth of current price level
                level.bidDepth -= bidFilled;

                // create reference to bid order
                Order storage bid = orders[bidId];

                // update bid order status to FILLED
                bid.status = STATUS.FILLED;

                // update bid order remaining quantity to 0
                bid.remaining -= bidFilled;

                // update ask order remaining quantity
                ask.remaining -= bidFilled / p;

                // update ask order status to PARTIAL
                ask.status = STATUS.PARTIAL;

                /// @custom:settle
                numeraire.transfer(msg.sender, bidFilled);
                index.transfer(bid.trader, bidFilled / p);

                /// @custom:dequeue bid order
                level.bids.dequeue();
            } else {
                // define amount of bid order filled
                uint256 bidFilled = n;

                // decrement (n) to reflect bid quantity filled
                n -= bidFilled;

                // reduce bid depth of current price level
                level.bidDepth -= bidFilled;

                // create reference to bid order
                Order storage bid = orders[bidId];

                // ensure bid order status is PARTIAL
                bid.status = STATUS.PARTIAL;

                // update bid order remaining quantity
                bid.remaining -= bidFilled;

                // update ask order remaining quantity
                ask.remaining -= bidFilled / p;

                // update ask order status to FILLED
                ask.status = STATUS.FILLED;

                /// @custom:settle
                numeraire.transfer(msg.sender, bidFilled);
                index.transfer(bid.trader, bidFilled / p);

                break;
            }
        }

        /// @dev if ask not fully filled, enqueue ask order
        if (ask.status != STATUS.FILLED) {
            level.asks.enqueue(id);
        }

        // update ask depth of current price level
        level.askDepth += ask.remaining;

        // add storage reference to ask order
        orders[id] = ask;

        // add storage reference to trader responsible for ask order
        traders[id] = msg.sender;

        // add order id to the history of trades made by trader
        trades[msg.sender].push(id);
    }

}
