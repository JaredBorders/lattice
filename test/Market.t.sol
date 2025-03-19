// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ERC20 as Synth} from "../src/ERC20.sol";
import {Market} from "../src/Market.sol";
import {MockSynth} from "./mocks/MockSynth.sol";
import {Test} from "@forge-std/Test.sol";

/// @title test suite for market exchange
/// @author flocast
/// @author jaredborders
/// @custom:version v0.0.1
contract MarketTest is Test {

    Market market;

    MockSynth numeraire;
    MockSynth index;

    address internal constant JORDAN = address(0x01);
    address internal constant DONNIE = address(0x02);

    uint256 internal constant GAS_OPCODE_COST = 2;

    modifier prankster(address prankster_) {
        vm.startPrank(prankster_);
        _;
        vm.stopPrank();
    }

    function setUp() public {
        _setup_market_tokens();
        _setup_market();
        _setup_balances();
        _setup_allowances();
    }

    function _setup_market_tokens() internal {
        numeraire = new MockSynth("sUSD", "sUSD");
        index = new MockSynth("sETH", "sETH");
    }

    function _setup_market() internal {
        market = new Market(address(numeraire), address(index));
    }

    function _setup_balances() internal {
        numeraire.mint(JORDAN, type(uint128).max);
        numeraire.mint(DONNIE, type(uint128).max);
        index.mint(JORDAN, type(uint128).max);
        index.mint(DONNIE, type(uint128).max);
    }

    function _setup_allowances() internal {
        vm.startPrank(JORDAN);
        numeraire.approve(address(market), type(uint256).max);
        index.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(DONNIE);
        numeraire.approve(address(market), type(uint256).max);
        index.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

}

contract BidOrderTest is MarketTest {

    function test_place_bid(
        uint16 price,
        uint16 quantity
    )
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        vm.assume(quantity != 0);

        // observe initial token balances
        uint256 preTraderBalance = numeraire.balanceOf(JORDAN);
        uint256 preMarketBalance = numeraire.balanceOf(address(market));

        // observe initial book depth
        (uint256 preBidDepth, uint256 preAskDepth) = market.depth(price);

        // define and place a bid in the market
        market.place(
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, quantity)
        );

        // observe token balances following the trade
        uint256 postTraderBalance = numeraire.balanceOf(JORDAN);
        uint256 postMarketBalance = numeraire.balanceOf(address(market));

        // observe book depth following the trade
        (uint256 postBidDepth, uint256 postAskDepth) = market.depth(price);

        // verify token balances were correctly adjusted
        assertEq(postTraderBalance, preTraderBalance - quantity);
        assertEq(postMarketBalance, preMarketBalance + quantity);

        // verify book depth was correctly adjusted
        assertEq(postBidDepth, preBidDepth + quantity);
        assertEq(postAskDepth, preAskDepth);
    }

    function test_place_bids(
        uint16 price,
        uint16 quantity,
        uint8 trades
    )
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        vm.assume(quantity != 0);
        vm.assume(trades != 0);

        // observe initial token balances
        uint256 preTraderBalance = numeraire.balanceOf(JORDAN);
        uint256 preMarketBalance = numeraire.balanceOf(address(market));

        // observe initial book depth
        (uint256 preBidDepth, uint256 preAskDepth) = market.depth(price);

        // place trade(s); each trade has no variance
        for (uint8 i = 0; i < trades; i++) {
            market.place(
                Market.Trade(
                    Market.KIND.LIMIT, Market.SIDE.BID, price, quantity
                )
            );
        }

        // observe token balances following the trade(s)
        uint256 postTraderBalance = numeraire.balanceOf(JORDAN);
        uint256 postMarketBalance = numeraire.balanceOf(address(market));

        // observe book depth following the trade(s)
        (uint256 postBidDepth, uint256 postAskDepth) = market.depth(price);

        // verify token balances were correctly adjusted
        assertEq(
            postTraderBalance,
            preTraderBalance - (uint256(quantity) * uint256(trades))
        );
        assertEq(
            postMarketBalance,
            preMarketBalance + (uint256(quantity) * uint256(trades))
        );

        // verify book depth was correctly adjusted
        assertEq(
            postBidDepth, preBidDepth + (uint256(quantity) * uint256(trades))
        );
        assertEq(postAskDepth, preAskDepth);
    }

    function test_place_bids_trade_variance(
        uint16 price,
        uint16 quantity,
        uint8 trades,
        uint8 variance
    )
        public
        prankster(DONNIE)
    {
        vm.assume(price != 0);
        vm.assume(quantity != 0);
        vm.assume(trades != 0);
        vm.assume(variance != 0);

        // cast to uint256 to avoid overflow from variance arithmetic
        uint256 variedPrice = price;
        uint256 variedQuantity = quantity;

        // place trade(s); each trade has variance
        for (uint8 i = 0; i < trades; i++) {
            // observe initial token balances
            uint256 preTraderBalance = numeraire.balanceOf(DONNIE);
            uint256 preMarketBalance = numeraire.balanceOf(address(market));

            // observe initial book depth
            (uint256 preBidDepth, uint256 preAskDepth) =
                market.depth(variedPrice);

            market.place(
                Market.Trade(
                    Market.KIND.LIMIT,
                    Market.SIDE.BID,
                    variedPrice,
                    variedQuantity
                )
            );

            // observe token balances following the trade
            uint256 postTraderBalance = numeraire.balanceOf(DONNIE);
            uint256 postMarketBalance = numeraire.balanceOf(address(market));

            // observe book depth following the trade @ varied price
            (uint256 postBidDepth, uint256 postAskDepth) =
                market.depth(variedPrice);

            // verify token balances were correctly adjusted
            assertEq(postTraderBalance, preTraderBalance - variedQuantity);
            assertEq(postMarketBalance, preMarketBalance + variedQuantity);

            // verify book depth was correctly adjusted
            assertEq(postBidDepth, preBidDepth + variedQuantity);
            assertEq(postAskDepth, preAskDepth);

            // add variance to the price
            variedPrice += variance;

            // add variance to the quantity
            variedQuantity += variance;
        }
    }

    function test_place_bid_zero_quantity(uint16 price)
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        uint16 quantity = 0;

        vm.expectRevert("Invalid quantity");
        market.place(
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, quantity)
        );
    }

    function test_place_bid_zero_price(uint16 quantity)
        public
        prankster(JORDAN)
    {
        vm.assume(quantity != 0);
        uint16 price = 0;

        vm.expectRevert("Invalid price");
        market.place(
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, quantity)
        );
    }

}

