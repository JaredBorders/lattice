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

    modifier prankster(address prankster_) {
        vm.startPrank(prankster_);
        _;
        vm.stopPrank();
    }

    function setUp() public {
        numeraire = new MockSynth("sUSD", "sUSD");
        index = new MockSynth("sETH", "sETH");

        market = new Market(address(numeraire), address(index));

        numeraire.mint(JORDAN, type(uint32).max);
        numeraire.mint(DONNIE, type(uint32).max);
        index.mint(JORDAN, type(uint32).max);
        index.mint(DONNIE, type(uint32).max);

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

    Market.Trade private bid;

    function test_place_bid(
        uint16 price,
        uint16 quantity
    )
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        vm.assume(quantity != 0);

        // Record initial balances
        uint256 initialUserBalance = numeraire.balanceOf(JORDAN);
        uint256 initialMarketBalance = numeraire.balanceOf(address(market));

        bid = Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, quantity);
        market.place(bid);

        // Verify the order was placed correctly
        (uint256 bidDepth, uint256 askDepth) = market.depth(price);
        assertEq(bidDepth, quantity);
        assertEq(askDepth, 0);

        // Verify trader funds were transferred
        assertEq(numeraire.balanceOf(JORDAN), initialUserBalance - quantity);
        assertEq(
            numeraire.balanceOf(address(market)),
            initialMarketBalance + quantity
        );
    }

    function test_place_bid_zero_quantity() public prankster(JORDAN) {
        uint16 price = 1000;
        uint16 quantity = 0;

        bid = Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, quantity);
        vm.expectRevert("Invalid quantity");
        market.place(bid);
    }

    function test_place_bid_zero_price() public prankster(JORDAN) {
        uint16 price = 0;
        uint16 quantity = 1000;

        bid = Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, quantity);
        vm.expectRevert("Invalid price");
        market.place(bid);
    }

    function test_place_multiple_bids(
        uint16 price,
        uint16 quantity1,
        uint16 quantity2
    )
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        vm.assume(quantity1 != 0);
        vm.assume(quantity2 != 0);

        // Place first bid
        bid = Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, quantity1);
        market.place(bid);

        // Place second bid at same price
        bid = Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, quantity2);
        market.place(bid);

        // Verify depth is updated correctly
        (uint256 bidDepth,) = market.depth(price);
        assertEq(bidDepth, uint256(quantity1) + uint256(quantity2));
    }

}

contract AskOrderTest is MarketTest {

    Market.Trade private ask;

    function test_place_ask(
        uint16 price,
        uint16 quantity
    )
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        vm.assume(quantity != 0);

        // Record initial balances
        uint256 initialUserBalance = index.balanceOf(JORDAN);
        uint256 initialMarketBalance = index.balanceOf(address(market));

        // Place an ask
        ask = Market.Trade(Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity);
        market.place(ask);

        // Verify the order was placed correctly
        (uint256 bidDepth, uint256 askDepth) = market.depth(price);
        assertEq(bidDepth, 0);
        assertEq(askDepth, quantity);

        // Verify trader funds were transferred
        assertEq(index.balanceOf(JORDAN), initialUserBalance - quantity);
        assertEq(
            index.balanceOf(address(market)), initialMarketBalance + quantity
        );
    }

    function test_place_ask_zero_quantity() public prankster(JORDAN) {
        uint16 price = 1000;
        uint16 quantity = 0;

        ask = Market.Trade(Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity);
        vm.expectRevert("Invalid quantity");
        market.place(ask);
    }

    function test_place_ask_zero_price() public prankster(JORDAN) {
        uint16 price = 0;
        uint16 quantity = 1000;

        ask = Market.Trade(Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity);
        vm.expectRevert("Invalid price");
        market.place(ask);
    }

    function test_place_multiple_asks(
        uint16 price,
        uint16 quantity1,
        uint16 quantity2
    )
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        vm.assume(quantity1 != 0);
        vm.assume(quantity2 != 0);

        // Place first ask
        ask = Market.Trade(Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity1);
        market.place(ask);

        // Place second ask at same price
        ask = Market.Trade(Market.KIND.LIMIT, Market.SIDE.ASK, price, quantity2);
        market.place(ask);

        // Verify depth is updated correctly
        (, uint256 askDepth) = market.depth(price);
        assertEq(askDepth, uint256(quantity1) + uint256(quantity2));
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
