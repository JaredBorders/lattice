# Lattice – Comprehensive Documentation

This document describes **Lattice**: an EVM-based, on-chain limit order book system designed for trading between two ERC20 tokens. Lattice’s contracts are written in Solidity and utilize [Foundry](https://book.getfoundry.sh/) for building, testing, and deployment.

- [Overview](#overview)
- [System Components](#system-components)
  - [1. `Market.sol`](#1-marketsol)
  - [2. `Queue.sol`](#2-queuesol)
  - [3. `Hook.sol`](#3-hooksol)
  - [4. `ERC20.sol`](#4-erc20sol)
- [Usage](#usage)
- [Performance and Gas Usage](#performance-and-gas-usage)
- [Disclaimer](#disclaimer)

---

## Overview

A Lattice market supports trading between a pair of `ERC20` tokens: **`index`** and **`numéraire`**.

#### Key Concepts

**Numéraire**: a _numéraire_ is a standard benchmark or **reference asset** against which all other assets are measured or valued. It serves as the **unit of account**, facilitating **comparative valuation** and enhancing liquidity by offering a common denominator.

> Typically, fiat currencies or stable assets serve as numéraires in derivative pricing models. For instance, in traditional foreign exchange markets, one might select the U.S. Dollar as a numéraire to price all other currencies. In DeFi systems like Lattice, the numéraire may be a stablecoin or other liquid, low-volatility token, fulfilling the same role of a consistent measure of value. The numéraire serves as the primary asset for valuation, providing a stable baseline for measuring the value of the index token.

**Index**: an _index_ refers to a **tradable asset** or a **composite representation of multiple assets**, which may include synthetic tokens, risk-bearing assets, or aggregated derivatives.

> In traditional markets, indices are frequently constructed to track the performance of a particular basket of assets, such as the S&P 500. Within Lattice, the index is often a synthetic or volatile token whose value is measured relative to the numéraire, embodying the directional exposure or risk component of a trading pair. The relationship between the numéraire and the index is akin to the pricing of derivatives, where the index’s value fluctuates relative to the stability of the numéraire. This dynamic is fundamental to the construction of various financial instruments and structured products.

**Limit Order**: a *limit order* placed at a specific price (in units of `numéraire / index`). Each price level is managed with **FIFO (first-in-first-out)** queues for bids and asks. When placing a new limit order:

1. The entire token quantity (numéraire for bids, index for asks) is transferred up-front into the `Market`.
2. The order tries to fill immediately against existing orders on the opposite side at that exact price.
3. Any unfilled amount is queued and remains on the book until it is fully matched or explicitly canceled.

---

## System Components

### 1. `Market.sol`

The core contract that implements the on-chain limit order book.

#### Key Enumerations

```solidity
enum KIND {
    MARKET,
    LIMIT
}

enum SIDE {
    BID,
    ASK
}

enum PARTICIPANT {
    ANY,
    MAKER,
    TAKER
}

enum STATUS {
    NULL,
    OPEN,
    PARTIAL,
    FILLED,
    CANCELLED
}
```

- **`KIND`** determines whether an order is a `LIMIT` or `MARKET`.
- **`SIDE`** designates whether the user is bidding (buy index) or asking (sell index).
- **`PARTICIPANT`** allows for further execution logic extension (maker/taker).
- **`STATUS`** tracks an order’s life cycle from creation to fill or cancellation.

#### Data Structures

##### `type Price is uint128;`

Defines a strongly-typed `Price`.

##### `struct Trade`

Used by `Market.place(...)`:

```solidity
struct Trade {
    KIND kind;
    SIDE side;
    Price price;
    uint128 quantity;
}
```

- `kind`: `LIMIT` or `MARKET`.
- `side`: `BID` or `ASK`.
- `price`: The limit price in `numéraire` per `index`.
- `quantity`: For `BID`, how many numéraire tokens are posted; for `ASK`, how many index tokens are posted.

##### `struct Order`

Represents an individual order stored by the book:

```solidity
struct Order {
    uint64 id;
    uint32 blocknumber;
    address trader;
    STATUS status;
    KIND kind;
    SIDE side;
    Price price;
    uint128 quantity;
    uint128 remaining;
}
```

- `remaining`: Tracks how many tokens are left unfilled (numéraire if `BID`, index if `ASK`).
- `status` updates to `PARTIAL`, `FILLED`, or `CANCELLED` as events occur.

##### `struct Level`

Holds data for a specific price level:

```solidity
struct Level {
    uint128 bidDepth;     // total numéraire locked in bid orders at this price
    uint128 askDepth;     // total index locked in ask orders at this price
    Queue.T bids;         // FIFO queue of bid order IDs
    Queue.T asks;         // FIFO queue of ask order IDs
}
```

- `bidDepth` / `askDepth` sum the total unfilled tokens for quick reference.
- Each side has a FIFO queue for order IDs.

#### Constructor

```solidity
constructor(address numéraire_, address index_) {
    numéraire = Synth(numéraire_);
    index = Synth(index_);
}
```

- Initializes references to two ERC20 tokens: `numéraire` and `index`.

#### Introspection Functions

- **`depth(Price price_) -> (uint128, uint128)`**  
  Returns `(bidDepth, askDepth)` at a specific price level.

- **`bids(Price price_) -> uint64[]`**  
  Returns the queued **bid** order IDs at `price_`.

- **`asks(Price price_) -> uint64[]`**  
  Returns the queued **ask** order IDs at `price_`.

- **`getOrder(uint64 id_) -> Order`**  
  Returns the full `Order` struct for the given ID.

#### Trading Functions

##### `place(Trade calldata trade_)`

1. Checks:
   - `trade_.quantity > 0`
   - `Price.unwrap(trade_.price) > 0`
2. If `trade_.kind == KIND.LIMIT`:
   - If `side == BID`, calls `__placeBid(trade_)`.
   - If `side == ASK`, calls `__placeAsk(trade_)`.
3. If `trade_.kind == KIND.MARKET`, reverts as market orders are not yet _fully_ supported in this implementation.

##### `remove(uint64 id_)`

Allows an **order owner** to cancel an order if it’s `OPEN` or `PARTIAL`:

1. Checks:
   - `msg.sender` must be the order’s `trader`.
   - Order must not be `FILLED` or `CANCELLED`.
   - Order must not be `MARKET`.
2. Sets `order.status = CANCELLED`.
3. Returns the `remaining` tokens to the owner and sets `order.remaining = 0`.
4. Adjusts the relevant `Level`’s `bidDepth` or `askDepth`.

> **Note**  
> The canceled order remains in the FIFO queue until encountered again during matching, at which point it is skipped and removed.

#### Internal Matching Logic

- **`__placeBid(Trade calldata trade_) -> uint64`**

  - Pulls `trade_.quantity` numéraire from the bidder to the contract.
  - Initializes an `Order` with `remaining = trade_.quantity`.
  - Attempts matching against all queued asks at `trade_.price`.
    - Compare how many index tokens can be purchased vs. how many remain in each ask.
    - Transfer tokens accordingly, update statuses, and dequeue asks as needed.
  - If still unfilled, the order is enqueued into `level.bids`.

- **`__placeAsk(Trade calldata trade_) -> uint64`**
  - Pulls `trade_.quantity` index tokens from the asker to the contract.
  - Initializes an `Order` with `remaining = trade_.quantity`.
  - Attempts matching against all queued bids at `trade_.price`.
    - Compare how much numéraire the ask can obtain vs. how much remains in each bid.
    - Transfer tokens accordingly, update statuses, and dequeue bids as needed.
  - If still unfilled, the order is enqueued into `level.asks`.

#### Key Notes and Behavior

1. **Immediate Token Transfer**
   - When a bid is placed, `numéraire.transferFrom(msg.sender, address(this), quantity)` is called. For an ask, `index.transferFrom(...)`.
2. **Partial Fills**
   - An order can be partially filled, with leftover remaining on the order book (`status = PARTIAL`).
3. **FIFO**
   - Within each price level, orders are processed strictly in the order they arrived (`Queue.T`).
4. **Single Price-Level**
   - Orders match **only** at the specified price. No crossing multiple price levels.
5. **Gas Considerations**
   - Because canceled orders remain in the queue until encountered, repeated partial matching can have incremental costs.

---

### 2. `Queue.sol`

A minimal FIFO (first-in-first-out) queue, specialized for storing `uint64` order IDs. Key functions:

- `enqueue(uint64)`: Appends an element.
- `dequeue()`: Removes and returns the oldest element. Reverts if empty.
- `peek()`: Returns the oldest element without removing. Reverts if empty.
- `isEmpty()`, `size()`: Utility checks.
- `toArray()`: Converts the queue contents to a dynamic array.

Internally, it uses a mapping-based circular buffer:

```solidity
struct T {
    uint128 front;
    uint128 back;
    mapping(uint128 => uint64) data;
}
```

---

### 3. `Hook.sol`

Provides a basic framework for programmatic liquidity extensions:

```solidity
enum METHOD {
    PLACE,
    REMOVE
}

struct Operation {
    METHOD method;
    bytes parameters;
}
```

- `_dispatch(Market market_, Operation memory op_)`: Decodes the operation’s parameters and calls `market_.place(...)` or `market_.remove(...)` accordingly.

Currently, the default `Market` doesn’t automatically call these hooks, but they can be integrated in other contexts to allow more complex or automated strategies.

---

### 4. `ERC20.sol`

A simplified (abstract) ERC20 contract implementing core logic:

- Manages `balances` and `allowances`.
- Standard transfer, `transferFrom`, and allowance patterns.
- Hooks for `_beforeTokenTransfer` and `_afterTokenTransfer` for extended functionality.
- In Lattice’s usage:
  - **numéraire**: stable-like token.
  - **index**: synthetic or risk-like token.

This contract can be subclassed or replaced with real tokens in production.

---

## Usage

Lattice uses [Foundry](https://book.getfoundry.sh/) for compilation, testing, and deployment. To further simplify interactions with the codebase, a `Makefile` is included for common tasks relating to foundry.

How to build, test, format, and snapshot the code:

1. **Build**
   ```shell
   make build
   ```
2. **Test**
   ```shell
   make test
   ```
3. **Format**
   ```shell
   make fmt
   ```
4. **Snapshot: Test Coverage & Gas Benchmarks**
   ```shell
   make snap
   ```

#### Dependencies

External dependencies are managed via Soldeer, a **Solidity Package Manager** written in rust and integrated into Foundry. How to install and update dependencies:

1. **Install Dependency**

   ```shell
   make add dependency=<DEPENDENCY>
   ```

   The dependency will be installed into the `dependencies/` directory. For example:

   ```shell
   make add dependency=@openzeppelin-contracts~5.0.2
   ```

2. **Remove Dependency**

   ```shell
    make remove dependency=<DEPENDENCY>
   ```

   The dependency will be removed from the `dependencies/` directory. For example:

   ```shell
   make remove dependency=@openzeppelin-contracts
   ```

   > **Note**
   > When removing a dependency, Soldeer will remove all artifacts and remappings related to the dependency. This includes:
   >
   > (1) the config entry
   > (2) the dependencies artifacts
   > (3) the soldeer.lock entry
   > (4) the remappings entry (txt or config remapping)
   >
   > Additionally you can manually remove a dependency by just removing the artifacts: dependency files, config entry, remappings entry.

---

## Performance and Gas Usage

An extensive test suite measures how Lattice performs under various scenarios (e.g., placing bids or asks, partial fills, cancellations). Below is a general overview of typical gas consumption:

1. **Placing a Limit Bid**

   - Common gas usage ranges ~210,000–300,000 per order, with a median near 296,000 gas in the tests.
   - A dedicated benchmark (`BidBenchmarkTest.test_benchmark_place_bid`) observed ~210,439 gas for one specific scenario.
   - Under a 30,000,000 gas block limit, you could place about 142 bids per block.

2. **Placing a Limit Ask**

   - Similar range: ~210,000–300,000 gas each, with a typical measurement around 278,647 gas in a benchmark scenario (`AskBenchmarkTest.test_benchmark_place_ask`).
   - Under the same block limit, around 107 asks could fit in a single block.

3. **Matching / Settlement**

   - Filling or partially filling an existing order often costs more gas.
   - “Fill” tests (`OrderSettlementTest`) recorded ~530,000 gas for bid/ask matches. Partial fills are similar, at ~508,000 gas.
   - Costs can scale if multiple orders are queued at the same price or if partially filled orders remain.

4. **Cancellation**

   - Removing an order (`RemoveOrderTest.test_remove_*`) typically costs ~240,000 gas, including overhead for status updates, balance transfers, and `bidDepth` / `askDepth` adjustments.

5. **Batch or Varied Orders**

   - Tests that place multiple orders in loops or add “variance” to price/quantity can accumulate multi-million gas totals.
   - This is primarily the sum of each individual placement/update operation in a single transaction.

6. **Queue Operations**
   - Core FIFO queue usage in `Queue.sol` remains efficient; single enqueues/dequeues are relatively low cost.
   - More expensive operations occur if large numbers of orders are enqueued and later converted to arrays with `toArray()`.

### Summary

- **Limit Bids**: ~210k–300k gas each (some scenarios near ~296k).
- **Limit Asks**: ~210k–300k gas each (some scenarios near ~278k).
- **Full/Partial Settlement**: ~530k gas on average.
- **Canceling Orders**: ~240k gas.
- **Repeated Orders**: Potentially millions of gas, depending on how many are placed in a single transaction.

> **Note**  
> These figures were recorded in local Foundry tests. Real-world performance can vary depending on network state, compiler versions, and other factors. Always profile in your target environment for accurate estimates.

---

## Disclaimer

This software is provided "as is" and "as available" without warranties of any kind, express or implied. The authors disclaim all liability for any loss or damage resulting from the use or misuse of this codebase. While Lattice has undergone extensive testing, its performance when integrated with other systems is not guaranteed. Users are advised to conduct their own thorough testing to ensure compatibility and expected functionality. Use at your own risk.
