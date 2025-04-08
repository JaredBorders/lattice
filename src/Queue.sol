// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title minimal FIFO (first-in-first-out) queue implementation
/// @dev utilizes a mapping-based circular queue
/// @author jaredborders
/// @custom:version v0.0.1
library Queue {

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when attempting certain operations on an empty queue
    /// @custom:peek attempt made to peek at an empty queue
    /// @custom:dequeue attempt made to dequeue from an empty queue
    error EmptyQueue();

    /*//////////////////////////////////////////////////////////////
                             TYPE STRUCTURE
    //////////////////////////////////////////////////////////////*/

    /// @custom:front index that maps to the first element in the queue
    /// @custom:back index that maps to the last element in the queue
    /// @custom:q mapping of index to elements in the queue
    struct T {
        uint64 front;
        uint64 back;
        mapping(uint64 => Node) nodes;
    }

    /// @custom:prev id of the previous node in the queue
    /// @custom:next id of the next node in the queue
    struct Node {
        uint64 prev;
        uint64 next;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice peeks at the front of the queue
    /// @dev element is not removed from the queue
    /// @custom:throws if the queue is empty
    /// @param queue_ from which to peek
    /// @return uint256 element at the front of the queue
    function peek(T storage queue_) external view returns (uint64) {
        if (queue_.front == 0) revert EmptyQueue();
        return queue_.front;
    }

    /// @notice gets the number of elements in the queue
    /// @param queue_ from which to get the size
    /// @return uint256 value representing the number of elements in the queue
    function size(T storage queue_) external view returns (uint256) {
        uint64 current = queue_.front;
        uint256 count;

        while (current != 0) {
            count++;
            current = queue_.nodes[current].next;
        }

        return count;
    }

    /// @notice checks if the queue is empty
    /// @param queue_ from which to check if empty
    /// @return boolean value representing if the queue is empty
    function isEmpty(T storage queue_) external view returns (bool) {
        return queue_.front == 0;
    }

    /// @notice creates a set from the elements in the queue
    /// @dev method can be expensive for large queues
    /// @param queue_ from which to create the set
    /// @return set of elements in the queue
    function toArray(T storage queue_)
        external
        view
        returns (uint64[] memory set)
    {
        uint64 current = queue_.front;
        uint256 count;

        while (current != 0) {
            count++;
            current = queue_.nodes[current].next;
        }

        set = new uint64[](count);
        current = queue_.front;

        for (uint256 i = 0; i < count; i++) {
            set[i] = current;
            current = queue_.nodes[current].next;
        }
    }

    /*//////////////////////////////////////////////////////////////
                               OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @custom:example illustration of enqueuing elements
    ///
    /// front: (F)
    /// back:  (B)
    ///
    ///  (F)                        (F)                        (F)
    ///   |                          |                          |
    ///   v                          v                          v
    ///  {_, _, _} -> enqueue(7) -> {7, _, _} -> enqueue(3) -> {7, 3, _}
    ///   ^                             ^                             ^
    ///   |                             |                             |
    ///  (B)                           (B)                           (B)
    ///
    /// @custom:end

    /// @notice adds an item to the queue
    /// @dev increments the back index, appending an element to the queue
    /// @custom:complexity O(1) time complexity
    /// @param queue_ to which to add the value
    /// @param value_ to be added to the queue
    function enqueue(T storage queue_, uint64 value_) external {
        if (queue_.back == 0) {
            queue_.front = value_;
            queue_.back = value_;
        } else {
            Node storage prev = queue_.nodes[queue_.back];
            prev.next = value_;

            Node storage node = queue_.nodes[value_];
            node.prev = queue_.back;

            queue_.back = value_;
        }
    }

    /// @custom:example illustration of dequeuing elements
    ///
    /// front: (F)
    /// back:  (B)
    ///
    ///        (B)                       (B)                       (B)
    ///         |                         |                         |
    ///         v                         v                         v
    ///  {7, 3, _} -> dequeue() -> {_, 3, _} -> dequeue() -> {_, _, _}
    ///   ^                            ^                            ^
    ///   |                            |                            |
    ///  (F)                          (F)                          (F)
    ///
    /// @custom:end

    /// @notice removes and returns the front item from the queue
    /// @dev increments the front index, removing an element from the queue
    /// @custom:throws if the queue is empty
    /// @param queue_ from which to dequeue
    /// @return value The dequeued value
    function dequeue(T storage queue_) external returns (uint64 value) {
        value = queue_.front;
        if (value == 0) revert EmptyQueue();

        Node storage node = queue_.nodes[value];
        uint64 next = node.next;

        if (next == 0) {
            queue_.front = 0;
            queue_.back = 0;
        } else {
            queue_.nodes[next].prev = 0;
            queue_.front = next;
        }

        delete queue_.nodes[value];
    }

    /// @notice removes an arbitrary value from the queue
    /// @param queue_ from which to remove
    /// @param value_ the id of the element to remove
    function remove(T storage queue_, uint64 value_) external {
        Node storage node = queue_.nodes[value_];
        uint64 prev = node.prev;
        uint64 next = node.next;

        if (queue_.front == value_) {
            queue_.front = next;
        }

        if (queue_.back == value_) {
            queue_.back = prev;
        }

        if (prev != 0) {
            queue_.nodes[prev].next = next;
        }

        if (next != 0) {
            queue_.nodes[next].prev = prev;
        }

        delete queue_.nodes[value_];
    }

}
