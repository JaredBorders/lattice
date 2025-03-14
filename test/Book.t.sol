// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Book} from "../src/Book.sol";
import {ERC20 as Synth} from "../src/ERC20.sol";
import {MockSynth} from "./mocks/MockSynth.sol";
import {Test} from "@forge-std/Test.sol";

/// @title test suite for the book contract
/// @author flocast
/// @author jaredborders
/// @custom:version v0.0.1
contract BookTest is Test {

    Book book;

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

        book = new Book(address(numeraire), address(index));

        numeraire.mint(JORDAN, type(uint32).max);
        numeraire.mint(DONNIE, type(uint32).max);
        index.mint(JORDAN, type(uint32).max);
        index.mint(DONNIE, type(uint32).max);

        vm.startPrank(JORDAN);
        numeraire.approve(address(book), type(uint256).max);
        index.approve(address(book), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(DONNIE);
        numeraire.approve(address(book), type(uint256).max);
        index.approve(address(book), type(uint256).max);
        vm.stopPrank();
    }

}

contract BidOrderTest is BookTest {

    function test_place_bid(
        uint16 price,
        uint16 quantity
    )
        public
        prankster(JORDAN)
    {
        vm.assume(price != 0);
        vm.assume(quantity != 0);
        Book.Trade memory bid =
            Book.Trade(Book.KIND.LIMIT, Book.SIDE.BID, price, quantity);
        book.place(bid);
    }

}

contract AskOrderTest is BookTest {}

contract PriceLevelTest is BookTest {}

contract OrderSettlementTest is BookTest {}

contract RemoveOrderTest is BookTest {}

contract MakerFeeTest is BookTest {}

contract TakerFeeTest is BookTest {}