contract BidBenchmarkTest is BidOrderTest {

    uint256 private constant BID_GAS_BENCHMARK = 278_611;
    uint256 private constant GAS_BLOCK_LIMIT = 30_000_000;
    uint256 private constant MAX_BIDS_PER_BLOCK = 107;

    function test_benchmark_place_bid() public prankster(DONNIE) {
        /// @custom:market sUSD:sETH Market
        /// @custom:observed ETH price Mar-18-2025 11:04:59 PM +UTC
        uint256 price = 1_919_470_000_000_000_000_000;

        /// @custom:numeraire quantity or bid size set to price
        /// @dev 1,919.47e18 sUSD can purchase 1 sETH @ observed price
        uint256 quantity = 1_919_470_000_000_000_000_000;

        Market.Trade memory bid =
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, quantity);

        uint256 gas = gasleft();

        market.place(bid);

        gas = (gas - gasleft()) + GAS_OPCODE_COST;

        assertEq(gas, BID_GAS_BENCHMARK);
        assertEq(MAX_BIDS_PER_BLOCK, GAS_BLOCK_LIMIT / BID_GAS_BENCHMARK);
    }

}

contract AskOrderTest is MarketTest {

    function test_place_ask(
        uint16 price,
        uint16 quantity
    )
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        vm.assume(quantity != 0);

        // observe initial token balances
        uint256 preTraderBalance = index.balanceOf(JORDAN);
        uint256 preMarketBalance = index.balanceOf(address(market));

        // observe initial book depth
        (uint256 preBidDepth, uint256 preAskDepth) = market.depth(price);

        // define and place an ask in the market
        market.place(
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity)
        );

        // observe token balances following the trade
        uint256 postTraderBalance = index.balanceOf(JORDAN);
        uint256 postMarketBalance = index.balanceOf(address(market));

        // observe book depth following the trade
        (uint256 postBidDepth, uint256 postAskDepth) = market.depth(price);

        // verify token balances were correctly adjusted
        assertEq(postTraderBalance, preTraderBalance - quantity);
        assertEq(postMarketBalance, preMarketBalance + quantity);

        // verify book depth was correctly adjusted
        assertEq(postBidDepth, preBidDepth);
        assertEq(postAskDepth, preAskDepth + quantity);
    }

    function test_place_bids(
        uint16 price,
        uint16 quantity,
        uint8 trades
    )
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        vm.assume(quantity != 0);
        vm.assume(trades != 0);

        // observe initial token balances
        uint256 preTraderBalance = index.balanceOf(JORDAN);
        uint256 preMarketBalance = index.balanceOf(address(market));

        // observe initial book depth
        (uint256 preBidDepth, uint256 preAskDepth) = market.depth(price);

        // place trade(s); each trade has no variance
        for (uint8 i = 0; i < trades; i++) {
            market.place(
                Market.Trade(
                    Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity
                )
            );
        }

        // observe token balances following the trade(s)
        uint256 postTraderBalance = index.balanceOf(JORDAN);
        uint256 postMarketBalance = index.balanceOf(address(market));

        // observe book depth following the trade(s)
        (uint256 postBidDepth, uint256 postAskDepth) = market.depth(price);

        // verify token balances were correctly adjusted
        assertEq(
            postTraderBalance,
            preTraderBalance - (uint256(quantity) * uint256(trades))
        );
        assertEq(
            postMarketBalance,
            preMarketBalance + (uint256(quantity) * uint256(trades))
        );

        // verify book depth was correctly adjusted
        assertEq(postBidDepth, preBidDepth);
        assertEq(
            postAskDepth, preAskDepth + (uint256(quantity) * uint256(trades))
        );
    }

    function test_place_bids_trade_variance(
        uint16 price,
        uint16 quantity,
        uint8 trades,
        uint8 variance
    )
        public
        prankster(DONNIE)
    {
        vm.assume(price != 0);
        vm.assume(quantity != 0);
        vm.assume(trades != 0);
        vm.assume(variance != 0);

        // cast to uint256 to avoid overflow from variance arithmetic
        uint256 variedPrice = price;
        uint256 variedQuantity = quantity;

        // place trade(s); each trade has variance
        for (uint8 i = 0; i < trades; i++) {
            // observe initial token balances
            uint256 preTraderBalance = index.balanceOf(DONNIE);
            uint256 preMarketBalance = index.balanceOf(address(market));

            // observe initial book depth
            (uint256 preBidDepth, uint256 preAskDepth) =
                market.depth(variedPrice);

            market.place(
                Market.Trade(
                    Market.KIND.LIMIT,
                    Market.SIDE.ASK,
                    variedPrice,
                    variedQuantity
                )
            );

            // observe token balances following the trade
            uint256 postTraderBalance = index.balanceOf(DONNIE);
            uint256 postMarketBalance = index.balanceOf(address(market));

            // observe book depth following the trade @ varied price
            (uint256 postBidDepth, uint256 postAskDepth) =
                market.depth(variedPrice);

            // verify token balances were correctly adjusted
            assertEq(postTraderBalance, preTraderBalance - variedQuantity);
            assertEq(postMarketBalance, preMarketBalance + variedQuantity);

            // verify book depth was correctly adjusted
            assertEq(postBidDepth, preBidDepth);
            assertEq(postAskDepth, preAskDepth + variedQuantity);

            // add variance to the price
            variedPrice += variance;

            // add variance to the quantity
            variedQuantity += variance;
        }
    }

    function test_place_bid_zero_quantity(uint16 price)
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        uint16 quantity = 0;

        vm.expectRevert("Invalid quantity");
        market.place(
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity)
        );
    }

    function test_place_bid_zero_price(uint16 quantity)
        public
        prankster(JORDAN)
    {
        vm.assume(quantity != 0);
        uint16 price = 0;

        vm.expectRevert("Invalid price");
        market.place(
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity)
        );
    }

}

