import "FlowYieldVaultsEarlyAccess"

transaction(addr: Address) {
    prepare(admin: auth(Storage) &Account) {
        let handle = admin.storage
            .borrow<&FlowYieldVaultsEarlyAccess.AdminHandle>(
                from: FlowYieldVaultsEarlyAccess.adminStoragePath
            ) ?? panic("Could not borrow AdminHandle")
        handle.revokeAccess(from: addr)
    }
}
