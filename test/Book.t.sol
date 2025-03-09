// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Book} from "../src/Book.sol";
import {ERC20 as Synth} from "../src/ERC20.sol";
import {MockSynth} from "./mocks/MockSynth.sol";
import {Test} from "@forge-std/Test.sol";

/// @title test suite for the book contract
/// @author jaredborders
/// @custom:version v0.0.1
contract Bookest is Test {

    Book book;
    MockSynth numeraire;
    MockSynth index;

    address internal constant JORDAN = address(0x01);
    address internal constant DONNIE = address(0x02);

    // set up a few price levels for testing
    uint256 price1;
    uint256 price2;

    function setUp() public {
        numeraire = new MockSynth("USD", "USD");
        index = new MockSynth("ETH", "ETH");

        book = new Book(address(numeraire), address(index));

        // Mint tokens to test accounts
        numeraire.mint(JORDAN, 1000 ether);
        numeraire.mint(DONNIE, 1000 ether);
        index.mint(JORDAN, 10 ether);
        index.mint(DONNIE, 10 ether);

        // set up price levels
        price1 = 1000 * 10 ** 18; // 1000 USD per ETH
        price2 = 1100 * 10 ** 18; // 1100 USD per ETH

        numeraire.approve(address(book), type(uint256).max);
        index.approve(address(book), type(uint256).max);
    }

    function test_place_bid() public {
        // Book.Order memory order = Book.Order({
        //     id: 0, // will be set by the place function
        //     trader: JORDAN,
        //     kind: Book.KIND.LIMIT,
        //     side: Book.SIDE.BID,
        //     price: price1,
        //     quantity: 1 ether,
        //     remaining: 1 ether
        // });

        // vm.prank(JORDAN);
        // numeraire.approve(address(clearinghouse), 1 ether);

        // // Record initial balances
        // uint256 initialUserBalance = numeraire.balanceOf(JORDAN);
        // uint256 initialBookBalance = numeraire.balanceOf(address(book));

        // vm.prank(JORDAN);
        // book.place(order);

        // // Verify the order was placed correctly
        // (uint256 bidDepth, uint256 askDepth) = book.depth(price1);
        // assertEq(bidDepth, 1 ether);
        // assertEq(askDepth, 0);

        // // Verify trader funds were transferred through the clearinghouse
        // assertEq(numeraire.balanceOf(JORDAN), initialUserBalance - 1 ether);
        // assertEq(
        //     numeraire.balanceOf(address(book)), initialBookBalance + 1 ether
        // );
    }

    function test_place_ask() public {
        // Book.Order memory order = Book.Order({
        //     id: 0, // will be set by the place function
        //     trader: JORDAN,
        //     kind: Book.KIND.LIMIT,
        //     side: Book.SIDE.ASK,
        //     price: price1,
        //     quantity: 1 ether,
        //     remaining: 1 ether
        // });

        // vm.prank(JORDAN);
        // index.approve(address(clearinghouse), 1 ether);

        // // Record initial balances
        // uint256 initialUserBalance = index.balanceOf(JORDAN);
        // uint256 initialBookBalance = index.balanceOf(address(book));

        // vm.prank(JORDAN);
        // book.place(order);

        // // Verify the order was placed correctly
        // (uint256 bidDepth, uint256 askDepth) = book.depth(price1);
        // assertEq(bidDepth, 0);
        // assertEq(askDepth, 1 ether);

        // // Verify trader funds were transferred through the clearinghouse
        // assertEq(index.balanceOf(JORDAN), initialUserBalance - 1 ether);
        // assertEq(index.balanceOf(address(book)), initialBookBalance + 1
        // ether);
    }

    function test_place_bids() public {
        vm.skip(true);
    }

    function test_place_asks() public {
        vm.skip(true);
    }

    function test_place_market_bid() public {
        vm.skip(true);
    }

    function test_place_market_ask() public {
        vm.skip(true);
    }

    function test_remove_bid() public {
        // // Record initial balances
        // uint256 initialUserBalance = numeraire.balanceOf(JORDAN);
        // uint256 initialBookBalance = numeraire.balanceOf(address(book));

        // Book.Order memory order = Book.Order({
        //     id: 0,
        //     trader: JORDAN,
        //     kind: Book.KIND.LIMIT,
        //     side: Book.SIDE.BID,
        //     price: price1,
        //     quantity: 1 ether,
        //     remaining: 1 ether
        // });

        // vm.prank(JORDAN);
        // numeraire.approve(address(clearinghouse), 1 ether);

        // vm.prank(JORDAN);
        // book.place(order);

        // (uint256 bidDepth,) = book.depth(price1);
        // assertEq(bidDepth, 1 ether);

        // // Remove the order
        // uint256 orderId = 0;
        // vm.prank(JORDAN);
        // book.remove(orderId);

        // // Verify the bid was removed from the depth
        // (bidDepth,) = book.depth(price1);
        // assertEq(bidDepth, 0);

        // // Verify funds were returned via clearinghouse
        // assertEq(numeraire.balanceOf(JORDAN), initialUserBalance);
        // assertEq(numeraire.balanceOf(address(book)), initialBookBalance);
    }

    function test_remove_ask() public {
        // // Record initial balances
        // uint256 initialUserBalance = index.balanceOf(JORDAN);
        // uint256 initialBookBalance = index.balanceOf(address(book));

        // Book.Order memory order = Book.Order({
        //     id: 0,
        //     trader: JORDAN,
        //     kind: Book.KIND.LIMIT,
        //     side: Book.SIDE.ASK,
        //     price: price1,
        //     quantity: 1 ether,
        //     remaining: 1 ether
        // });

        // vm.prank(JORDAN);
        // index.approve(address(clearinghouse), 1 ether);

        // vm.prank(JORDAN);
        // book.place(order);

        // (, uint256 askDepth) = book.depth(price1);
        // assertEq(askDepth, 1 ether);

        // // Remove the order
        // uint256 orderId = 0;
        // vm.prank(JORDAN);
        // book.remove(orderId);

        // // Verify the ask was removed from the depth
        // (, askDepth) = book.depth(price1);
        // assertEq(askDepth, 0);

        // // Verify funds were returned
        // assertEq(index.balanceOf(JORDAN), initialUserBalance);
        // assertEq(index.balanceOf(address(book)), initialBookBalance);
    }

    function test_remove_unauthorized() public {
        // Book.Order memory order = Book.Order({
        //     id: 0,
        //     trader: JORDAN,
        //     kind: Book.KIND.LIMIT,
        //     side: Book.SIDE.BID,
        //     price: price1,
        //     quantity: 1 ether,
        //     remaining: 1 ether
        // });

        // vm.prank(JORDAN);
        // numeraire.approve(address(clearinghouse), 1 ether);

        // // Place the order as JORDAN
        // vm.prank(JORDAN);
        // book.place(order);

        // // Try to remove as DONNIE
        // uint256 orderId = 0;
        // vm.prank(DONNIE);
        // vm.expectRevert();
        // book.remove(orderId);
    }

    function test_fill_bid() public {
        vm.skip(true);
    }

    function test_fill_ask() public {
        vm.skip(true);
    }

    function test_fill_bids() public {
        vm.skip(true);
    }

    function test_fill_asks() public {
        vm.skip(true);
    }

    function test_fill_bid_partial() public {
        vm.skip(true);
    }

    function test_fill_ask_partial() public {
        vm.skip(true);
    }

}
