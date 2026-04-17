# Flow Credit Markets

## Getting started

Clone the repository and install dependencies:

```sh
flow deps install
```

Run lint & tests:

```sh
make lint
make test
```

---

## Project Layout

- `cadence/transactions/` and `cadence/scripts/` — production transactions and scripts only
- `cadence/tests/transactions/` and `cadence/tests/scripts/` — test-only helpers, not for production use

## Writing tests

Tests live in `cadence/tests/` as `*_test.cdc` files.

Use the snapshot pattern to reset blockchain state between tests without redeploying contracts:

```cadence
import Test
import BlockchainHelpers

access(all) var snapshot: UInt64 = 0

access(all) fun beforeEach() {
    if snapshot != getCurrentBlockHeight() {
        Test.reset(to: snapshot)
    }
}

access(all) fun setup() {
    // deploy contracts
    // setup code every test case needs
    snapshot = getCurrentBlockHeight()
}
```
