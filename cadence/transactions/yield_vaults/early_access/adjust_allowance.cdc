import "FlowYieldVaultsEarlyAccess"

/// Replaces the remaining allowance on the pass issued to `addr`.
/// Setting `newAllowance` to `0` immediately blocks further vault creation.
///
/// **Parameters**
/// - `addr`: Recipient whose pass allowance should be updated.
/// - `newAllowance`: New vault budget; may be lower or higher than the current value.
transaction(addr: Address, newAllowance: UInt64) {
    prepare(admin: auth(Storage) &Account) {
        let handle = admin.storage
            .borrow<&FlowYieldVaultsEarlyAccess.Admin>(from: FlowYieldVaultsEarlyAccess.adminStoragePath)
            ?? panic("Could not borrow Admin")
        handle.setAllowance(addr: addr, newAllowance: newAllowance)
    }
}
