import "FlowYieldVaults"

transaction(name: String) {

    let admin: &FlowYieldVaults.Admin

    prepare(signer: auth(BorrowValue) &Account) {
        self.admin = signer.storage.borrow<&FlowYieldVaults.Admin>(from: FlowYieldVaults.adminStoragePath)
            ?? panic("FlowYieldVaults.Admin not found at \(FlowYieldVaults.adminStoragePath)")
    }

    execute {
        let vault <- self.admin.createYieldVault(name: name)
        destroy vault
    }
}
