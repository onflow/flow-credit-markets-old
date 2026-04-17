import "FungibleToken"
import "FlowYieldVaultsInterfaces"

access(all) contract FlowYieldVaults: FlowYieldVaultsInterfaces {

    access(all) resource YieldVault: FlowYieldVaultsInterfaces.YieldVault {
        access(all) view fun isAvailableToWithdraw(amount: UFix64): Bool {
            let _ = amount
            return false
        }

        access(FungibleToken.Withdraw) fun withdraw(amount _: UFix64): @{FungibleToken.Vault} {
            panic("Not implemented")
        }

        access(all) fun deposit(from: @{FungibleToken.Vault}) {
            destroy from
        }

        access(all) view fun getSupportedVaultTypes(): {Type: Bool} {
            return {}
        }

        access(all) view fun isSupportedVaultType(type: Type): Bool {
            let _ = type
            return false
        }
    }

    access(account) fun createYieldVault(name: String): @{FlowYieldVaultsInterfaces.YieldVault} {
        let _ = name
        return <- create YieldVault()
    }
}