contract AskBenchmarkTest is AskOrderTest {

    uint256 private constant ASK_GAS_BENCHMARK = 278_647;
    uint256 private constant GAS_BLOCK_LIMIT = 30_000_000;
    uint256 private constant MAX_ASKS_PER_BLOCK = 107;

    function test_benchmark_place_ask() public prankster(DONNIE) {
        /// @custom:market sUSD:sETH Market
        /// @custom:observed ETH price Mar-18-2025 11:04:59 PM +UTC
        uint256 price = 1_919_470_000_000_000_000_000;

        /// @custom:index quantity or ask size set to price
        /// @dev 1 sETH can be sold for 1,919.47e18 sUSD @ observed price
        uint256 quantity = 1_919_470_000_000_000_000_000;

        Market.Trade memory ask =
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity);

        uint256 gas = gasleft();

        market.place(ask);

        gas = (gas - gasleft()) + GAS_OPCODE_COST;

        assertEq(gas, ASK_GAS_BENCHMARK);
        assertEq(MAX_ASKS_PER_BLOCK, GAS_BLOCK_LIMIT / ASK_GAS_BENCHMARK);
    }

}

contract PriceLevelTest is MarketTest {}

contract OrderSettlementTest is MarketTest {

    function test_bid_filled_by_ask(uint16 price, uint16 quantity) public {
        vm.assume(price != 0);
        vm.assume(quantity != 0);
        vm.assume(uint256(price) * uint256(quantity) <= type(uint32).max);

        // First place a bid as JORDAN
        uint256 bidQuantity = uint256(price) * uint256(quantity);
        Market.Trade memory bid =
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, bidQuantity);

        uint256 jordanInitialNumeraire = numeraire.balanceOf(JORDAN);
        uint256 jordanInitialIndex = index.balanceOf(JORDAN);
        uint256 donnieInitialNumeraire = numeraire.balanceOf(DONNIE);
        uint256 donnieInitialIndex = index.balanceOf(DONNIE);

        vm.prank(JORDAN);
        market.place(bid);

        // Verify the bid is placed
        uint256 bidDepth;
        (bidDepth,) = market.depth(price);
        assertEq(bidDepth, bidQuantity);

        // Now place a matching ask as DONNIE
        Market.Trade memory ask =
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity);

        vm.prank(DONNIE);
        market.place(ask);

        // Verify the orders have been matched and settled
        uint256 askDepth;
        (bidDepth, askDepth) = market.depth(price);

        assertEq(bidDepth, 0);
        assertEq(askDepth, 0);

        // Calculate expected token transfers
        uint256 expectedIndexTransfer = quantity;
        uint256 expectedNumeraireTransfer = uint256(price) * uint256(quantity);

        // Verify JORDAN received the index tokens and spent numeraire
        assertEq(
            index.balanceOf(JORDAN), jordanInitialIndex + expectedIndexTransfer
        );
        assertEq(
            numeraire.balanceOf(JORDAN),
            jordanInitialNumeraire - expectedNumeraireTransfer
        );

        // Verify DONNIE received the numeraire tokens and spent index
        assertEq(
            numeraire.balanceOf(DONNIE),
            donnieInitialNumeraire + expectedNumeraireTransfer
        );
        assertEq(
            index.balanceOf(DONNIE), donnieInitialIndex - expectedIndexTransfer
        );
    }

    function test_ask_filled_by_bid(uint16 price, uint16 quantity) public {
        vm.assume(price != 0);
        vm.assume(quantity != 0);
        vm.assume(uint256(price) * uint256(quantity) <= type(uint32).max);

        // First place an ask as JORDAN
        Market.Trade memory ask =
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity);

        uint256 jordanInitialNumeraire = numeraire.balanceOf(JORDAN);
        uint256 jordanInitialIndex = index.balanceOf(JORDAN);
        uint256 donnieInitialNumeraire = numeraire.balanceOf(DONNIE);
        uint256 donnieInitialIndex = index.balanceOf(DONNIE);

        vm.prank(JORDAN);
        market.place(ask);

        // Verify the ask is placed
        uint256 askDepth;
        (, askDepth) = market.depth(price);
        assertEq(askDepth, quantity);

        // Now place a matching bid as DONNIE
        uint256 bidQuantity = uint256(price) * uint256(quantity);
        Market.Trade memory bid =
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, bidQuantity);

        vm.prank(DONNIE);
        market.place(bid);

        // Verify the orders have been matched and settled
        uint256 bidDepth;
        (bidDepth, askDepth) = market.depth(price);

        assertEq(bidDepth, 0);
        assertEq(askDepth, 0);

        // Calculate expected token transfers
        uint256 expectedIndexTransfer = quantity;
        uint256 expectedNumeraireTransfer = uint256(price) * uint256(quantity);

        // Verify JORDAN received the numeraire tokens and spent index
        assertEq(
            numeraire.balanceOf(JORDAN),
            jordanInitialNumeraire + expectedNumeraireTransfer
        );
        assertEq(
            index.balanceOf(JORDAN), jordanInitialIndex - expectedIndexTransfer
        );

        // Verify DONNIE received the index tokens and spent numeraire
        assertEq(
            index.balanceOf(DONNIE), donnieInitialIndex + expectedIndexTransfer
        );
        assertEq(
            numeraire.balanceOf(DONNIE),
            donnieInitialNumeraire - expectedNumeraireTransfer
        );
    }

    function test_partial_fill(uint16 price, uint16 smallQuantity) public {
        vm.assume(price != 0);
        vm.assume(smallQuantity != 0);
        vm.assume(
            uint256(price) * uint256(smallQuantity) <= type(uint32).max / 4
        );

        uint256 smallBidValue = uint256(price) * uint256(smallQuantity);
        uint256 largeBidValue = smallBidValue * 3;

        // Place a large bid
        Market.Trade memory largeBid = Market.Trade(
            Market.KIND.LIMIT, Market.SIDE.BID, price, largeBidValue
        );

        vm.prank(JORDAN);
        market.place(largeBid);

        // Place a smaller ask that should partially fill the bid
        Market.Trade memory smallAsk = Market.Trade(
            Market.KIND.LIMIT, Market.SIDE.ASK, price, smallQuantity
        );

        vm.prank(DONNIE);
        market.place(smallAsk);

        // Verify that the bid is partially filled
        uint256 bidDepth;
        uint256 askDepth;
        (bidDepth, askDepth) = market.depth(price);

        uint256 expectedRemainingBid = largeBidValue - smallBidValue;

        assertEq(bidDepth, expectedRemainingBid);
        assertEq(askDepth, 0);
    }

}

