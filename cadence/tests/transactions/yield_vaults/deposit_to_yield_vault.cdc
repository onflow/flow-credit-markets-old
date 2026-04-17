import "FungibleToken"
import "MockToken"

transaction(path: StoragePath, amount: UFix64) {
    prepare(signer: auth(BorrowValue) &Account) {
        let vault = signer.storage.borrow<&{FungibleToken.Receiver}>(from: path)
            ?? panic("YieldVault not found at \(path)")
        let tokens <- MockToken.mint(amount: amount)
        vault.deposit(from: <- tokens)
    }
}
