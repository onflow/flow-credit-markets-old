# flow-credit-markets Top-level Agent Instructions

This document provides top-level information to agents (Claude Code etc.).
**It is loaded into context automatically for all sessions in this repo, so keep it concise!**

# Testing

All Cadence test files are located in:

```
cadence/tests/*_test.cdc
```

## Run All Tests

```bash
make test
```

## Run Individual Test Files

To run a specific test file:

```bash
flow test <path/to/test_file.cdc>
```

**Example:**
```bash
flow test cadence/tests/random_test.cdc
```

## Run Individual Tests by Name

**IMPORTANT**: To run a specific test function by name, you **must** specify the file path:

```bash
flow test <path/to/test_file.cdc> --name <test_function_name>
```

**Example:**
```bash
flow test cadence/tests/random_test.cdc --name testSomeFunction
```

### Find all tests in a file
```bash
grep "fun test" cadence/tests/random_test.cdc
```

# Linting

```bash
make lint
```

Run both lint and tests:

```bash
make ci
```

# Cadence Coding Guidelines

- Use string templating, not concatenation: `"Hello \(name)"` not `"Hello ".concat(name)`
- Use `equalWithinVariance` from `test_helpers.cdc` for equality assertions where rounding errors are possible
- Use red-green TDD for bug fixes and extensions to functionality. Tests must use assertions (eg. `Test.assert`) to verify expected behaviour, not logs.
