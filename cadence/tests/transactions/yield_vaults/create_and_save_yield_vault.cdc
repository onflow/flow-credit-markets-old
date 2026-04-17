import "FlowYieldVaults"

transaction(name: String, path: StoragePath) {
    prepare(signer: auth(BorrowValue, SaveValue) &Account) {
        let admin = signer.storage.borrow<&FlowYieldVaults.Admin>(from: FlowYieldVaults.adminStoragePath)
            ?? panic("FlowYieldVaults.Admin not found at \(FlowYieldVaults.adminStoragePath)")
        let vault <- admin.createYieldVault(name: name)
        signer.storage.save(<- vault, to: path)
    }
}
