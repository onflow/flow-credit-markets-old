import "FlowYieldVaultsEarlyAccess"

/// Replaces the remaining allowance on an existing pass.
/// Setting `newAllowance` to `0` immediately blocks further vault creation.
///
/// **Parameters**
/// - `passUUID`: UUID of the target pass.
/// - `newAllowance`: New vault budget; may be lower or higher than the current value.
transaction(passUUID: UInt64, newAllowance: UInt64) {
    prepare(admin: auth(Storage) &Account) {
        let handle = admin.storage
            .borrow<&FlowYieldVaultsEarlyAccess.Admin>(from: FlowYieldVaultsEarlyAccess.adminStoragePath)
            ?? panic("Could not borrow Admin")
        handle.setAllowance(passUUID: passUUID, newAllowance: newAllowance)
    }
}
