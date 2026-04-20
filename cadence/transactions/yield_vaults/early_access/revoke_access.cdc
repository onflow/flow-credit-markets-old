import "FlowYieldVaultsEarlyAccess"

/// Destroys the pass for `addr`, deletes its capability controllers
/// (invalidating any held capability), and retracts the inbox entry
/// if still unclaimed.
///
/// **Parameters**
/// - `addr`: Recipient whose pass should be revoked.
transaction(addr: Address) {
    prepare(admin: auth(Storage) &Account) {
        let handle = admin.storage
            .borrow<&FlowYieldVaultsEarlyAccess.Admin>(from: FlowYieldVaultsEarlyAccess.adminStoragePath)
            ?? panic("Could not borrow Admin")
        handle.revokePass(addr: addr)
    }
}
