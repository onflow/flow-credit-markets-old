# Numeraire Specification
## Background
Prices of assets must be denominated in some particular common unit — the Numeraire (unit of account).
The numeraire is the default currency against which everything else is measured,
and is used to request prices from price oracles.

## Summary
1. The numeraire type is stored in a `Type` field in the `FlowALP.PoolConfig` struct, set on initialization.
   It should not change during the lifetime of the Pool.
2. To handle conversion between FungibleToken `Type`s (used by FlowALP)
   and currency symbol strings (used by price sources),
   a dictionary should be implemented mapping Types -> currency symbols.
   - This should be part of the price oracle interface.

We currently use an off-chain currency, `USD`, as the numeraire (see `OffchainCurrency.cdc`).
This is implemented as a FungibleToken type representing `USD`.

In the future, we plan to use `MOET` as the numeraire.

## Requirements
- Always use the numeraire as the unit of account when requesting prices from price oracles.
  For example, as the `quoteSymbol` if directly querying the `BandOracle` price source.

## Non-Goals
Types representing off-chain currencies MUST NOT function as actual fungible tokens
that can be transferred or traded on-chain; they should only be used to compare relative prices.
Therefore, vaults for these currencies should not be constructible. This is enforced in `OffchainCurrency.cdc`.
