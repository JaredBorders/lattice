// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ERC20 as Synth} from "./ERC20.sol";
import {Hook} from "./Hook.sol";
import {Queue} from "./Queue.sol";
import {RedBlackTreeLib} from "@solady/utils/RedBlackTreeLib.sol";

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
    type Price is uint128;

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
        uint128 quantity;
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
        uint64 id;
        uint32 blocknumber;
        address trader;
        STATUS status;
        KIND kind;
        SIDE side;
        Price price;
        uint128 quantity;
        uint128 remaining;
    }

    /// @notice defines the structure of a price level in the order book
    /// @dev bidDepth is measured in numeraire tokens at the price level
    /// @dev askDepth is measured in index tokens at the price level
    /// @custom:bidDepth indicates total open bid interest at price level
    /// @custom:askDepth indicates total open ask interest at price level
    /// @custom:bids queue records bids eligible for matching at price level
    /// @custom:asks queue records asks eligible for matching at price level
    struct Level {
        uint128 bidDepth;
        uint128 askDepth;
        Queue.T bids;
        Queue.T asks;
    }

    /*//////////////////////////////////////////////////////////////
                               BOOK STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice maps id assigned to order to the order itself
    /// @dev order id is unique and incremented for each new order
    /// @dev records all orders, regardless of status, for reference
    mapping(uint64 id => Order) internal orders;

    /// @notice maps price to price level in the order book
    /// @dev price level is unique and precise to 18 decimal places
    mapping(Price price => Level) internal levels;

    /// @notice maps id assigned to order to trader responsible for order
    /// @dev allows for quick lookup of trader by order id
    mapping(uint64 id => address trader) internal traders;

    /// @notice unique identifier for each order
    /// @dev incremented for each new order
    /// @custom:cid acronym for "current identifier"
    uint64 private cid = 1;

    /// @notice Red-Black Trees for tracking price levels in order of priority
    /// @dev bidTree keys are negated to sort in descending order (highest bids
    /// first)
    RedBlackTreeLib.Tree private bidTree;
    RedBlackTreeLib.Tree private askTree;

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

    /// @notice thrown when there is no liquidity to fill a market order
    error InsufficientLiquidity();

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
        uint64 indexed id,
        address indexed trader,
        SIDE side,
        Price price,
        uint128 quantity,
        uint128 remaining,
        STATUS status,
        uint32 blocknumber
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
        returns (uint128 bidDepth, uint128 askDepth)
    {
        Level storage level = levels[price_];
        bidDepth = level.bidDepth;
        askDepth = level.askDepth;
    }

    /// @notice get set of bid order ids at a specific price level
    /// @param price_ level at which bids are queried
    /// @return set of bid order ids at price level
    function bids(Price price_) public view returns (uint64[] memory set) {
        Level storage level = levels[price_];
        set = level.bids.toArray();
    }

    /// @notice get set of ask order ids at a specific price level
    /// @param price_ level at which asks are queried
    /// @return set of ask order ids at price level
    function asks(Price price_) public view returns (uint64[] memory set) {
        Level storage level = levels[price_];
        set = level.asks.toArray();
    }

    /// @notice get order by id
    /// @param id_ unique identifier assigned to order
    /// @return order object associated with id
    function getOrder(uint64 id_) public view returns (Order memory) {
        return orders[id_];
    }

    /// @notice get best bid price (highest price)
    function getBestBidPrice() public view returns (Price) {
        bytes32 keyPtr = RedBlackTreeLib.first(bidTree);
        if (RedBlackTreeLib.isEmpty(keyPtr)) {
            return Price.wrap(0);
        }
        uint256 key = RedBlackTreeLib.value(keyPtr);
        // Bids are stored with negated keys for proper sorting (highest first)
        return Price.wrap(type(uint128).max - uint128(key));
    }

    /// @notice get best ask price (lowest price)
    function getBestAskPrice() public view returns (Price) {
        bytes32 keyPtr = RedBlackTreeLib.first(askTree);
        if (RedBlackTreeLib.isEmpty(keyPtr)) {
            return Price.wrap(0);
        }
        return Price.wrap(uint128(RedBlackTreeLib.value(keyPtr)));
    }

    /// @notice get all price levels in the bid book (descending order)
    function getAllBidPrices() public view returns (Price[] memory) {
        uint256[] memory keys = RedBlackTreeLib.values(bidTree);
        Price[] memory prices = new Price[](keys.length);

        for (uint256 i = 0; i < keys.length; i++) {
            // Convert from negated storage format
            prices[i] = Price.wrap(type(uint128).max - uint128(keys[i]));
        }

        return prices;
    }

    /// @notice get all price levels in the ask book (ascending order)
    function getAllAskPrices() public view returns (Price[] memory) {
        uint256[] memory keys = RedBlackTreeLib.values(askTree);
        Price[] memory prices = new Price[](keys.length);

        for (uint256 i = 0; i < keys.length; i++) {
            prices[i] = Price.wrap(uint128(keys[i]));
        }

        return prices;
    }

    /// @notice get the next best ask price after a given price
    /// @param currentPrice The current ask price
    /// @return The next ask price, or Price.wrap(0) if no next price
    function getNextAskPrice(Price currentPrice)
        internal
        view
        returns (Price)
    {
        uint128 currentKey = Price.unwrap(currentPrice);
        bytes32 keyPtr = RedBlackTreeLib.find(askTree, currentKey);
        if (RedBlackTreeLib.isEmpty(keyPtr)) {
            return Price.wrap(0);
        }
        bytes32 nextPtr = RedBlackTreeLib.next(keyPtr);
        if (RedBlackTreeLib.isEmpty(nextPtr)) {
            return Price.wrap(0);
        }
        return Price.wrap(uint128(RedBlackTreeLib.value(nextPtr)));
    }

    /// @notice get the next best bid price after a given price
    /// @param currentPrice The current bid price
    /// @return The next bid price, or Price.wrap(0) if no next price
    function getNextBidPrice(Price currentPrice)
        internal
        view
        returns (Price)
    {
        // Convert from negated storage format
        uint128 currentKey = type(uint128).max - Price.unwrap(currentPrice);
        bytes32 keyPtr = RedBlackTreeLib.find(bidTree, currentKey);
        if (RedBlackTreeLib.isEmpty(keyPtr)) {
            return Price.wrap(0);
        }
        bytes32 nextPtr = RedBlackTreeLib.next(keyPtr);
        if (RedBlackTreeLib.isEmpty(nextPtr)) {
            return Price.wrap(0);
        }
        // Convert back to actual price
        return Price.wrap(
            type(uint128).max - uint128(RedBlackTreeLib.value(nextPtr))
        );
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
                __placeMarketBid(trade_.quantity);
            } else {
                __placeMarketAsk(trade_.quantity);
            }
        }
    }

    /// @notice remove an order from the order book by id
    /// @dev only order owner can remove order
    /// @dev order must not be filled or cancelled
    /// @param id_ unique identifier assigned to order
    function remove(uint64 id_) public {
        if (traders[id_] != msg.sender) revert Unauthorized();

        Order storage order = orders[id_];

        if (order.status == STATUS.FILLED) revert OrderFilled();
        if (order.status == STATUS.CANCELLED) revert OrderCancelled();
        if (order.kind == KIND.MARKET) revert MarketOrderUnsupported();

        order.status = STATUS.CANCELLED;

        Level storage level = levels[order.price];

        // cache remaining quantity of order
        uint128 remaining = order.remaining;

        // zero out remaining quantity of order
        order.remaining = 0;

        if (order.side == SIDE.BID) {
            // reduce bid depth of current price level
            level.bidDepth -= remaining;

            /// @custom:settle remaining numeraire tokens
            numeraire.transfer(msg.sender, remaining);

            level.bids.remove(id_);

            // if this price level is now empty, remove it from the tree
            if (level.bidDepth == 0) {
                // use negated key for bids (to sort in descending order)
                uint128 treeKey = type(uint128).max - Price.unwrap(order.price);
                RedBlackTreeLib.remove(bidTree, treeKey);
            }
        } else {
            //  reduce ask depth of current price level
            level.askDepth -= remaining;

            /// @custom:settle remaining index tokens
            index.transfer(msg.sender, remaining);

            level.asks.remove(id_);

            // if this price level is now empty, remove it from the tree
            if (level.askDepth == 0) {
                RedBlackTreeLib.remove(askTree, Price.unwrap(order.price));
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              LIMIT ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice place a bid limit order on the order book
    /// @dev bid order is filled with available asks at price level or better
    /// @param trade_ defining the bid order to be placed
    /// @return id or unique identifier assigned to bid order placed
    function __placeBid(Trade calldata trade_) private returns (uint64 id) {
        /// @dev immediately transfer numeraire tokens to contract
        numeraire.transferFrom(msg.sender, address(this), trade_.quantity);

        // assign bid order id to current identifier then increment
        id = cid++;

        /// @notice create new bid order (in memory)
        /// @dev bid status is OPEN until filled or cancelled
        /// @dev initially, remaining quantity is equal to total quantity
        Order memory bid = Order({
            id: id,
            blocknumber: uint32(block.number),
            trader: msg.sender,
            status: STATUS.OPEN,
            kind: trade_.kind,
            side: trade_.side,
            price: trade_.price,
            quantity: trade_.quantity,
            remaining: trade_.quantity
        });

        uint128 limitPrice = Price.unwrap(trade_.price);
        uint128 remainingNumeraire = trade_.quantity;

        Price currentAskPrice = getBestAskPrice();

        // match against ask orders at better prices first
        while (
            remainingNumeraire > 0 && Price.unwrap(currentAskPrice) > 0
                && Price.unwrap(currentAskPrice) <= limitPrice
        ) {
            // create reference to price level in contract storage
            Level storage level = levels[currentAskPrice];

            uint128 askPrice = Price.unwrap(currentAskPrice);

            uint128 maxIndexBuyable = remainingNumeraire / askPrice;
            if (maxIndexBuyable == 0) break;

            uint128 indexReceived = 0;
            bool continueMatching = true;

            // match against all orders at this price level
            while (
                continueMatching && !level.asks.isEmpty() && maxIndexBuyable > 0
            ) {
                uint64 askId = level.asks.peek();
                Order storage ask = orders[askId];

                uint128 askIndexRemaining = ask.remaining;

                if (maxIndexBuyable >= askIndexRemaining) {
                    // can fill entire ask
                    uint128 numeraireSpent = askIndexRemaining * askPrice;
                    remainingNumeraire -= numeraireSpent;
                    maxIndexBuyable -= askIndexRemaining;
                    indexReceived += askIndexRemaining;

                    // reduce ask depth of current price level
                    level.askDepth -= askIndexRemaining;

                    // update ask order remaining quantity to 0
                    ask.remaining = 0;

                    // update ask order status to FILLED
                    ask.status = STATUS.FILLED;

                    /// @custom:settle
                    numeraire.transfer(ask.trader, numeraireSpent);

                    /// @custom:dequeue ask order
                    level.asks.dequeue();
                } else {
                    // can only fill part of ask
                    uint128 numeraireSpent = maxIndexBuyable * askPrice;
                    remainingNumeraire -= numeraireSpent;
                    indexReceived += maxIndexBuyable;

                    // reduce ask depth of current price level
                    level.askDepth -= maxIndexBuyable;

                    // update ask order remaining quantity

                    ask.remaining -= maxIndexBuyable;

                    // ensure ask order status is PARTIAL
                    ask.status = STATUS.PARTIAL;

                    /// @custom:settle
                    numeraire.transfer(ask.trader, numeraireSpent);

                    continueMatching = false;
                }
            }

            /// @custom:settle
            if (indexReceived > 0) {
                index.transfer(msg.sender, indexReceived);
            }

            /// @dev We must find the next price level before removing the
            /// current one from the tree.
            /// This is because Solady's RedBlackTreeLib uses pointer-based
            /// traversal, and once a node
            /// is removed from the tree, we can no longer find its neighbors.
            /// This pattern ensures
            /// we preserve the traversal path by pre-calculating the next node
            /// before modifying the tree.
            Price nextAskPrice = Price.wrap(0);
            if (continueMatching && maxIndexBuyable > 0) {
                nextAskPrice = getNextAskPrice(currentAskPrice);
            }

            // remove empty price level from the tree
            if (level.askDepth == 0) {
                RedBlackTreeLib.remove(askTree, Price.unwrap(currentAskPrice));
            }

            // move to next price level if we can still buy more
            if (continueMatching && maxIndexBuyable > 0) {
                currentAskPrice = nextAskPrice;
            } else {
                break;
            }
        }

        // update bid order remaining quantity
        bid.remaining = remainingNumeraire;
        // update bid order status
        /// @dev Rather than only checking if bid.remaining is zero,
        /// this checks if the remaining numeraire is dust
        /// in which case the order is considered FILLED
        bid.status = ((bid.remaining / limitPrice) == 0)
            ? STATUS.FILLED
            : (remainingNumeraire < trade_.quantity) ? STATUS.PARTIAL : STATUS.OPEN;

        /// @dev if bid not fully filled, enqueue bid order
        if (bid.status != STATUS.FILLED) {
            Level storage level = levels[trade_.price];
            level.bids.enqueue(id);
            level.bidDepth += remainingNumeraire;

            // add this price level in the bid tree
            uint128 treeKey = type(uint128).max - limitPrice;
            if (!RedBlackTreeLib.exists(bidTree, treeKey)) {
                RedBlackTreeLib.insert(bidTree, treeKey);
            }
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
            uint32(block.number)
        );
    }

    /// @notice place an ask limit order on the order book
    /// @dev ask order is filled with available bids at price level or better
    /// @param trade_ defining the ask order to be placed
    /// @return id or unique identifier assigned to ask order placed
    function __placeAsk(Trade calldata trade_) private returns (uint64 id) {
        /// @dev immediately transfer index tokens to contract
        index.transferFrom(msg.sender, address(this), trade_.quantity);

        // assign ask order id to current identifier then increment
        id = cid++;

        /// @notice create new ask order (in memory)
        /// @dev ask status is OPEN until filled or cancelled
        /// @dev initially, remaining quantity is equal to total quantity
        Order memory ask = Order({
            id: id,
            blocknumber: uint32(block.number),
            trader: msg.sender,
            status: STATUS.OPEN,
            kind: trade_.kind,
            side: trade_.side,
            price: trade_.price,
            quantity: trade_.quantity,
            remaining: trade_.quantity
        });

        uint128 limitPrice = Price.unwrap(trade_.price);
        uint128 remainingIndex = trade_.quantity;

        Price currentBidPrice = getBestBidPrice();

        // match against bid orders at better prices first
        while (
            remainingIndex > 0 && Price.unwrap(currentBidPrice) > 0
                && Price.unwrap(currentBidPrice) >= limitPrice
        ) {
            // create reference to price level in contract storage
            Level storage level = levels[currentBidPrice];

            uint128 bidPrice = Price.unwrap(currentBidPrice);

            uint128 numeraireReceived = 0;
            bool continueMatching = true;

            // match against all orders at this price level
            while (
                continueMatching && !level.bids.isEmpty() && remainingIndex > 0
            ) {
                uint64 bidId = level.bids.peek();
                Order storage bid = orders[bidId];

                uint128 bidNumeraireRemaining = bid.remaining;
                uint128 maxIndexBuyable = bidNumeraireRemaining / bidPrice;

                if (maxIndexBuyable == 0) {
                    /// @custom:dequeue bid order
                    level.bids.dequeue();
                    continue;
                }

                if (maxIndexBuyable >= remainingIndex) {
                    // can fill our entire ask
                    uint128 numeraireToReceive = remainingIndex * bidPrice;
                    numeraireReceived += numeraireToReceive;

                    // reduce bid depth of current price level
                    level.bidDepth -= numeraireToReceive;

                    // update bid order remaining quantity
                    bid.remaining -= numeraireToReceive;

                    // update bid order status
                    /// @dev Rather than only checking if bid.remaining is zero,
                    /// this checks if the remaining numeraire is dust
                    /// in which case the order is considered FILLED
                    bid.status = ((bid.remaining / bidPrice) == 0)
                        ? STATUS.FILLED
                        : STATUS.PARTIAL;

                    /// @custom:settle
                    index.transfer(bid.trader, remainingIndex);

                    /// @custom:dequeue bid order
                    if (bid.status == STATUS.FILLED) {
                        level.bids.dequeue();
                    }

                    remainingIndex = 0;
                    continueMatching = false;
                } else {
                    // can only fill part of our ask
                    uint128 numeraireToReceive = maxIndexBuyable * bidPrice;
                    remainingIndex -= maxIndexBuyable;
                    numeraireReceived += numeraireToReceive;

                    // reduce bid depth of current price level
                    level.bidDepth -= numeraireToReceive;

                    // update bid order remaining quantity to 0
                    bid.remaining = 0;

                    // update bid order status to FILLED
                    bid.status = STATUS.FILLED;

                    /// @custom:settle
                    index.transfer(bid.trader, maxIndexBuyable);

                    /// @custom:dequeue bid order
                    level.bids.dequeue();
                }
            }

            /// @custom:settle
            if (numeraireReceived > 0) {
                numeraire.transfer(msg.sender, numeraireReceived);
            }

            /// @dev We must find the next price level before removing the
            /// current one from the tree.
            /// This is because Solady's RedBlackTreeLib uses pointer-based
            /// traversal, and once a node
            /// is removed from the tree, we can no longer find its neighbors.
            /// This pattern ensures
            /// we preserve the traversal path by pre-calculating the next node
            /// before modifying the tree.
            Price nextBidPrice = Price.wrap(0);
            if (continueMatching && remainingIndex > 0) {
                nextBidPrice = getNextBidPrice(currentBidPrice);
            }

            // remove empty price level from the tree
            if (level.bidDepth == 0) {
                uint128 treeKey =
                    type(uint128).max - Price.unwrap(currentBidPrice);
                RedBlackTreeLib.remove(bidTree, treeKey);
            }

            // move to next price level if we still have tokens to sell
            if (continueMatching && remainingIndex > 0) {
                currentBidPrice = nextBidPrice;
            } else {
                break;
            }
        }

        // update ask order remaining quantity
        ask.remaining = remainingIndex;

        // update ask order status
        ask.status = (remainingIndex == 0)
            ? STATUS.FILLED
            : (remainingIndex < trade_.quantity) ? STATUS.PARTIAL : STATUS.OPEN;

        /// @dev if ask not fully filled, enqueue ask order
        if (ask.status != STATUS.FILLED) {
            Level storage level = levels[trade_.price];
            level.asks.enqueue(id);
            level.askDepth += remainingIndex;

            // ensure this price level is in the ask tree
            if (!RedBlackTreeLib.exists(askTree, limitPrice)) {
                RedBlackTreeLib.insert(askTree, limitPrice);
            }
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
            uint32(block.number)
        );
    }

    /*//////////////////////////////////////////////////////////////
                              MARKET ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice place a bid market order on the order book
    /// @dev bid order is filled at best available ask prices
    /// @param quantity_ amount of numeraire tokens to spend
    function __placeMarketBid(uint128 quantity_) private {
        /// @dev immediately transfer numeraire tokens to contract
        numeraire.transferFrom(msg.sender, address(this), quantity_);

        // assign bid order id to current identifier then increment
        uint64 id = cid++;

        /// @notice create new bid order (in memory)
        /// @dev bid status is OPEN until filled or cancelled
        /// @dev initially, remaining quantity is equal to total quantity
        /// @custom:todo what to set for price for market orders
        Order memory bid = Order({
            id: id,
            blocknumber: uint32(block.number),
            trader: msg.sender,
            status: STATUS.OPEN,
            kind: KIND.MARKET,
            side: SIDE.BID,
            price: Price.wrap(1),
            quantity: quantity_,
            remaining: quantity_
        });

        Price currentPrice = getBestAskPrice();

        if (Price.unwrap(currentPrice) == 0) revert InsufficientLiquidity();

        uint128 remainingNumeraire = quantity_;
        uint128 indexReceived = 0;

        // match against ask orders at better prices first
        while (remainingNumeraire > 0 && Price.unwrap(currentPrice) > 0) {
            // create reference to price level in contract storage
            Level storage level = levels[currentPrice];

            uint128 price = Price.unwrap(currentPrice);

            // match against all orders at this price level
            while (!level.asks.isEmpty() && remainingNumeraire > 0) {
                uint64 askId = level.asks.peek();
                Order storage ask = orders[askId];

                uint128 askIndexRemaining = ask.remaining;
                uint128 maxIndexBuyable = remainingNumeraire / price;

                if (maxIndexBuyable == 0) break;

                uint128 indexToFill = (maxIndexBuyable >= askIndexRemaining)
                    ? askIndexRemaining
                    : maxIndexBuyable;
                uint128 numeraireToSpend = indexToFill * price;

                remainingNumeraire -= numeraireToSpend;
                indexReceived += indexToFill;

                // update ask order remaining quantity
                ask.remaining -= indexToFill;

                // update ask order status
                ask.status =
                    (ask.remaining == 0) ? STATUS.FILLED : STATUS.PARTIAL;

                // reduce ask depth of current price level
                level.askDepth -= indexToFill;

                /// @custom:settle
                numeraire.transfer(ask.trader, numeraireToSpend);

                /// @custom:dequeue ask order
                if (ask.remaining == 0) {
                    level.asks.dequeue();
                }
            }

            /// @dev We must find the next price level before removing the
            /// current one from the tree.
            /// This is because Solady's RedBlackTreeLib uses pointer-based
            /// traversal, and once a node
            /// is removed from the tree, we can no longer find its neighbors.
            /// This pattern ensures
            /// we preserve the traversal path by pre-calculating the next node
            /// before modifying the tree.
            Price nextAskPrice = Price.wrap(0);
            if (remainingNumeraire > 0) {
                nextAskPrice = getNextAskPrice(currentPrice);
            }

            // remove empty price level from the tree
            if (level.askDepth == 0) {
                RedBlackTreeLib.remove(askTree, Price.unwrap(currentPrice));
            }

            // move to next price level if order still not filled
            if (remainingNumeraire > 0) {
                currentPrice = nextAskPrice;
                if (Price.unwrap(currentPrice) == 0) break;
            }
        }

        /// @custom:settle
        if (indexReceived > 0) {
            index.transfer(msg.sender, indexReceived);
        }

        // update bid order remaining quantity
        bid.remaining = remainingNumeraire;

        // update bid order status
        bid.status = (remainingNumeraire == 0) ? STATUS.FILLED : STATUS.PARTIAL;

        /// @custom:settle
        if (remainingNumeraire > 0) {
            numeraire.transfer(msg.sender, remainingNumeraire);
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
            uint32(block.number)
        );
    }

    /// @notice place an ask market order on the order book
    /// @dev ask order is filled at best available bid prices
    /// @param quantity_ amount of index tokens to sell
    function __placeMarketAsk(uint128 quantity_) private {
        /// @dev immediately transfer index tokens to contract
        index.transferFrom(msg.sender, address(this), quantity_);

        // assign ask order id to current identifier then increment
        uint64 id = cid++;

        /// @notice create new ask order (in memory)
        /// @dev ask status is OPEN until filled or cancelled
        /// @dev initially, remaining quantity is equal to total quantity
        Order memory ask = Order({
            id: id,
            blocknumber: uint32(block.number),
            trader: msg.sender,
            status: STATUS.OPEN,
            kind: KIND.MARKET,
            side: SIDE.ASK,
            price: Price.wrap(1),
            quantity: quantity_,
            remaining: quantity_
        });

        Price currentPrice = getBestBidPrice();

        if (Price.unwrap(currentPrice) == 0) revert InsufficientLiquidity();

        uint128 remainingIndex = quantity_;
        uint128 numeraireReceived = 0;

        // match against bid orders at better prices first
        while (remainingIndex > 0 && Price.unwrap(currentPrice) > 0) {
            // create reference to price level in contract storage
            Level storage level = levels[currentPrice];

            uint128 price = Price.unwrap(currentPrice);

            // match against all orders at this price level
            while (!level.bids.isEmpty() && remainingIndex > 0) {
                uint64 bidId = level.bids.peek();
                Order storage bid = orders[bidId];

                uint128 bidNumeraireRemaining = bid.remaining;
                uint128 maxIndexSellable = bidNumeraireRemaining / price;

                if (maxIndexSellable == 0) {
                    /// @custom:dequeue bid order
                    level.bids.dequeue();
                    continue;
                }

                uint128 indexToFill = (maxIndexSellable >= remainingIndex)
                    ? remainingIndex
                    : maxIndexSellable;
                uint128 numeraireToReceive = indexToFill * price;
                remainingIndex -= indexToFill;
                numeraireReceived += numeraireToReceive;

                // update bid order remaining quantity
                bid.remaining -= numeraireToReceive;

                // update bid order status
                /// @dev Rather than only checking if bid.remaining is zero,
                /// this checks if the remaining numeraire is dust
                /// in which case the order is considered FILLED
                bid.status = ((bid.remaining / price) == 0)
                    ? STATUS.FILLED
                    : STATUS.PARTIAL;

                // reduce bid depth of current price level
                level.bidDepth -= numeraireToReceive;

                /// @custom:settle
                index.transfer(bid.trader, indexToFill);

                // @custom:dequeue bid order
                if (bid.remaining == 0) {
                    level.bids.dequeue();
                }
            }

            /// @dev We must find the next price level before removing the
            /// current one from the tree.
            /// This is because Solady's RedBlackTreeLib uses pointer-based
            /// traversal, and once a node
            /// is removed from the tree, we can no longer find its neighbors.
            /// This pattern ensures
            /// we preserve the traversal path by pre-calculating the next node
            /// before modifying the tree.
            Price nextBidPrice = Price.wrap(0);
            if (remainingIndex > 0) {
                nextBidPrice = getNextBidPrice(currentPrice);
            }

            // remove empty price level from the tree
            if (level.bidDepth == 0) {
                uint128 treeKey = type(uint128).max - Price.unwrap(currentPrice);
                RedBlackTreeLib.remove(bidTree, treeKey);
            }

            // move to next price level if order still not filled
            if (remainingIndex > 0) {
                currentPrice = nextBidPrice;
                if (Price.unwrap(currentPrice) == 0) break;
            }
        }

        /// @custom:settle
        if (numeraireReceived > 0) {
            numeraire.transfer(msg.sender, numeraireReceived);
        }

        // update ask order remaining quantity
        ask.remaining = remainingIndex;

        // update ask order status
        ask.status = (remainingIndex == 0) ? STATUS.FILLED : STATUS.PARTIAL;

        /// @custom:settle
        if (remainingIndex > 0) {
            index.transfer(msg.sender, remainingIndex);
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
            uint32(block.number)
        );
    }

}
