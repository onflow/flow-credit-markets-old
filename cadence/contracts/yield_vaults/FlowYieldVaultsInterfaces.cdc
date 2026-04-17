import "FungibleToken"

access(all) contract interface FlowYieldVaultsInterfaces {

    access(all) struct interface Strategy {
        access(all) fun createYieldVault(name: String): @{YieldVault}
    }

    access(all) resource interface YieldVault: FungibleToken.Provider, FungibleToken.Receiver {}

    access(account) fun createYieldVault(name: String): @{YieldVault}
}
