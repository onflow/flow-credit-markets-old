import "FlowYieldVaultsEarlyAccess"

/// Issues an early access pass to `addr` and publishes the capability to their inbox.
/// If a pass already exists for `addr`, its allowance is replaced and any
/// previously issued capabilities are invalidated.
///
/// **Parameters**
/// - `addr`: Recipient address to issue the pass to.
/// - `allowance`: Number of yield vaults the pass holder may create.
transaction(addr: Address, allowance: UInt64) {
    prepare(admin: auth(Storage) &Account) {
        let handle = admin.storage
            .borrow<&FlowYieldVaultsEarlyAccess.Admin>(from: FlowYieldVaultsEarlyAccess.adminStoragePath)
            ?? panic("Could not borrow Admin")
        handle.issuePass(to: addr, allowance: allowance)
    }
}
