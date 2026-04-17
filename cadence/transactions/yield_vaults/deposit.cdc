import "FlowYieldVaultsEarlyAccess"

transaction(path: StoragePath) {
    prepare(signer: auth(Storage) &Account) {
        let pos = signer.storage.borrow<&FlowYieldVaultsEarlyAccess.EarlyAccessPosition>(
            from: path
        ) ?? panic("No EarlyAccessPosition in storage")
        pos.deposit(signer: signer)
    }
}
