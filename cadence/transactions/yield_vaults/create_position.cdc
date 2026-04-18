import "FlowYieldVaultsEarlyAccess"
import "FlowYieldVaultsInterfaces"

/// Creates a new yield vault using the signer's early access pass.
/// Panics if no valid pass capability is found or the pass allowance is exhausted.
///
/// **Parameters**
/// - `strategyID`: Identifies the vault strategy to create a vault for.
/// - `earlyAccessPath`: Storage path of the pass capability; defaults to
///   `FlowYieldVaultsEarlyAccess.passCapabilityStoragePath` when `nil`.
/// - `vaultPath`: Storage path where the new `YieldVault` will be saved.
transaction(strategyID: UInt64, earlyAccessPath: StoragePath?, vaultPath: StoragePath) {
    prepare(signer: auth(Storage) &Account) {
        let earlyAccessPath = earlyAccessPath ?? FlowYieldVaultsEarlyAccess.passCapabilityStoragePath
        let capability = signer.storage.copy<Capability<&FlowYieldVaultsEarlyAccess.EarlyAccessPass>>(
            from: earlyAccessPath
        ) ?? panic("No valid early access pass")
        let pass = capability.borrow() ?? panic("No valid early access pass")
        let vault <- pass.createYieldVault(strategyID: strategyID)
        signer.storage.save(<- vault, to: vaultPath)
    }
}
