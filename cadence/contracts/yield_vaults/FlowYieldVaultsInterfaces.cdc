import "FungibleToken"
import "FlowActions"

access(all) contract interface FlowYieldVaultsInterfaces {

    access(all) struct interface Strategy {
        access(all) fun createStrategyVault(strategyID: UInt64): @{StrategyVault}
    }

    access(all) resource interface StrategyVault: FungibleToken.Provider, FungibleToken.Receiver {}

    access(all) fun createStrategyVault(strategyID: UInt64): @{StrategyVault}
}
