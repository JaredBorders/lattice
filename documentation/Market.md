# Market.sol – On-chain Limit Order Book Based Market Powering the Exchange of Tokenized Synthetic Assets

## Overview

**`Market`** is a permissionless limit-order book mechanism that facilitates trading between two ERC20 tokens:

- A **numeraire** token (e.g., sUSD).
- An **index** token (e.g., sETH).

Orders are placed with a **price** (in units of `numeraire / index`) and are managed on a single-price-level basis. Each price level is represented by a **FIFO (first-in-first-out)** queue for both **bid** and **ask** orders. When a new limit order is placed, it attempts to match immediately against available liquidity at the same price level. Any unfilled portion is added to the FIFO queue.

> **Note**: At present, **only limit orders** are fully operational. **Market orders** revert if attempted.

---

## Table of Contents

1. [Key Enumerations & Data Structures](#key-enumerations--data-structures)
2. [Constructor](#constructor)
3. [Introspection Functions](#introspection-functions)
   - [depth()](#depth)
   - [bids()](#bids)
   - [asks()](#asks)
   - [getOrder()](#getorder)
4. [Trading Functions](#trading-functions)
   - [place()](#place)
   - [remove()](#remove)
5. [Internal Matching Logic](#internal-matching-logic)
   - [\_\_placeBid()](#_placebid)
   - [\_\_placeAsk()](#_placeask)
6. [Key Notes & Behavior](#key-notes--behavior)

---

## Key Enumerations & Data Structures

### Enumerations

1. **`KIND`**

   - `MARKET`: A market order (currently not supported, reverts).
   - `LIMIT`: A limit order (supported).

2. **`SIDE`**

   - `BID`: The trader wants to acquire the **index** token in exchange for the **numeraire**.
   - `ASK`: The trader wants to sell the **index** token in exchange for the **numeraire**.

3. **`PARTICIPANT`**

   - `ANY`, `MAKER`, `TAKER`.
     > _This enum is declared but not yet used in the contract logic._

4. **`STATUS`**
   - `NULL`: Default uninitialized state.
   - `OPEN`: A limit order that is on the book but not yet fully matched.
   - `PARTIAL`: A limit order partially filled, with some quantity remaining.
   - `FILLED`: The order has been fully matched.
   - `CANCELLED`: The order was removed (canceled) before it was fully filled.

### Structs

1. **`Trade`**  
   Passed to the `place(...)` function. Fields:

   - `kind`: `MARKET` (reverts if used) or `LIMIT`.
   - `side`: `BID` or `ASK`.
   - `price`: The exchange rate denominated in `numeraire` per `index`.
   - `quantity`:
     - For a **BID**: total **numeraire** tokens posted.
     - For an **ASK**: total **index** tokens posted.

2. **`Order`**  
   Stored by ID in `orders[id]`. Contains:

   - `id`: Unique, auto-incrementing identifier.
   - `blocknumber`: The block at which the order was placed.
   - `trader`: The address that placed the order.
   - `status`: Current status (`OPEN`, `PARTIAL`, `FILLED`, `CANCELLED`).
   - `kind`: `MARKET` or `LIMIT` (currently `MARKET` is not supported).
   - `side`: `BID` or `ASK`.
   - `price`: Price level (in `numeraire` per `index`).
   - `quantity`: Original total quantity of the order.
   - `remaining`: Remaining unfilled portion of the order.

3. **`Level`**  
   Represents a single price level and holds:
   - `bidDepth`: The total unfilled **numeraire** quantity of all **BID** orders at this price.
   - `askDepth`: The total unfilled **index** token quantity of all **ASK** orders at this price.
   - `bids`: A FIFO queue of **BID** order IDs (`Queue.T`).
   - `asks`: A FIFO queue of **ASK** order IDs (`Queue.T`).

---

## Constructor

```solidity
constructor(address numeraire_, address index_) {
    numeraire = Synth(numeraire_);
    index = Synth(index_);
}
```

- Initializes two ERC20 tokens, storing their addresses in immutable fields:
  - `numeraire`: The “cash-like” token (e.g., sUSD).
  - `index`: The “underlying” token (e.g., sETH).

---

## Introspection Functions

### `depth(uint256 price_) -> (uint256 bidDepth, uint256 askDepth)`

```solidity
function depth(uint256 price_) public view returns (uint256, uint256)
```

**Purpose:**  
Returns the total outstanding book depth at a specific **price**.

- **Parameters:**  
  `price_` – The price level to look up.
- **Returns:**
  - `bidDepth`: Sum of unfilled **numeraire** in all open or partially filled bids.
  - `askDepth`: Sum of unfilled **index** in all open or partially filled asks.

### `bids(uint256 price_) -> uint256[]`

```solidity
function bids(uint256 price_) public view returns (uint256[] memory)
```

**Purpose:**  
Returns a **list of BID order IDs** queued at the specified **price**.

- **Parameters:**  
  `price_` – The price level to retrieve **BID** orders from.
- **Returns:**  
  An array of **BID** order IDs in FIFO order.

### `asks(uint256 price_) -> uint256[]`

```solidity
function asks(uint256 price_) public view returns (uint256[] memory)
```

**Purpose:**  
Returns a **list of ASK order IDs** queued at the specified **price**.

- **Parameters:**  
  `price_` – The price level to retrieve **ASK** orders from.
- **Returns:**  
  An array of **ASK** order IDs in FIFO order.

### `getOrder(uint256 id_) -> Order`

```solidity
function getOrder(uint256 id_) public view returns (Order memory)
```

**Purpose:**  
Returns the **Order** struct for a given `id_`.

- **Parameters:**  
  `id_` – The unique order identifier.
- **Returns:**  
  The **Order** corresponding to that ID (including status, remaining, etc.).

---

## Trading Functions

### `place(Trade calldata trade_)`

```solidity
function place(Trade calldata trade_) public
```

**Purpose:**  
Submits a new order to the market. For **limit** orders, it attempts to match immediately with existing opposite-side orders at the same price. The unfilled portion (if any) is added to the order book.

- **Checks:**

  1. `trade_.quantity` > 0
  2. `trade_.price` > 0

- **Behavior:**
  - **Limit Bids** call [`__placeBid(trade_)`](#_placebid).
  - **Limit Asks** call [`__placeAsk(trade_)`](#_placeask).
  - **Market Orders** revert with `"Unsupported"`.

### `remove(uint256 id_)`

```solidity
function remove(uint256 id_) public
```

**Purpose:**  
Allows an order’s **owner** to cancel it if it has not been fully filled or already canceled. Any unfilled quantity is returned to the owner.

- **Checks:**

  1. `msg.sender` must be the owner of `id_`.
  2. The order must not be `FILLED` or `CANCELLED`.
  3. The order must not be of kind `MARKET` (currently not relevant, as market orders revert on placement).

- **Actions:**
  1. Sets the order’s `status` to `CANCELLED`.
  2. Fetches the `remaining` quantity.
  3. Subtracts that `remaining` from either `level.bidDepth` or `level.askDepth`.
  4. Sets `order.remaining = 0`.
  5. Transfers the unfilled token balance back to the caller.

> **Note**: Although the order is canceled, it remains in the FIFO queue. Later, when the queue front is processed, a canceled order is skipped and dequeued.

---

## Internal Matching Logic

### `__placeBid(Trade calldata trade_) -> uint256`

```solidity
function __placeBid(Trade calldata trade_) private returns (uint256 id)
```

1. **Token Transfer**

   - Immediately pulls `trade_.quantity` **numeraire** tokens from `msg.sender` to the contract.

2. **Initialize the Order**

   - Creates a new `Order memory bid` with:
     - `id = cid++`
     - `status = OPEN`
     - `remaining = trade_.quantity`
     - `price = trade_.price`
     - `side = BID`
     - `trader = msg.sender`
     - (other metadata as well)

3. **Matching**

   - Let `p = bid.price` and `n = bid.quantity`.
   - Convert `n` to the maximum **index** tokens the bidder can buy at this price: `i = n / p`.
   - While the queue at `level.asks` is not empty:
     1. Peek the next ask (`askId`).
     2. If that ask is `CANCELLED`, dequeue and continue.
     3. Compare `i` to the ask’s `remaining`.
     4. Fill fully or partially depending on whichever side is smaller:
        - Transfer **numeraire** to the ask’s trader and **index** to the bidder.
        - Update both orders’ `remaining` and statuses (`PARTIAL` or `FILLED`).
     5. If the bid is fully filled, break out of the loop; else continue matching.

4. **Enqueue Remainder**
   - If the bid is not fully filled (`status != FILLED`), enqueue it into `level.bids`.
   - Increase `level.bidDepth` by any leftover `bid.remaining`.

### `__placeAsk(Trade calldata trade_) -> uint256`

```solidity
function __placeAsk(Trade calldata trade_) private returns (uint256 id)
```

1. **Token Transfer**

   - Immediately pulls `trade_.quantity` **index** tokens from `msg.sender` to the contract.

2. **Initialize the Order**

   - Creates a new `Order memory ask` with:
     - `id = cid++`
     - `status = OPEN`
     - `remaining = trade_.quantity`
     - `price = trade_.price`
     - `side = ASK`
     - `trader = msg.sender`
     - (other metadata as well)

3. **Matching**

   - Let `p = ask.price` and `i = ask.quantity`.
   - Convert `i` to the total **numeraire** the asker wants: `n = p * i`.
   - While the queue at `level.bids` is not empty:
     1. Peek the next bid (`bidId`).
     2. If that bid is `CANCELLED`, dequeue and continue.
     3. Compare `n` to the bid’s `remaining`.
     4. Fill fully or partially depending on whichever side is smaller:
        - Transfer **index** to the bid’s trader and **numeraire** to the asker.
        - Update both orders’ `remaining` and statuses (`PARTIAL` or `FILLED`).
     5. If the ask is fully filled, break; else continue matching.

4. **Enqueue Remainder**
   - If the ask is not fully filled, enqueue it into `level.asks`.
   - Increase `level.askDepth` by any leftover `ask.remaining`.

---

## Key Notes & Behavior

1. **Immediate Token Lock**

   - For **bids**: `numeraire` is transferred in full to the contract before matching begins.
   - For **asks**: `index` is transferred in full to the contract before matching begins.

2. **Partial Fills**

   - If an order only partially matches, the leftover portion remains on the book.
   - `status` becomes `PARTIAL`, and `remaining` tokens stay locked.

3. **Cancellation**

   - Users can remove an `OPEN` or `PARTIAL` limit order.
   - Any remaining tokens are returned immediately.
   - The order’s queue entry is eventually dequeued when encountered during subsequent matching.

4. **Single-Price-Level Matching**

   - A newly placed order only attempts to match at the **exact** price it specifies (i.e., no crossing multiple price levels).
   - Orders at other prices do not come into play.

5. **Unsupported Market Orders**

   - Any attempt to place a `KIND.MARKET` order reverts with `"Unsupported"`.

6. **FIFO Queues**

   - Each **price** has two FIFO queues: `bids` and `asks`.
   - Matching proceeds in strict time order: older orders get matched first.

7. **Gas Costs**

   - The data structures and partial fill logic are designed for repeated usage while aiming to keep a stable gas overhead.
   - Canceled orders remain in queue storage until they surface at the front, where they are skipped and dequeued.

8. **Expansion Hooks**
   - The enumerations `PARTICIPANT` and the `Hook` library exist to allow expansions—e.g., off-chain triggers, fee logic, or advanced matching. These are currently not fully integrated but serve as extension points for future features.

---

**Disclaimer**  
This code is a simplified example of a single-price-level order book. It does not manage cross-price matching or advanced time-in-force orders. Use at your own risk and adapt carefully for production environments.
