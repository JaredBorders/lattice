// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ERC20 as Synth} from "./ERC20.sol";
import {Hook} from "./Hook.sol";
import {Queue} from "./Queue.sol";

/// @title market mechanism supporting programmatic liquidity
/// @dev mechanism utilizes a bid/ask order book to facilitate trading
/// @author jaredborders
/// @custom:version v0.0.1
contract Market {

    /// @notice fifo queue library for bid/ask orders
    /// @dev enforces price-time priority in tandem with price levels
    using Queue for Queue.T;

    /*//////////////////////////////////////////////////////////////
                             MARKET TOKENS
    //////////////////////////////////////////////////////////////*/

    /// @notice asset in which bids are denominated
    /// @dev exchange price levels are denominated in numeraire; i.e.,
    /// settlement asset
    Synth immutable numeraire;

    /// @notice asset in which asks are denominated
    /// @dev price level is denominated in index; i.e., speculative asset
    Synth immutable index;

    /*//////////////////////////////////////////////////////////////
                          MARKET ENUMERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice enumeration of supported order types
    /// @custom:MARKET indicates order to be filled at best available price
    /// @custom:LIMIT indicates order to be filled at specified price
    enum KIND {
        MARKET,
        LIMIT
    }

    /// @notice enumeration of possible order sides
    /// @custom:BID indicates intent to exchange index for numeraire
    /// @custom:ASK indicates intent to exchange numeraire for index
    enum SIDE {
        BID,
        ASK
    }

    /// @notice enumeration of possible trader classifications
    /// @dev serves additional context if trader prefers maker/taker status
    /// @custom:ANY indicates the classification is irrelevant
    /// @custom:MAKER indicates order placed by trader adds book liquidity
    /// @custom:TAKER indicates order placed by trader removes book liquidity
    enum PARTICIPANT {
        ANY,
        MAKER,
        TAKER
    }

    /// @notice enumeration of possible order statuses
    /// @dev only OPEN and PARTIAL orders are eligible for matching
    /// @custom:NULL indicates order has not been placed
    /// @custom:OPEN indicates order has been placed and awaiting matching
    /// @custom:PARTIAL indicates order has been partially filled
    /// @custom:FILLED indicates order has been completely filled
    /// @custom:CANCELLED indicates order has been removed from the book
    enum STATUS {
        NULL,
        OPEN,
        PARTIAL,
        FILLED,
        CANCELLED
    }

    /*//////////////////////////////////////////////////////////////
                            MARKET TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice type for price levels in the order book
    type Price is uint256;

    /*//////////////////////////////////////////////////////////////
                           MARKET STRUCTURES
    //////////////////////////////////////////////////////////////*/

    /// @notice defines the structure of a trade
    /// @dev side of trade indicates denomination of quantity
    /// @custom:KIND indicates the type of order to be placed
    /// @custom:SIDE indicates the direction of the order to be placed
    /// @custom:price indicates the price level at which the order is placed
    /// @custom:quantity indicates the intended amount of tokens to be exchanged
    struct Trade {
        KIND kind;
        SIDE side;
        Price price;
        uint256 quantity;
    }

    /// @notice defines the structure of an order recorded by the book
    /// @dev status of order indicates eligibility for matching
    /// @dev kind of order indicates how the order is to be filled
    /// @dev side of order indicates the direction of the order
    /// @custom:id unique identifier assigned to each order
    /// @custom:blocknumber at which order was placed
    /// @custom:trader address of the trader responsible for the order
    /// @custom:status indicates the current state of the order
    /// @custom:kind indicates the type of order to be placed
    /// @custom:side indicates the direction of the order to be placed
    /// @custom:price indicates the price level at which the order is placed
    /// @custom:quantity indicates the intended amount of tokens to be exchanged
    /// @custom:remaining indicates the amount of tokens yet to be exchanged
    struct Order {
        uint256 id;
        uint256 blocknumber;
        address trader;
        STATUS status;
        KIND kind;
        SIDE side;
        Price price;
        uint256 quantity;
        uint256 remaining;
    }

    /// @notice defines the structure of a price level in the order book
    /// @dev bidDepth is measured in numeraire tokens at the price level
    /// @dev askDepth is measured in index tokens at the price level
    /// @custom:bidDepth indicates total open bid interest at price level
    /// @custom:askDepth indicates total open ask interest at price level
    /// @custom:bids queue records bids eligible for matching at price level
    /// @custom:asks queue records asks eligible for matching at price level
    struct Level {
        uint256 bidDepth;
        uint256 askDepth;
        Queue.T bids;
        Queue.T asks;
    }

    /*//////////////////////////////////////////////////////////////
                               BOOK STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice maps id assigned to order to the order itself
    /// @dev order id is unique and incremented for each new order
    /// @dev records all orders, regardless of status, for reference
    mapping(uint256 id => Order) internal orders;

    /// @notice maps price to price level in the order book
    /// @dev price level is unique and precise to 18 decimal places
    mapping(Price price => Level) internal levels;

    /// @notice maps id assigned to order to trader responsible for order
    /// @dev allows for quick lookup of trader by order id
    mapping(uint256 id => address trader) internal traders;

    /// @notice unique identifier for each order
    /// @dev incremented for each new order
    /// @custom:cid acronym for "current identifier"
    uint256 private cid;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when an invalid price is provided
    error InvalidPrice();

    /// @notice thrown when an invalid quantity is provided
    error InvalidQuantity();

    /// @notice thrown when msg.sender is not the order owner
    error Unauthorized();

    /// @notice thrown when the order is already filled
    error OrderFilled();

    /// @notice thrown when the order is already cancelled
    error OrderCancelled();

    /// @notice thrown when operation is not supported for market orders
    error MarketOrderUnsupported();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new order is placed in the market
    /// @custom:id unique identifier assigned to the order
    /// @custom:blocknumber at which order was placed
    /// @custom:trader address of the trader responsible for the order
    /// @custom:side indicates the direction of the order
    /// @custom:price indicates the price level at which the order is placed
    /// @custom:quantity indicates the intended amount of tokens to be exchanged
    /// @custom:remaining indicates the amount of tokens yet to be exchanged
    /// @custom:status indicates the current state of the order
    /// @custom:blocknumber at which order was placed
    event OrderPlaced(
        uint256 indexed id,
        address indexed trader,
        SIDE side,
        Price price,
        uint256 quantity,
        uint256 remaining,
        STATUS status,
        uint256 blocknumber
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice creates market and defines the numeraire and index tokens
    /// @param numeraire_ address of the numeraire token
    /// @param index_ address of the index token
    constructor(address numeraire_, address index_) {
        numeraire = Synth(numeraire_);
        index = Synth(index_);
    }

    /*//////////////////////////////////////////////////////////////
                             INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    /// @notice get bid and ask depth at a specific price level
    /// @dev bid depth is measured in numeraire tokens
    /// @dev ask depth is measured in index tokens
    /// @param price_ level at which depth is queried
    /// @return bidDepth indicating open bid interest at price level
    /// @return askDepth indicating open ask interest at price level
    function depth(Price price_)
        public
        view
        returns (uint256 bidDepth, uint256 askDepth)
    {
        Level storage level = levels[price_];
        bidDepth = level.bidDepth;
        askDepth = level.askDepth;
    }

    /// @notice get set of bid order ids at a specific price level
    /// @param price_ level at which bids are queried
    /// @return set of bid order ids at price level
    function bids(Price price_) public view returns (uint256[] memory set) {
        Level storage level = levels[price_];
        set = level.bids.toArray();
    }

    /// @notice get set of ask order ids at a specific price level
    /// @param price_ level at which asks are queried
    /// @return set of ask order ids at price level
    function asks(Price price_) public view returns (uint256[] memory set) {
        Level storage level = levels[price_];
        set = level.asks.toArray();
    }

    /// @notice get order by id
    /// @param id_ unique identifier assigned to order
    /// @return order object associated with id
    function getOrder(uint256 id_) public view returns (Order memory) {
        return orders[id_];
    }

    /*//////////////////////////////////////////////////////////////
                                TRADING
    //////////////////////////////////////////////////////////////*/

    /// @notice place a trade on the order book
    /// @dev sufficient market token allowances expected
    /// @dev trade object is recorded within order book as an order
    /// @param trade_ defining the trade to be placed
    function place(Trade calldata trade_) public {
        if (trade_.quantity == 0) revert InvalidQuantity();
        if (Price.unwrap(trade_.price) == 0) revert InvalidPrice();

        if (trade_.kind == KIND.LIMIT) {
            if (trade_.side == SIDE.BID) {
                __placeBid(trade_);
            } else {
                __placeAsk(trade_);
            }
        }

        if (trade_.kind == KIND.MARKET) {
            if (trade_.side == SIDE.BID) {
                revert MarketOrderUnsupported();
            } else {
                revert MarketOrderUnsupported();
            }
        }
    }

    /// @notice remove an order from the order book by id
    /// @dev only order owner can remove order
    /// @dev order must not be filled or cancelled
    /// @param id_ unique identifier assigned to order
    function remove(uint256 id_) public {
        if (traders[id_] != msg.sender) revert Unauthorized();

        Order storage order = orders[id_];

        if (order.status == STATUS.FILLED) revert OrderFilled();
        if (order.status == STATUS.CANCELLED) revert OrderCancelled();
        if (order.kind == KIND.MARKET) revert MarketOrderUnsupported();

        order.status = STATUS.CANCELLED;

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

    /*//////////////////////////////////////////////////////////////
                              LIMIT ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice place a bid limit order on the order book
    /// @dev bid order is filled with available asks at price level
    /// @param trade_ defining the bid order to be placed
    /// @return id or unique identifier assigned to bid order placed
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
            blocknumber: block.number,
            trader: msg.sender,
            status: STATUS.OPEN,
            kind: trade_.kind,
            side: trade_.side,
            price: trade_.price,
            quantity: trade_.quantity,
            remaining: trade_.quantity
        });

        uint256 p = Price.unwrap(bid.price);
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

                // update bid order status
                bid.status = bid.remaining == 0 ? STATUS.FILLED : STATUS.PARTIAL;

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

            // update bid depth of current price level
            level.bidDepth += bid.remaining;
        }

        // add storage reference to bid order
        orders[id] = bid;

        // add storage reference to trader responsible for bid order
        traders[id] = msg.sender;

        emit OrderPlaced(
            id,
            msg.sender,
            bid.side,
            bid.price,
            bid.quantity,
            bid.remaining,
            bid.status,
            block.number
        );
    }

    /// @notice place an ask limit order on the order book
    /// @dev ask order is filled with available bids at price level
    /// @param trade_ defining the ask order to be placed
    /// @return id or unique identifier assigned to ask order placed
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
            blocknumber: block.number,
            trader: msg.sender,
            status: STATUS.OPEN,
            kind: trade_.kind,
            side: trade_.side,
            price: trade_.price,
            quantity: trade_.quantity,
            remaining: trade_.quantity
        });

        uint256 p = Price.unwrap(ask.price);
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

                // update ask order status
                ask.status = ask.remaining == 0 ? STATUS.FILLED : STATUS.PARTIAL;

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

            // update ask depth of current price level
            level.askDepth += ask.remaining;
        }

        // add storage reference to ask order
        orders[id] = ask;

        // add storage reference to trader responsible for ask order
        traders[id] = msg.sender;

        emit OrderPlaced(
            id,
            msg.sender,
            ask.side,
            ask.price,
            ask.quantity,
            ask.remaining,
            ask.status,
            block.number
        );
    }

}
