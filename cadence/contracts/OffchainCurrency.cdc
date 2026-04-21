import "FungibleToken"

/// OffchainCurrency refers to real-world currencies that do not actually exist on-chain, e.g. USD.
/// (It does NOT refer to stablecoins pegged to those currencies, such as pyUSD, USDC, etc.)
/// Offchain currency types are only intended for use as a numeraire (unit of account),
/// to provide a common baseline for the relative prices of other tokens and currencies returned by price oracles.
/// Therefore vaults of OffchainCurrency cannot be created.
///
access(all) contract interface OffchainCurrency: FungibleToken {

    /// Vaults of this currency cannot be created - enforced by type system with return type of `Never`.
    access(all) fun createEmptyVault(vaultType _: Type): Never {
        panic("Cannot create vault for OffchainCurrency \(self.getType().identifier)")
    }
}
