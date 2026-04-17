import "FungibleToken"
import "FlowYieldVaultsInterfaces"

access(all) contract MockStrategy {

    access(all) struct Strategy: FlowYieldVaultsInterfaces.Strategy {
        access(all) fun createYieldVault(name _: String): @{FlowYieldVaultsInterfaces.YieldVault} {
            return <- create Vault()
        }
    }

    access(all) resource Vault: FlowYieldVaultsInterfaces.YieldVault {
        access(all) fun deposit(from: @{FungibleToken.Vault}) {
            destroy from
        }

        access(FungibleToken.Withdraw) fun withdraw(amount _: UFix64): @{FungibleToken.Vault} {
            panic("not implemented")
        }

        access(all) view fun isAvailableToWithdraw(amount _: UFix64): Bool {
            return false
        }

        access(all) view fun getSupportedVaultTypes(): {Type: Bool} {
            return {}
        }

        access(all) view fun isSupportedVaultType(type _: Type): Bool {
            return false
        }
    }

    access(all) fun createStrategy(): Strategy {
        return Strategy()
    }
}
