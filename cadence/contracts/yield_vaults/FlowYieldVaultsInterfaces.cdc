import "FungibleToken"

access(all) contract interface FlowYieldVaultsInterfaces {

    access(all) struct interface Strategy {
        access(all) fun createYieldVault(strategyID: UInt64): @{YieldVault}
    }

    access(all) resource interface YieldVault: FungibleToken.Provider, FungibleToken.Receiver {}

    access(account) fun createYieldVault(strategyID: UInt64): @{YieldVault}
}
