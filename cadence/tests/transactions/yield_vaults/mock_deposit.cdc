import "FlowYieldVaultsInterfaces"

/// Deposits into the strategy vault stored at `path`.
/// Panics if no `YieldVault` is found at the given path.
///
/// **Parameters**
/// - `path`: Storage path of the `YieldVault` to deposit into.
transaction(path: StoragePath) {
    prepare(signer: auth(Storage) &Account) {
        let _ = signer.storage.borrow<&{FlowYieldVaultsInterfaces.YieldVault}>(from: path)
            ?? panic("No YieldVault found at path")
    }
}
