# Book.sol – Minimal Limit-Order Book

## Overview

**`Book`** is a minimal implementation of a limit-order book for two tokens:

- A **numeraire** token (e.g., sUSD).
- An **index** token (e.g., sETH).

The contract allows users to place **limit orders** (and potentially market orders, though it’s currently marked as unsupported) for **bid** (buy index with numeraire) or **ask** (sell index for numeraire). Each order is stored on-chain along with a price level and inserted into a first-in-first-out (FIFO) queue for matching.

---

## Table of Contents

1. [Key Data Structures](#key-data-structures)
2. [Constructor](#constructor)
3. [Public Functions](#public-functions)
   - [\`depth\`](#depth)
   - [\`place\`](#place)
   - [\`remove\`](#remove)
4. [Internal Matching Functions](#internal-matching-functions)
   - [\`\_\_placeBid\`](#__placebid)
   - [\`\_\_placeAsk\`](#__placeask)
5. [Key Notes & Behavior](#key-notes--behavior)

---

## Key Data Structures

### Enums

- **`KIND`**

  - `MARKET` or `LIMIT`.
  - Currently, only **limit orders** are fully supported.

- **`SIDE`**

  - `BID` (buy the index token with the numeraire)
  - `ASK` (sell the index token for the numeraire)

- **`STATUS`**
  - `NULL`: Default initialization.
  - `OPEN`: A limit order that has been placed but not matched.
  - `PARTIAL`: An order that has been partially filled but still has `remaining` to be matched.
  - `FILLED`: The order has been matched completely.
  - `CANCELLED`: The user explicitly canceled the order.

### Structs

1. **`Trade`**  
   A simple struct used as the function argument to `place(...)`, containing:

   - `kind`: whether it’s `MARKET` or `LIMIT`.
   - `side`: either `BID` or `ASK`.
   - `price`: how many numeraire tokens for 1 index token.
   - `quantity`: total numeraire tokens (for a BID) or total index tokens (for an ASK).

2. **`Order`**  
   Stored in `orders[id]` mapping. Represents a single order with fields:

   - `id`: unique numeric identifier.
   - `trader`: the address that placed it.
   - `status`: current state (`OPEN`, `PARTIAL`, `FILLED`, `CANCELLED`).
   - `kind`: `MARKET` or `LIMIT`.
   - `side`: `BID` or `ASK`.
   - `price`: numeraire per 1 index token (e.g., 3,000 sUSD/sETH)
   - `quantity`: the original total quantity.
   - `remaining`: how many tokens are still unfilled.

3. **`Level`**  
   Each price level has:
   - `bidDepth`: total unfilled quantity of **numeraire** for all BID orders in that queue.
   - `askDepth`: total unfilled quantity of **index** tokens for all ASK orders in that queue.
   - `bids`: a FIFO queue (see `Queue.sol`) of all bid orders at this price.
   - `asks`: a FIFO queue (see `Queue.sol`) of all ask orders at this price.

---

## Constructor

```solidity
constructor(address numeraire_, address index_) {
    numeraire = Synth(numeraire_);
    index = Synth(index_);
}
```

- Initializes the contract with two ERC20 tokens:
  - **numeraire**: The currency-like token (e.g., sUSD).
  - **index**: The underlying token being traded (e.g., sETH).

This constructor simply sets the contract’s immutable references and does not mint any tokens.

---

## Public Functions

### `depth(uint256 price_) -> (uint256 bids, uint256 asks)`

```solidity
function depth(uint256 price_) public view returns (uint256 bids, uint256 asks)
```

**Purpose:**  
Allows anyone to query the aggregated liquidity at a certain **price**.

- **Parameters:** `price_` is the price level to check.
- **Returns:** `(bids, asks)`
  - `bids`: How much **numeraire** is locked in for buy orders at this price.
  - `asks`: How many **index** tokens are being sold at this price.

**What It Does Not Do:**

- It does not return the specific order IDs or their owners.
- It does not match or change any order.

### `place(Trade calldata trade_)`

```solidity
function place(Trade calldata trade_) public
```

**Purpose:**  
Entry point for creating either a **limit** or **market** order, on the **buy** or **sell** side.

- **Parameters:**
  - `trade_.quantity` must be non-zero.
  - `trade_.price` must be non-zero.
  - `trade_.kind`: only `KIND.LIMIT` is supported here.
  - `trade_.side`: `BID` or `ASK`.

**Behavior:**

- Checks basic validity (`quantity`, `price` > 0).
- If `LIMIT`:
  - If `BID`, calls [`__placeBid(trade_)`](#__placebid).
  - If `ASK`, calls [`__placeAsk(trade_)`](#__placeask).
- If `MARKET`, currently reverts as “Unsupported.”

**What It Does Not Do:**

- No immediate settlement for an **ask** is shown here (the method is incomplete in the example).
- Does not handle partial or “time in force” logic (other than partial fills done in the matching function).

### `remove(uint256 id_)`

```solidity
function remove(uint256 id_) public
```

**Purpose:**  
Allows the **owner** of an order to cancel it before it is fully filled. Returns the unfilled portion of tokens to the user.

- **Checks:**

  1. The caller must match `traders[id_]`.
  2. The order must not be `FILLED` or `CANCELLED`.
  3. The order must not be a market order.

- **Actions:**
  1. Sets `order.status = STATUS.CANCELLED`.
  2. Fetches the order’s `remaining`.
  3. Subtracts that `remaining` from `level.bidDepth` or `level.askDepth`, depending on whether it’s a bid or ask.
  4. Sets `order.remaining = 0`.
  5. Transfers that leftover token amount back to the user.

**What It Does Not Do:**

- This does not remove the order from the FIFO queue in `Queue.sol` directly. Instead, the queue remains as-is. When a matching function sees a `CANCELLED` order at the front, it dequeues it and skips processing.
- It does not update the order’s `trades` history beyond setting the status.

---

## Internal Matching Functions

### `__placeBid(Trade calldata trade_) -> uint256`

```solidity
function __placeBid(Trade calldata trade_) private returns (uint256 id)
```

**Purpose:**  
Creates a **new bid** limit order (buying `index` with `numeraire`), **immediately** attempts to fill it against existing ask orders in the same price level, and enqueues any leftover portion if it’s not fully filled.

**Process Details:**

1. **Immediate Token Transfer**

   - `numeraire.transferFrom(msg.sender, address(this), trade_.quantity);`
   - Locks the entire bid’s `quantity` of numeraire into the contract up front.

2. **Initialize Order**

   - Creates an `Order memory bid` with:
     - `id` = `cid++` (unique ascending ID)
     - `status = OPEN`
     - `price`, `quantity`, and `remaining = quantity`.

3. **Matching Loop**

   - Retrieves the `Level` for `trade_.price`.
   - While there are ask orders in `level.asks`, do:
     1. Peek the front ask (`askId = level.asks.peek()`).
     2. If that ask is `CANCELLED`, dequeue it and skip.
     3. Compare how many index tokens this new bid can still buy (`i = n / p`) vs. how many tokens the ask has left (`askRemaining`).
     4. If `i >= askRemaining`, fill the entire ask:
        - Decrement `i` by `askRemaining`.
        - Mark the ask as `FILLED`, set `ask.remaining` to 0, dequeue it.
        - Reduce `bid.remaining` in terms of numeraire as well.
        - Transfer the settlement tokens (`numeraire.transfer(...)`, `index.transfer(...)`).
        - Set `bid.status = PARTIAL` (since it’s partially matched so far).
     5. Else fill the entire _bid_ (but only part of the ask):
        - Fill `i` tokens from the ask.
        - Mark the ask as `PARTIAL` (`ask.remaining -= i`).
        - Mark the bid as `FILLED` (`bid.remaining -= i * p`).
        - Transfer tokens accordingly.
        - Break the loop (the bid is done).

4. **Post-Loop**
   - If the bid is still not `FILLED`, it means we either matched partially or not at all. We enqueue the leftover bid to `level.bids`.
   - Increase `level.bidDepth` by the leftover `bid.remaining`.
   - Store the final `bid` in `orders[id]`.
   - Save references in `traders[id]` and `trades[msg.sender]`.

**What It Does Not Do:**

- It does **not** handle any price crossing (bids that exceed multiple price levels). This example only matches within the same exact `trade_.price` level.
- Does not remove “partially filled” asks from the queue except for the portion that was filled. If the ask remains partially open, it will stay in the queue, or be re-enqueued in a more complete design.

### `__placeAsk(Trade calldata trade_) -> uint256 id`

```solidity
function __placeAsk(Trade calldata trade_) private returns (uint256 id)
```

**Purpose:**  
Would mirror `__placeBid` but for sells. Transfers `index` tokens from the user to the contract, attempts to fill them immediately with any existing **bids**. The given code is just a stub:

```solidity
if (level.bids.isEmpty()) revert("Unsupported");
else revert("Unsupported");
```

At present, it always reverts as “Unsupported.” The matching logic for an ask would be symmetrical to the bid side:

- Transfer `index` tokens in.
- Loop through `level.bids` (peek the top).
- Compare how many index tokens remain to be sold vs. how much the bid can buy.
- Fill partially or fully, track statuses, etc.

**What It Does Not Do:**

- It doesn’t actually create or match an ask order.
- No partial or full fill logic is implemented.
- No enqueuing to `asks` is done.

---

## Key Notes & Behavior

1. **Canceling Orders**

   - A user can cancel any open (or partially filled) order that hasn’t yet reached `FILLED` status.
   - This sets `status = CANCELLED` and returns leftover tokens.

2. **Skipping Canceled Orders**

   - In `__placeBid`, you explicitly skip canceled orders that appear at the front of `level.asks` by calling `dequeue()` and continuing.
   - This ensures canceled orders do not block new matches.

3. **FIFO Queues**

   - Uses `Queue.T` for each price level.
   - Orders are matched in the order they were placed (first in, first out).

4. **Price Collision**

   - At present, `__placeBid` only searches for asks in the **same** `trade_.price` level. There is no logic to handle if the best available ask has a price that is **less** than the user’s bid (which would be typical in a real exchange scenario).

5. **Incomplete `__placeAsk`**
   - As of now, the ask side is not implemented. One could replicate the logic from `__placeBid` but invert the token roles and queue usage (`bids` vs. `asks`).
