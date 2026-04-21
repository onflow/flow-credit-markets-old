import "FlowYieldVaultsInterfaces"

/// Registry of yield vault strategies on this account, keyed by name.
/// An `Admin` resource (saved at `adminStoragePath` on the contract account)
/// registers and removes strategies conforming to
/// `FlowYieldVaultsInterfaces.Strategy`. Yield vaults are minted from a
/// registered strategy by `name` through `createYieldVault`.
///
/// This contract is strategy-agnostic: it does not depend on any specific
/// strategy family. Concrete strategies live in their own contracts and are
/// plugged in through `Admin.registerStrategy`.
access(all) contract FlowYieldVaults: FlowYieldVaultsInterfaces {

    /// Emitted when a strategy is registered under `name`.
    access(all) event StrategyCreated(name: String)
    /// Emitted when a strategy is removed from the registry.
    access(all) event StrategyRemoved(name: String)
    /// Emitted when a yield vault is minted from the named strategy.
    access(all) event StrategyVaultCreated(name: String)

    /// Storage path where the `Admin` resource is saved on this account.
    access(all) let adminStoragePath: StoragePath

    /// Registered strategies, keyed by name. Names are unique; registering
    /// an already-used name panics.
    access(self) let strategies: {String: {FlowYieldVaultsInterfaces.Strategy}}

    /// Admin resource; holder may register / remove strategies and mint
    /// yield vaults directly (bypassing any external access gate).
    access(all) resource Admin {
        /// Registers `strategy` under `name`.
        /// Panics if a strategy is already registered under that name.
        ///
        /// **Parameters**
        /// - `name`: Unique identifier for the strategy in this registry.
        /// - `strategy`: Any value conforming to
        ///   `FlowYieldVaultsInterfaces.Strategy`.
        access(all) fun registerStrategy(
            name: String,
            strategy: {FlowYieldVaultsInterfaces.Strategy}
        ) {
            assert(
                FlowYieldVaults.strategies[name] == nil,
                message: "Strategy already registered: \(name)"
            )
            FlowYieldVaults.strategies[name] = strategy
            emit StrategyCreated(name: name)
        }

        /// Removes the strategy registered under `name`.
        /// Panics if no strategy is registered under that name. Does not
        /// affect already-minted yield vaults — those captured the strategy
        /// parameters at creation time.
        ///
        /// **Parameters**
        /// - `name`: Name of the strategy to remove.
        access(all) fun removeStrategy(name: String) {
            let strategy = FlowYieldVaults.strategies.remove(key: name)
            if strategy == nil {
                panic("Strategy not found")
            }
            emit StrategyRemoved(name: name)
        }
    }

    /// Mints a yield vault from a registered strategy.
    /// Panics if no strategy is registered under `name`.
    ///
    /// **This function will be made `access(all)` once early access ends.**
    /// The `access(account)` gate is a temporary launch-phase restriction that
    /// funnels all user-facing vault creation through `FlowYieldVaultsEarlyAccess`.
    /// Treat this function as if it were already public when reasoning about
    /// security: it must be safe for any caller to invoke with any registered
    /// `name`, and downstream logic (strategies, vault resources) must not rely
    /// on the gate to keep untrusted callers out.
    ///
    /// **Parameters**
    /// - `name`: Name of the registered strategy.
    ///
    /// **Returns** A new `YieldVault` for the caller to save in storage.
    access(account) fun createYieldVault(name: String): @{FlowYieldVaultsInterfaces.YieldVault} {
        let strategy = self.strategies[name] ?? panic("Strategy not found")
        let vault <- strategy.createYieldVault(name: name)
        emit StrategyVaultCreated(name: name)
        return <- vault
    }

    view access(all) fun strategyCount(): UInt64 {
        return UInt64(self.strategies.length)
    }

    /// Returns a map of registered strategy name → strategy info map.
    /// Each info map is produced by the strategy itself via
    /// `FlowYieldVaultsInterfaces.Strategy.info()`; this contract stores no
    /// metadata of its own.
    view access(all) fun strategyInfos(): {String: {String: String}} {
        let infos: {String: {String: String}} = {}
        for name in self.strategies {
            infos[name] = self.strategies[name]!.info()
        }
        return infos
    }

    init() {
        self.strategies = {}
        self.adminStoragePath = StoragePath(identifier: "FlowYieldVaultsAdmin")!
        self.account.storage.save(<- create Admin(), to: self.adminStoragePath)
    }
}
