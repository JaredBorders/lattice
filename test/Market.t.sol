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
        bid = Market.Trade(Market.KIND.LIMIT, Market.SIDE.BID, price, quantity);
        market.place(bid);
    }

}

contract AskOrderTest is MarketTest {}

contract PriceLevelTest is MarketTest {}

contract OrderSettlementTest is MarketTest {}

contract RemoveOrderTest is MarketTest {}

contract MakerFeeTest is MarketTest {}

contract TakerFeeTest is MarketTest {}
