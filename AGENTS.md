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
The documentation comments ("doc-strings" / "doc-comments": line comments starting with `///`,
or block comments starting with `/**`) available in Cadence programs are processed by the tool,
to produce human-readable documentations.

### Markdown Support
Standard Markdown format is supported in doc-comments, with a bit of Cadence flavour.
This means, any Markdown syntax used within the comments would be honoured and rendered like a standard Markdown snippet.
It gives the flexibility for the developers to write well-structured documentations.

e.g: A set of bullet points added using Markdown bullets syntax would be rendered as bullet points in the
generated documentation as well.

Documentation Comment:
```
/// This is the description of the function. You can use markdown syntax here.
/// Can use **bold** or _italic_ texts, or even bullet-points:
///   - Here's the first point.
///   - Can also use code snippets (eg: `a + b`)
  ```
Output:

>This is the description of the function. You can use markdown syntax here.<br/>
>Can use **bold** or _italic_ texts, or even bullet-points:
>   - Here's the first point.
>   - Can also use code snippets (eg: `a + b`)


### Function Documentation
Function documentation may start with a description of the function.
It also supports a special set of tags to document parameters and return types.
Parameters can be documented using the `@param` tag, followed by the parameter name, a colon (`:`) and the parameter description.
The return type can be documented using the `@return` tag.

```
/// This is the description of the function. This function adds two values.
///
/// @param a: First integer value to add
/// @param b: Second integer value to add
/// @return Addition of the two arguments `a` and `b`
///
pub fun add(a: Int, b: Int): Int {
}
```

## Best Practices
- Avoid using headings, horizontal-lines in the documentation.
  - It could potentially conflict with the headers and lines added by the tool, when generating the documentation
  - This may cause the generated documentation to be rendered in a disorganized manner.
- Use inline-codes (within backticks `` `foo` ``) when referring to names/identifiers (such as function names,
  parameter names, etc.) in the code.
  ```
  /// This is the description of the function.
  /// This function adds `a` and `b` values.
  ///
  pub fun add(a: Int, b: Int): Int {
  }
  ```
- When documenting function parameters and return type, avoid mixing parameter/return-type documentations
  with the description of the function. e.g:
  ```
  /// This is the description of the function.
  ///
  /// @param a: First integer value to add
  /// @param b: Second integer value to add
  ///
  /// This function adds two values. However, this is not the proper way to document it.
  /// This part of the description is not in the proper place.
  ///
  /// @return Addition of the two arguments `a` and `b`
  ///
  pub fun add(a: Int, b: Int): Int {
  }
  ```
