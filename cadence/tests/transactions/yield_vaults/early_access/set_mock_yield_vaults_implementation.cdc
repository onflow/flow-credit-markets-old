import "FlowYieldVaultsEarlyAccess"

transaction() {
    prepare(admin: auth(Storage) &Account) {
        let handle = admin.storage.borrow<&FlowYieldVaultsEarlyAccess.Admin>(
            from: FlowYieldVaultsEarlyAccess.adminStoragePath
        ) ?? panic("Admin not found")
        handle.setFlowYieldVaults(flowYieldVaultsName: "MockFlowYieldVaults")
    }
}
