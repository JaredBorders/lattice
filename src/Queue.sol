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
        uint256 front;
        uint256 back;
        mapping(uint256 => uint256) data;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice peeks at the front of the queue
    /// @dev element is not removed from the queue
    /// @custom:throws if the queue is empty
    /// @param queue_ from which to peek
    /// @return uint256 element at the front of the queue
    function peek(T storage queue_) external view returns (uint256) {
        require(queue_.front != queue_.back, EmptyQueue());
        return queue_.data[queue_.front];
    }

    /// @notice gets the number of elements in the queue
    /// @param queue_ from which to get the size
    /// @return uint256 value representing the number of elements in the queue
    function size(T storage queue_) external view returns (uint256) {
        return queue_.back - queue_.front;
    }

    /// @notice checks if the queue is empty
    /// @param queue_ from which to check if empty
    /// @return boolean value representing if the queue is empty
    function isEmpty(T storage queue_) external view returns (bool) {
        return queue_.front == queue_.back;
    }

    /// @notice creates a set from the elements in the queue
    /// @dev method can be expensive for large queues
    /// @param queue_ from which to create the set
    /// @return set of elements in the queue
    function toArray(T storage queue_)
        external
        view
        returns (uint256[] memory set)
    {
        uint256 start = queue_.front;
        uint256 end = queue_.back;

        set = new uint256[](end - start);

        uint256 j = 0;
        while (start < end) {
            set[j++] = queue_.data[start++];
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
    function enqueue(T storage queue_, uint256 value_) external {
        queue_.data[queue_.back] = value_;
        unchecked {
            queue_.back++;
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
    function dequeue(T storage queue_) external returns (uint256 value) {
        require(queue_.front != queue_.back, EmptyQueue());

        // record the value to return before deleting
        value = queue_.data[queue_.front];

        // free storage via deletion; refunds gas
        delete queue_.data[queue_.front];

        unchecked {
            queue_.front++;
        }
    }

}