contract RemoveOrderTest is MarketTest {

    function test_remove_bid(
        uint16 price,
        uint16 quantity
    )
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        vm.assume(quantity != 0);

        // Place a bid
        Market.Trade memory bid =
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, quantity);

        uint256 initialUserBalance = numeraire.balanceOf(JORDAN);
        uint256 initialMarketBalance = numeraire.balanceOf(address(market));

        market.place(bid);

        // Verify bid is placed
        (uint256 bidDepth,) = market.depth(price);
        assertEq(bidDepth, quantity);
        assertEq(numeraire.balanceOf(JORDAN), initialUserBalance - quantity);

        market.remove(0);

        // Verify bid is removed
        (bidDepth,) = market.depth(price);
        assertEq(bidDepth, 0);

        // Verify funds returned
        assertEq(numeraire.balanceOf(JORDAN), initialUserBalance);
        assertEq(numeraire.balanceOf(address(market)), initialMarketBalance);
    }

    function test_remove_ask(
        uint16 price,
        uint16 quantity
    )
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        vm.assume(quantity != 0);

        // Place an ask
        Market.Trade memory ask =
            Market.Trade(Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity);

        uint256 initialUserBalance = index.balanceOf(JORDAN);
        uint256 initialMarketBalance = index.balanceOf(address(market));

        market.place(ask);

        // Verify ask is placed
        (, uint256 askDepth) = market.depth(price);
        assertEq(askDepth, quantity);
        assertEq(index.balanceOf(JORDAN), initialUserBalance - quantity);

        market.remove(0);

        // Verify ask is removed
        (, askDepth) = market.depth(price);
        assertEq(askDepth, 0);

        // Verify funds returned
        assertEq(index.balanceOf(JORDAN), initialUserBalance);
        assertEq(index.balanceOf(address(market)), initialMarketBalance);
    }

}

contract MakerFeeTest is MarketTest {}

contract TakerFeeTest is MarketTest {}
