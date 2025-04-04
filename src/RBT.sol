// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title Red-Black Tree Library for Order Book Implementation
/// @dev Optimized for tracking price levels in an order book
/// @author flocast (modified from BokkyPooBah's Red-Black Tree Library)
library RBT {

    /*//////////////////////////////////////////////////////////////
                              TYPE STRUCTURES
    //////////////////////////////////////////////////////////////*/

    /// @notice represents a node within the Red-Black Tree
    /// @custom:parent key of the parent node
    /// @custom:left key of the left child
    /// @custom:right key of the right child
    /// @custom:red true if the node is red, false if black
    struct Node {
        uint128 parent;
        uint128 left;
        uint128 right;
        bool red;
    }

    /// @notice represents the Red-Black Tree
    /// @custom:root key of the root node
    /// @custom:nodes mapping of keys to nodes
    struct Tree {
        uint128 root; // Root node key
        mapping(uint128 => Node) nodes; // Maps price levels to nodes
    }

    /*//////////////////////////////////////////////////////////////
                                 CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice sentinel value for an empty node
    uint128 private constant EMPTY = 0;

    /*//////////////////////////////////////////////////////////////
                                   VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice find the minimum key in the tree (lowest price for asks)
    /// @param self the tree to search
    /// @return _key the minimum key in the tree, or EMPTY if tree is empty
    function first(Tree storage self) internal view returns (uint128 _key) {
        _key = self.root;
        if (_key != EMPTY) {
            _key = treeMinimum(self, self.root);
        }
    }

    /// @notice find the maximum key in the tree (highest price for bids)
    /// @param self the tree to search
    /// @return _key the maximum key in the tree, or EMPTY if tree is empty
    function last(Tree storage self) internal view returns (uint128 _key) {
        _key = self.root;
        if (_key != EMPTY) {
            _key = treeMaximum(self, self.root);
        }
    }

    /// @notice find the next key in order (next higher price)
    /// @param self the tree to search
    /// @param key the current key
    /// @return cursor the next key in order, or EMPTY if no next key exists
    function next(
        Tree storage self,
        uint128 key
    )
        internal
        view
        returns (uint128 cursor)
    {
        require(key != EMPTY, "RBT: key is empty");

        if (self.nodes[key].right != EMPTY) {
            cursor = treeMinimum(self, self.nodes[key].right);
        } else {
            cursor = self.nodes[key].parent;
            while (cursor != EMPTY && key == self.nodes[cursor].right) {
                key = cursor;
                cursor = self.nodes[cursor].parent;
            }
        }
    }

    /// @notice find the previous key in order (next lower price)
    /// @param self the tree to search
    /// @param key the current key
    /// @return cursor the previous key in order, or EMPTY if no previous key
    /// exists
    function prev(
        Tree storage self,
        uint128 key
    )
        internal
        view
        returns (uint128 cursor)
    {
        require(key != EMPTY, "RBT: key is empty");

        if (self.nodes[key].left != EMPTY) {
            cursor = treeMaximum(self, self.nodes[key].left);
        } else {
            cursor = self.nodes[key].parent;
            while (cursor != EMPTY && key == self.nodes[cursor].left) {
                key = cursor;
                cursor = self.nodes[cursor].parent;
            }
        }
    }

    /// @notice check if a key exists in the tree
    /// @param self the tree to search
    /// @param key the key to check
    /// @return true if the key exists, false otherwise
    function exists(
        Tree storage self,
        uint128 key
    )
        internal
        view
        returns (bool)
    {
        return (key != EMPTY)
            && ((key == self.root) || (self.nodes[key].parent != EMPTY));
    }

    /// @notice check if a key is empty
    /// @param key the key to check
    /// @return true if the key is empty, false otherwise
    function isEmpty(uint128 key) internal pure returns (bool) {
        return key == EMPTY;
    }

    /// @notice get the empty value
    /// @return EMPTY value
    function getEmpty() internal pure returns (uint128) {
        return EMPTY;
    }

    /*//////////////////////////////////////////////////////////////
                                OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice insert a key into the tree
    /// @param self the tree to insert into
    /// @param key the key to insert
    function insert(Tree storage self, uint128 key) internal {
        require(key != EMPTY, "RBT: cannot insert empty key");
        require(!exists(self, key), "RBT: key already exists");

        uint128 cursor = EMPTY;
        uint128 probe = self.root;

        self.nodes[key] =
            Node({parent: EMPTY, left: EMPTY, right: EMPTY, red: true});

        while (probe != EMPTY) {
            cursor = probe;
            if (key < probe) {
                probe = self.nodes[probe].left;
            } else {
                probe = self.nodes[probe].right;
            }
        }

        self.nodes[key].parent = cursor;
        if (cursor == EMPTY) {
            self.root = key;
        } else if (key < cursor) {
            self.nodes[cursor].left = key;
        } else {
            self.nodes[cursor].right = key;
        }

        insertFixup(self, key);
    }

    /// @notice remove a key from the tree
    /// @param self the tree to remove from
    /// @param key the key to remove
    function remove(Tree storage self, uint128 key) internal {
        require(key != EMPTY, "RBT: cannot remove empty key");
        require(exists(self, key), "RBT: key does not exist");

        uint128 probe;
        uint128 cursor;
        bool doFixup;

        if (self.nodes[key].left == EMPTY || self.nodes[key].right == EMPTY) {
            cursor = key;
        } else {
            cursor = self.nodes[key].right;
            while (self.nodes[cursor].left != EMPTY) {
                cursor = self.nodes[cursor].left;
            }
        }

        if (self.nodes[cursor].left != EMPTY) {
            probe = self.nodes[cursor].left;
        } else {
            probe = self.nodes[cursor].right;
        }

        uint128 yParent = self.nodes[cursor].parent;
        self.nodes[probe].parent = yParent;

        if (yParent != EMPTY) {
            if (cursor == self.nodes[yParent].left) {
                self.nodes[yParent].left = probe;
            } else {
                self.nodes[yParent].right = probe;
            }
        } else {
            self.root = probe;
        }

        doFixup = !self.nodes[cursor].red;

        if (cursor != key) {
            replaceParent(self, cursor, key);
            self.nodes[cursor].left = self.nodes[key].left;
            self.nodes[self.nodes[cursor].left].parent = cursor;
            self.nodes[cursor].right = self.nodes[key].right;
            self.nodes[self.nodes[cursor].right].parent = cursor;
            self.nodes[cursor].red = self.nodes[key].red;
            (cursor, key) = (key, cursor);
        }

        if (doFixup) {
            removeFixup(self, probe);
        }

        if (probe == EMPTY) {
            self.nodes[probe].parent = EMPTY;
        }
    }

    /// @notice get an array of keys in ascending order
    /// @param self the tree to traverse
    /// @return array of keys in ascending order
    function toArray(Tree storage self)
        internal
        view
        returns (uint128[] memory)
    {
        uint256 count = 0;
        uint128 current = first(self);

        while (current != EMPTY) {
            count++;
            current = next(self, current);
        }

        uint128[] memory result = new uint128[](count);
        current = first(self);

        for (uint256 i = 0; i < count; i++) {
            result[i] = current;
            current = next(self, current);
        }

        return result;
    }

    /*//////////////////////////////////////////////////////////////
                             PRIVATE HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice find the minimum key in a subtree
    /// @param self the tree to search
    /// @param key the root of the subtree
    /// @return the minimum key in the subtree
    function treeMinimum(
        Tree storage self,
        uint128 key
    )
        private
        view
        returns (uint128)
    {
        while (self.nodes[key].left != EMPTY) {
            key = self.nodes[key].left;
        }
        return key;
    }

    /// @notice find the maximum key in a subtree
    /// @param self the tree to search
    /// @param key the root of the subtree
    /// @return the maximum key in the subtree
    function treeMaximum(
        Tree storage self,
        uint128 key
    )
        private
        view
        returns (uint128)
    {
        while (self.nodes[key].right != EMPTY) {
            key = self.nodes[key].right;
        }
        return key;
    }

    /// @notice fix tree after insertion
    /// @param self the tree to fix
    /// @param key the key that was inserted
    function insertFixup(Tree storage self, uint128 key) private {
        uint128 cursor;

        while (key != self.root && self.nodes[self.nodes[key].parent].red) {
            uint128 keyParent = self.nodes[key].parent;

            if (keyParent == self.nodes[self.nodes[keyParent].parent].left) {
                cursor = self.nodes[self.nodes[keyParent].parent].right;

                if (self.nodes[cursor].red) {
                    self.nodes[keyParent].red = false;
                    self.nodes[cursor].red = false;
                    self.nodes[self.nodes[keyParent].parent].red = true;
                    key = self.nodes[keyParent].parent;
                } else {
                    if (key == self.nodes[keyParent].right) {
                        key = keyParent;
                        rotateLeft(self, key);
                    }

                    keyParent = self.nodes[key].parent;
                    self.nodes[keyParent].red = false;
                    self.nodes[self.nodes[keyParent].parent].red = true;
                    rotateRight(self, self.nodes[keyParent].parent);
                }
            } else {
                cursor = self.nodes[self.nodes[keyParent].parent].left;

                if (self.nodes[cursor].red) {
                    self.nodes[keyParent].red = false;
                    self.nodes[cursor].red = false;
                    self.nodes[self.nodes[keyParent].parent].red = true;
                    key = self.nodes[keyParent].parent;
                } else {
                    if (key == self.nodes[keyParent].left) {
                        key = keyParent;
                        rotateRight(self, key);
                    }

                    keyParent = self.nodes[key].parent;
                    self.nodes[keyParent].red = false;
                    self.nodes[self.nodes[keyParent].parent].red = true;
                    rotateLeft(self, self.nodes[keyParent].parent);
                }
            }
        }

        self.nodes[self.root].red = false;
    }

    /// @notice replace parent links
    /// @param self the tree to modify
    /// @param a node to replace with
    /// @param b node to replace
    function replaceParent(Tree storage self, uint128 a, uint128 b) private {
        uint128 bParent = self.nodes[b].parent;
        self.nodes[a].parent = bParent;

        if (bParent == EMPTY) {
            self.root = a;
        } else {
            if (b == self.nodes[bParent].left) {
                self.nodes[bParent].left = a;
            } else {
                self.nodes[bParent].right = a;
            }
        }
    }

    /// @notice fix tree after removal
    /// @param self the tree to fix
    /// @param key the key around which to fix
    function removeFixup(Tree storage self, uint128 key) private {
        uint128 cursor;

        while (key != self.root && !self.nodes[key].red) {
            uint128 keyParent = self.nodes[key].parent;

            if (key == self.nodes[keyParent].left) {
                cursor = self.nodes[keyParent].right;

                if (self.nodes[cursor].red) {
                    self.nodes[cursor].red = false;
                    self.nodes[keyParent].red = true;
                    rotateLeft(self, keyParent);
                    cursor = self.nodes[keyParent].right;
                }

                if (
                    !self.nodes[self.nodes[cursor].left].red
                        && !self.nodes[self.nodes[cursor].right].red
                ) {
                    self.nodes[cursor].red = true;
                    key = keyParent;
                } else {
                    if (!self.nodes[self.nodes[cursor].right].red) {
                        self.nodes[self.nodes[cursor].left].red = false;
                        self.nodes[cursor].red = true;
                        rotateRight(self, cursor);
                        cursor = self.nodes[keyParent].right;
                    }

                    self.nodes[cursor].red = self.nodes[keyParent].red;
                    self.nodes[keyParent].red = false;
                    self.nodes[self.nodes[cursor].right].red = false;
                    rotateLeft(self, keyParent);
                    key = self.root;
                }
            } else {
                cursor = self.nodes[keyParent].left;

                if (self.nodes[cursor].red) {
                    self.nodes[cursor].red = false;
                    self.nodes[keyParent].red = true;
                    rotateRight(self, keyParent);
                    cursor = self.nodes[keyParent].left;
                }

                if (
                    !self.nodes[self.nodes[cursor].right].red
                        && !self.nodes[self.nodes[cursor].left].red
                ) {
                    self.nodes[cursor].red = true;
                    key = keyParent;
                } else {
                    if (!self.nodes[self.nodes[cursor].left].red) {
                        self.nodes[self.nodes[cursor].right].red = false;
                        self.nodes[cursor].red = true;
                        rotateLeft(self, cursor);
                        cursor = self.nodes[keyParent].left;
                    }

                    self.nodes[cursor].red = self.nodes[keyParent].red;
                    self.nodes[keyParent].red = false;
                    self.nodes[self.nodes[cursor].left].red = false;
                    rotateRight(self, keyParent);
                    key = self.root;
                }
            }
        }

        self.nodes[key].red = false;
    }

    /// @notice rotate left around a node
    /// @param self the tree to rotate
    /// @param key the node to rotate around
    function rotateLeft(Tree storage self, uint128 key) private {
        uint128 cursor = self.nodes[key].right;
        uint128 keyParent = self.nodes[key].parent;
        uint128 cursorLeft = self.nodes[cursor].left;

        self.nodes[key].right = cursorLeft;

        if (cursorLeft != EMPTY) {
            self.nodes[cursorLeft].parent = key;
        }

        self.nodes[cursor].parent = keyParent;

        if (keyParent == EMPTY) {
            self.root = cursor;
        } else if (key == self.nodes[keyParent].left) {
            self.nodes[keyParent].left = cursor;
        } else {
            self.nodes[keyParent].right = cursor;
        }

        self.nodes[cursor].left = key;
        self.nodes[key].parent = cursor;
    }

    /// @notice rotate right around a node
    /// @param self the tree to rotate
    /// @param key the node to rotate around
    function rotateRight(Tree storage self, uint128 key) private {
        uint128 cursor = self.nodes[key].left;
        uint128 keyParent = self.nodes[key].parent;
        uint128 cursorRight = self.nodes[cursor].right;

        self.nodes[key].left = cursorRight;

        if (cursorRight != EMPTY) {
            self.nodes[cursorRight].parent = key;
        }

        self.nodes[cursor].parent = keyParent;

        if (keyParent == EMPTY) {
            self.root = cursor;
        } else if (key == self.nodes[keyParent].right) {
            self.nodes[keyParent].right = cursor;
        } else {
            self.nodes[keyParent].left = cursor;
        }

        self.nodes[cursor].right = key;
        self.nodes[key].parent = cursor;
    }

}
