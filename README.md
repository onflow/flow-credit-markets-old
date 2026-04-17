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

## Project Structure

```
cadence/
├── contracts/
│   ├── actions/
│   │   └── FlowActions.cdc                 # Reusable Interfaces
│   ├── alp/
│   │   └── FlowALP.cdc                     # Active Lending Protocol
│   └── yield_vaults/
│       ├── FlowYieldVaults.cdc             # Yield Vault
│       └── FlowYieldVaultsEarlyAccess.cdc  # Allowlist gate for early access
│
├── scripts/                                # Production scripts
│   ├── actions/
│   ├── alp/
│   └── yield_vaults/
│
├── transactions/                           # Production transactions
│   ├── actions/
│   ├── alp/
│   └── yield_vaults/
│
└── tests/
    ├── helpers/                            # Shared test utilities
    ├── mocks/                              # Mock contracts for isolated unit tests
    ├── scripts/                            # Scripts used only in tests
    │   ├── actions/
    │   ├── alp/
    │   └── yield_vaults/
    ├── transactions/                       # Transactions used only in tests
    │   ├── actions/
    │   ├── alp/
    │   └── yield_vaults/
    └── *_test.cdc                          # Test suites

docs/                                       # Design specs and architecture notes
```
