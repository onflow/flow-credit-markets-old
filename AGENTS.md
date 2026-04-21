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

- Use red-green TDD for bug fixes and extensions to functionality. Tests must use assertions (eg. `Test.assert`) to verify expected behaviour, not logs.
- Use string templating, not concatenation: `"Hello \(name)"` not `"Hello ".concat(name)`

# Documentation

## Documentation Comments Format
Documentation comments ("doc-strings" / "doc-comments") are line comments starting with `///` or block comments starting with `/**`, attached to declarations (contracts, resources, structs, functions, fields, events).

### Markdown Support
Standard Markdown is supported in doc-comments. Any Markdown syntax in the comment is rendered as Markdown — use bold, italics, bullet lists, inline code, etc. as needed.

```
/// This is the description of the function. You can use markdown syntax here.
/// Can use **bold** or _italic_ texts, or even bullet-points:
///   - Here's the first point.
///   - Can also use code snippets (eg: `a + b`)
```

### Function Documentation
Function documentation has three parts, in order:

1. **Description** — one or more sentences explaining what the function does. Call out panics or side effects here if they affect the caller.
2. **Parameters** block (only when the function takes parameters) — the bold label `**Parameters**` on its own line, followed by a bullet list with one line per parameter in the form ``` - `name`: description ```.
3. **Returns** block (only when the function returns a non-`Void` value) — the bold label `**Returns**` inline, followed by a prose description of the return value.

Blocks are separated by blank comment lines (`///`).

```
/// Consumes one unit of allowance and creates a new yield vault.
/// Panics if allowance is exhausted.
///
/// **Parameters**
/// - `name`: Name of the registered strategy to create a vault for.
///
/// **Returns** A new `YieldVault` to be saved in the caller's storage.
access(all) fun createYieldVault(name: String): @{FlowYieldVaultsInterfaces.YieldVault} {
    // ...
}
```

For short functions where the description already names the parameters and return value in prose, the Parameters / Returns blocks can be omitted:

```
/// Returns `|numer − denom| / denom`, or `0.0` when `denom = 0`.
/// Used to compare `|1 − (numer / denom)|` without UFix64 underflow.
view access(all) fun absDeviationFromOne(_ numer: UFix64, _ denom: UFix64): UFix64 {
    // ...
}
```

## Best Practices
- Avoid Markdown headings (`#`, `##`, ...) and horizontal rules (`---`) inside doc-comments. Use `**bold labels**` (like `**Parameters**`, `**Returns**`) when you need section-like structure.
- Use inline-codes (within backticks `` `foo` ``) when referring to names / identifiers (function names, parameter names, types, field names, etc.).
  ```
  /// Adds `a` and `b`.
  access(all) fun add(a: Int, b: Int): Int {
      // ...
  }
  ```
- Keep the description at the top. Do not interleave description text with the Parameters or Returns blocks.
  ```
  /// NOT this:
  ///
  /// Description sentence 1.
  ///
  /// **Parameters**
  /// - `a`: First value.
  ///
  /// Description sentence 2 — this belongs up with sentence 1.
  ///
  /// **Returns** The sum.
  ```
- Put Returns after Parameters; do not split them with extra description.
- When a function panics, say so in the description ("Panics if …"), not as a separate block.
