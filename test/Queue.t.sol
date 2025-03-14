// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Queue} from "../src/Queue.sol";
import {Test} from "@forge-std/Test.sol";

/// @title test suite for the queue library
/// @author jaredborders
/// @custom:version v0.0.1
contract QueueTest is Test {

    using Queue for Queue.T;

    Queue.T queue;

    function _enqueue(uint256 size) internal {
        for (uint256 i = 1; i <= size; i++) {
            queue.enqueue(i);
        }
    }

    function test_queue_peek(uint8 x) public {
        vm.assume(x > 0);
        _enqueue(x);
        assertEq(queue.peek(), 1);
    }

    function test_queue_peek_empty() public {
        vm.expectRevert(Queue.EmptyQueue.selector);
        queue.peek();
    }

    function test_queue_size(uint8 x) public {
        _enqueue(x);
        assertEq(queue.size(), x);
    }

    function test_queue_isEmpty(uint8 x) public {
        _enqueue(x);
        bool empty = queue.isEmpty();
        x == 0 ? assertTrue(empty) : assertFalse(empty);
    }

    function test_queue_enqueue(uint8 x) public {
        vm.assume(x > 0);
        _enqueue(x);
        assertEq(queue.size(), x);
        assertEq(queue.peek(), 1);
    }

    function test_queue_dequeue(uint8 x) public {
        vm.assume(x > 0);
        _enqueue(x);
        for (uint256 i = 1; x > 0;) {
            uint256 value = queue.dequeue();
            assertEq(value, i);
            assertEq(queue.size(), x - 1);
            x--;
            i++;
        }
    }

    function test_queue_dequeue_empty(uint8 x) public {
        vm.assume(x > 0);
        _enqueue(x);
        for (; x > 0; x--) {
            queue.dequeue();
        }
        vm.expectRevert(Queue.EmptyQueue.selector);
        queue.dequeue();
    }

}
