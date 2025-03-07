// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title fungible token implementation
/// @custom:account refers to an externally-owned account
/// @author openzeppelin
/// @author jaredborders
/// @custom:version v0.0.1
abstract contract ERC20 {

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @custom:contract ERC20.sol
    /// @notice thrown when attempting to reduce allowance below zero
    /// @param owner address who granted the allowance
    /// @param spender address who was granted the allowance
    /// @param current allowance spender has been granted
    /// @param amount to reduce the allowance by
    error ERC20AllowanceUnderflow(
        address owner, address spender, uint256 current, uint256 amount
    );

    /// @custom:contract ERC20.sol
    /// @notice thrown when attempt to transfer exceeds balance
    /// @param from address who is attempting to transfer
    /// @param balance amount of tokens owned by the sender
    /// @param amount to transfer
    error ERC20TransferExceedsBalance(
        address from, uint256 balance, uint256 amount
    );

    /// @custom:contract ERC20.sol
    /// @notice thrown when attempting to burn more tokens than balance
    /// @param account address whose tokens are being burned
    /// @param balance amount of tokens owned by the account
    /// @param amount to burn
    error ERC20BurnExceedsBalance(
        address account, uint256 balance, uint256 amount
    );

    /// @custom:contract ERC20.sol
    /// @notice thrown when attempting to spend more than allowance granted
    /// @param owner address who granted the allowance
    /// @param spender address who was granted the allowance
    /// @param current allowance spender has been granted
    /// @param amount to spend
    error ERC20AllowanceExceeded(
        address owner, address spender, uint256 current, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted when tokens are transferred from one account to another
    /// @param from designates the account tokens are transferred from
    /// @param to designates the account tokens are transferred to
    /// @param value the number of tokens transferred
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice emitted when an account grants another account an allowance
    /// @dev allowance is the amount of tokens some spender is allowed to spend
    /// @param owner who has granted the allowance
    /// @param spender who has been granted the allowance
    /// @param value or amount of tokens the spender is allowed to spend
    event Approval(
        address indexed owner, address indexed spender, uint256 value
    );

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice record of account balances
    mapping(address account => uint256 balance) public balances;

    /// @notice record of allowances granted by account owners to spenders
    mapping(address account => mapping(address spender => uint256 allowance))
        public allowances;

    /// @notice query the total circulating supply of the token
    /// @return uint256 total supply of the token
    uint256 public totalSupply;

    /// @notice query the name of the token
    /// @return string name of the token
    string public name;

    /// @notice query the symbol of the token
    /// @return string symbol of the token
    string public symbol;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice construct a new ERC20 token
    /// @dev name and symbol will not change after construction
    /// @param name_ name of the token
    /// @param symbol_ symbol of the token
    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    /*//////////////////////////////////////////////////////////////
                             INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    /// @notice query the number of decimals used by the token
    /// @dev usually a value of 18; imitates ether-wei relationship
    /// @custom:caution although uncommon, decimals may not be 18
    /// @dev if decimals is 2, a balance of 404 should be read as 4.04
    /// @return uint8 number of decimals used by the token
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /// @notice query token balance of an account
    /// @param account_ address of the account to query
    /// @return uint256 balance of tokens held by the account
    function balanceOf(address account_)
        public
        view
        virtual
        returns (uint256)
    {
        return balances[account_];
    }

    /// @notice query the allowance some owner has granted to a spender
    /// @param owner_ address of the account who has granted the allowance
    /// @param spender_ address of the account granted the allowance
    /// @return uint256 amount of tokens the spender is allowed to spend
    function allowance(
        address owner_,
        address spender_
    )
        public
        view
        virtual
        returns (uint256)
    {
        return allowances[owner_][spender_];
    }

    /*//////////////////////////////////////////////////////////////
                          TRANSFER OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice transfer tokens from the caller to a recipient
    /// @param to_ address of the account to receive the tokens
    /// @param amount_ of tokens to transfer
    /// @return boolean indicating success of the transfer
    function transfer(
        address to_,
        uint256 amount_
    )
        public
        virtual
        returns (bool)
    {
        _transfer(msg.sender, to_, amount_);

        return true;
    }

    /// @notice transfer tokens from an account to another account
    /// @dev allowance must be sufficient to transfer; unless sender is owner
    /// @param from_ address of the account to transfer tokens from
    /// @param to_ address of the account to transfer tokens to
    /// @param amount_ of tokens to transfer
    /// @return boolean indicating success of the transfer
    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    )
        public
        virtual
        returns (bool)
    {
        _spendAllowance(from_, msg.sender, amount_);

        _transfer(from_, to_, amount_);

        return true;
    }

    /// @notice transfer tokens from an account to another account
    /// @dev allowance not checked
    /// @param from_ address of the account to transfer tokens from
    /// @param to_ address of the account to transfer tokens to
    /// @param amount_ of tokens to transfer
    function _transfer(
        address from_,
        address to_,
        uint256 amount_
    )
        internal
        virtual
    {
        _beforeTokenTransfer(from_, to_, amount_);

        uint256 fromBalance = balances[from_];

        if (fromBalance < amount_) {
            revert ERC20TransferExceedsBalance(from_, fromBalance, amount_);
        }

        unchecked {
            balances[from_] = fromBalance - amount_;
            balances[to_] += amount_;
        }

        emit Transfer(from_, to_, amount_);

        _afterTokenTransfer(from_, to_, amount_);
    }

    /*//////////////////////////////////////////////////////////////
                          ALLOWANCE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice caller grants an allowance for some spender
    /// @param spender_ address of the account granted the allowance
    /// @param amount_ of tokens the spender is allowed to spend
    /// @dev allowance becomes persistently infinite if set to type(uint256).max
    /// @return boolean indicating success of the approval
    function approve(
        address spender_,
        uint256 amount_
    )
        public
        virtual
        returns (bool)
    {
        _approve(msg.sender, spender_, amount_);

        return true;
    }

    /// @notice caller increases the allowance for some spender
    /// @param spender_ address of the account granted the allowance
    /// @param amount_ of tokens added to the spender's allowance
    /// @dev allowance becomes persistently infinite if set to type(uint256).max
    /// @return boolean indicating success of the increase
    function increaseAllowance(
        address spender_,
        uint256 amount_
    )
        public
        virtual
        returns (bool)
    {
        _approve(
            msg.sender, spender_, allowance(msg.sender, spender_) + amount_
        );

        return true;
    }

    /// @notice caller decreases the allowance for some spender
    /// @param spender_ address of the account granted the allowance
    /// @param amount_ of tokens subtracted from the spender's allowance
    /// @return boolean indicating success of the decrease
    function decreaseAllowance(
        address spender_,
        uint256 amount_
    )
        public
        virtual
        returns (bool)
    {
        // define the current allowance
        uint256 current = allowance(msg.sender, spender_);

        if (current < amount_) {
            revert ERC20AllowanceUnderflow(
                msg.sender, spender_, current, amount_
            );
        }

        unchecked {
            _approve(msg.sender, spender_, current - amount_);
        }

        return true;
    }

    /// @notice caller grants an allowance for some spender
    /// @param owner_ address of the account who has granted the allowance
    /// @param spender_ address of the account granted the allowance
    /// @param amount_ of tokens the spender is allowed to spend
    /// @dev allowance becomes persistently infinite if set to type(uint256).max
    function _approve(
        address owner_,
        address spender_,
        uint256 amount_
    )
        internal
        virtual
    {
        allowances[owner_][spender_] = amount_;

        emit Approval(owner_, spender_, amount_);
    }

    /// @notice caller decreases the allowance for some spender
    /// @dev allowance not decremented if set to type(uint256).max
    /// @param owner_ address of the account who has granted the allowance
    /// @param spender_ address of the account granted the allowance
    /// @param amount_ of tokens subtracted from the spender's allowance
    function _spendAllowance(
        address owner_,
        address spender_,
        uint256 amount_
    )
        internal
        virtual
    {
        uint256 current = allowance(owner_, spender_);

        if (current != type(uint256).max) {
            if (current < amount_) {
                revert ERC20AllowanceExceeded(
                    owner_, spender_, current, amount_
                );
            }

            unchecked {
                _approve(owner_, spender_, current - amount_);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        MINT AND BURN OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice mint tokens and assign them to an account
    /// @param account_ address of the account to mint tokens for
    /// @param amount_ of tokens to mint
    function _mint(address account_, uint256 amount_) internal virtual {
        _beforeTokenTransfer(address(0), account_, amount_);

        totalSupply += amount_;

        unchecked {
            balances[account_] += amount_;
        }

        emit Transfer(address(0), account_, amount_);

        _afterTokenTransfer(address(0), account_, amount_);
    }

    /// @notice burn tokens from an account
    /// @param account_ address of the account to burn tokens from
    /// @param amount_ of tokens to burn
    function _burn(address account_, uint256 amount_) internal virtual {
        _beforeTokenTransfer(account_, address(0), amount_);

        uint256 accountBalance = balances[account_];

        if (accountBalance < amount_) {
            revert ERC20BurnExceedsBalance(account_, accountBalance, amount_);
        }

        unchecked {
            balances[account_] = accountBalance - amount_;
            totalSupply -= amount_;
        }

        emit Transfer(account_, address(0), amount_);

        _afterTokenTransfer(account_, address(0), amount_);
    }

    /*//////////////////////////////////////////////////////////////
                                 HOOKS
    //////////////////////////////////////////////////////////////*/

    /// @notice hook that is called before any token transfer
    /// @dev called before minting and burning tokens
    /// @param from_ address that tokens will be transferred from
    /// @param to_ address that tokens will be transferred to
    /// @param amount_ of tokens that will be transferred
    function _beforeTokenTransfer(
        address from_,
        address to_,
        uint256 amount_
    )
        internal
        virtual
    {}

    /// @notice hook that is called after any token transfer
    /// @dev called after minting and burning tokens
    /// @param from_ address that tokens were transferred from
    /// @param to_ address that tokens were transferred to
    /// @param amount_ of tokens that were transferred
    function _afterTokenTransfer(
        address from_,
        address to_,
        uint256 amount_
    )
        internal
        virtual
    {}

}
