# Lattice – On-Chain Limit Order Book

Lattice provides a straightforward, EVM-based limit order book (LOB) that allows developers to list bids and asks for two ERC20 tokens. It is built on top of [Foundry](https://book.getfoundry.sh/) for easy compilation, testing, and deployment, and is designed for easy extension via programmatic liquidity.

---

## Overview

**Lattice** is a permissionless market mechanism that handles trades between two ERC20 tokens:

1. A **numeraire** token (e.g., a stable-like asset).
2. An **index** token (e.g., a synthetic or speculative asset).

All orders are placed with a specific **price** (quoted in `numeraire per index`) and managed through **FIFO (first-in-first-out)** queues at each price level. When an order is placed, it immediately attempts to match against opposite-side orders at the same price. Any unfilled portion is enqueued and can later be canceled by its owner or matched by incoming orders.

### Highlights

- **Immediate Token Lock**: Bids require sending numeraire tokens up-front; asks require index tokens up-front.  
- **Partial Fills & Cancellation**: Orders can be partially filled, leaving a remainder on the book. Users can remove an open or partially filled order to reclaim remaining tokens.  
- **Single Price-Level Matching**: Incoming orders only match against the exact price level. No multi-level or best-price crossing.  
- **FIFO Queues**: Older orders have priority at any given price level, ensuring fair ordering.  
- **Hook Library**: Lattice includes an optional `Hook` library for advanced extension (e.g., programmatic liquidity strategies).

---

## Foundry Quickstart

[Foundry](https://book.getfoundry.sh/) is a modular toolkit for Ethereum application development, written in Rust. After installing Foundry, you can use the following commands:

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
forge snapshot
```

### Anvil (Local Testing)

```shell
anvil
```

### Script Deployment (Example)

```shell
forge script script/Counter.s.sol:CounterScript \
    --rpc-url <YOUR_RPC_URL> \
    --private-key <YOUR_PRIVATE_KEY>
```

### Cast

```shell
cast <subcommand>
```

For more details on Foundry, see the [official book](https://book.getfoundry.sh/).

---

## Contract Architecture

### 1. `Market.sol`

Central to Lattice’s design, `Market` maintains:

- **Bid/Ask Queues** for each price level.
- **Order Matching Logic** that processes bids and asks in FIFO order within that level.
- **ERC20 Interactions** to lock tokens up-front when orders are placed.

Each **limit order** is stored as an `Order` struct, containing fields such as:
- `id` (unique identifier),
- `side` (bid or ask),
- `status` (open, partial, filled, canceled),
- `remaining` (tokens still unmatched).

#### Order Placement

```solidity
function place(Trade calldata trade_) public
```

- Verifies non-zero `trade_.quantity` and `trade_.price`.
- If `trade_.kind` == `LIMIT`, routes to private matching routines:  
  - `__placeBid(...)` or `__placeAsk(...)`.
- If `trade_.kind` == `MARKET`, reverts.

#### Order Removal

```solidity
function remove(uint64 id_) public
```

- Cancels the user’s order if it’s still open or partially filled.
- Returns unfilled tokens (numeraire or index) to the owner.
- Marks the order as `CANCELLED`, so it will be skipped in future matching.

### 2. `Queue.sol`

Provides a minimal FIFO queue for storing order IDs. Supports:
- `enqueue(uint64 value_)`
- `dequeue()` (throws if empty)
- `peek()` (throws if empty)
- `isEmpty()`, `size()`, `toArray()`

Used within `Market` to track orders for each price level.

### 3. `Hook.sol`

Defines an optional extension approach where custom liquidity logic can be inserted. Currently, it offers a simple `_dispatch` method to decode and forward operations (`place` or `remove`).

### 4. `ERC20.sol`

A simplified ERC20 contract that `Market` references for transferring numeraire and index tokens. In production, you’d likely point this to real tokens; in tests, it can be subclassed or mocked.

---

## Example Flow

1. **User A** places a limit ask (10 index at price = 5). The contract pulls 10 index tokens from User A, then tries matching with existing bids at price = 5. Any remainder is queued.
2. **User B** places a limit bid (40 numeraire, intending to buy 8 index at price = 5). If there’s an ask at that same price, the contract matches immediately.  
3. If the ask can’t be fully filled by the bid, the remainder remains in the queue, awaiting future matches or cancellation.

---

## Contributing and Feedback

- **Pull Requests** are welcome!
- **Issues**: Please report any bugs or potential improvements.
