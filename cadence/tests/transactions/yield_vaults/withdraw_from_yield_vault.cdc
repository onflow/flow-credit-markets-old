import "FungibleToken"

transaction(path: StoragePath, amount: UFix64) {
    prepare(signer: auth(BorrowValue) &Account) {
        let vault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Provider}>(from: path)
            ?? panic("YieldVault not found at \(path)")
        let out <- vault.withdraw(amount: amount)
        destroy out
    }
}
