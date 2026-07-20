import "FungibleToken"

access(all) contract FlowYieldVaults {

    access(all) struct interface Strategy {
        access(all) fun createYieldVault(strategyID: UInt64): @YieldVault
    }

    access(all) resource YieldVault: FungibleToken.Provider, FungibleToken.Receiver {


        access(all) view fun isAvailableToWithdraw(amount _: UFix64): Bool {
            panic("TODO")
        }

        access(FungibleToken.Withdraw) fun withdraw(amount _: UFix64): @{FungibleToken.Vault} {
            panic("TODO")
        }

        access(all) fun deposit(from _: @{FungibleToken.Vault}) {
            panic("TODO")
        }

        access(all) view fun getSupportedVaultTypes(): {Type: Bool} {
            panic("TODO")
        }

        access(all) view fun isSupportedVaultType(type _: Type): Bool {
            panic("TODO")
        }
}

    access(account) fun createYieldVault(strategyID _: UInt64): @YieldVault {
        panic("not implemented")
    }
}
