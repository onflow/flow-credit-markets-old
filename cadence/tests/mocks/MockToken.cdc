import "FungibleToken"

access(all) contract MockToken: FungibleToken {

    access(all) resource Vault: FungibleToken.Vault {
        access(all) var balance: UFix64

        init(balance: UFix64) {
            self.balance = balance
        }

        access(contract) fun burnCallback() {
            self.balance = 0.0
        }

        access(all) view fun getViews(): [Type] { return [] }
        access(all) fun resolveView(_ view: Type): AnyStruct? {
            let _ = view
            return nil
        }

        access(all) view fun isAvailableToWithdraw(amount: UFix64): Bool {
            return amount <= self.balance
        }

        access(FungibleToken.Withdraw) fun withdraw(amount: UFix64): @{FungibleToken.Vault} {
            self.balance = self.balance - amount
            return <- create Vault(balance: amount)
        }

        access(all) fun deposit(from: @{FungibleToken.Vault}) {
            let vault <- from as! @MockToken.Vault
            self.balance = self.balance + vault.balance
            vault.balance = 0.0
            destroy vault
        }

        access(all) fun createEmptyVault(): @{FungibleToken.Vault} {
            return <- create Vault(balance: 0.0)
        }
    }

    access(all) fun createEmptyVault(vaultType: Type): @{FungibleToken.Vault} {
        let _ = vaultType
        return <- create Vault(balance: 0.0)
    }

    /// Mints a `Vault` with the given balance. Test-only — unrestricted minting.
    access(all) fun mint(amount: UFix64): @Vault {
        return <- create Vault(balance: amount)
    }

    access(all) view fun getContractViews(resourceType: Type?): [Type] {
        let _ = resourceType
        return []
    }
    access(all) fun resolveContractView(resourceType: Type?, viewType: Type): AnyStruct? {
        let _ = resourceType
        let _v = viewType
        return nil
    }
}
