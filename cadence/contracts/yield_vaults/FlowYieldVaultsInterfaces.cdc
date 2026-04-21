import "FungibleToken"

/// Contract interface shared between `FlowYieldVaults` and concrete strategy
/// contracts. Defines the two extension points of the yield vault system:
///
/// - `Strategy`: a struct interface implemented by each concrete strategy
///   contract. Strategies are the factories — they mint `YieldVault` resources
///   and carry the strategy-specific logic (target protocol, accounting,
///   rewards, etc.).
/// - `YieldVault`: a resource interface describing a yield-generating position.
///   The concrete resource type is defined *inside each strategy contract*
///   and returned from `Strategy.createYieldVault`. `FlowYieldVaults` itself
///   contains no vault implementation; it only composes strategies.
///
/// This split lets strategies evolve independently of the registry. New
/// strategies can be added or removed without changing `FlowYieldVaults`,
/// and each strategy owns its own vault resource lifecycle.
access(all) contract interface FlowYieldVaultsInterfaces {

    /// Factory for `YieldVault` resources. Implemented by each concrete
    /// strategy contract (e.g. a lending strategy, a DEX LP strategy).
    access(all) struct interface Strategy {
        /// Mints a new `YieldVault` resource for this strategy.
        ///
        /// **Parameters**
        /// - `name`: Registry name under which this strategy is exposed.
        ///   Forwarded by `FlowYieldVaults.createYieldVault` and available
        ///   to the strategy if it wants to stamp the vault with its name.
        access(all) fun createYieldVault(name: String): @{YieldVault}

        /// Free-form metadata about this strategy as a key → value map.
        /// Each strategy decides what to expose (e.g. `"description"`,
        /// `"protocol"`, `"asset"`). Surfaced by
        /// `FlowYieldVaults.strategyInfos()` so UIs can list strategies
        /// without hard-coding their metadata.
        access(all) view fun info(): {String: String}
    }

    /// Yield-generating position minted by a strategy. The concrete resource
    /// type lives inside the strategy contract — this interface only exposes
    /// the `FungibleToken` surface shared by all vaults.
    access(all) resource interface YieldVault: FungibleToken.Provider, FungibleToken.Receiver {}

    /// Mints a yield vault from a registered strategy. See
    /// `FlowYieldVaults.createYieldVault` for the full contract.
    access(account) fun createYieldVault(name: String): @{YieldVault}
}
