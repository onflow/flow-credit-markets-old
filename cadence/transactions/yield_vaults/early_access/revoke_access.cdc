import "FlowYieldVaultsEarlyAccess"

/// Destroys the pass and attempts to retract the inbox capability.
/// If already claimed, the stored capability becomes invalid, blocking
/// future vault creation.
///
/// **Parameters**
/// - `passUUID`: UUID of the target pass.
transaction(passUUID: UInt64) {
    prepare(admin: auth(Storage) &Account) {
        let handle = admin.storage
            .borrow<&FlowYieldVaultsEarlyAccess.Admin>(from: FlowYieldVaultsEarlyAccess.adminStoragePath)
            ?? panic("Could not borrow Admin")
        handle.revokePass(passUUID: passUUID)
    }
}
