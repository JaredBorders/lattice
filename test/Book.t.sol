// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Book} from "../src/Book.sol";
import {Test} from "@forge-std/Test.sol";

/// @title test suite for the book contract
/// @author jaredborders
/// @custom:version v0.0.1
contract Bookest is Test {

    Book book;

    function beforeAll() public {
        book = new Book();
    }

    function test_place_bid() public {
        vm.skip(true);
    }

    function test_place_ask() public {
        vm.skip(true);
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
