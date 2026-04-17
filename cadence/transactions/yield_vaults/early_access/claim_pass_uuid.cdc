import "FlowYieldVaultsEarlyAccess"

/// Claims a specific pass by UUID from the provider's inbox.
/// Use when claiming a pass that is not the most recently issued one,
/// e.g. when multiple passes have been issued to the same address.
///
/// **Parameters**
/// - `passUUID`: UUID of the target pass.
/// - `provider`: Address of the account that issued the pass.
/// - `path`: Storage path for the pass capability; defaults to
///   `passCapabilityStoragePath` if `nil`.
transaction(passUUID: UInt64, provider: Address, path: StoragePath?) {
    prepare(signer: auth(Storage, Inbox) &Account) {
        var storagePath = FlowYieldVaultsEarlyAccess.passCapabilityStoragePath
        if let p = path {
            storagePath = p
        }
        let _ = signer.storage.load<Capability<&FlowYieldVaultsEarlyAccess.EarlyAccessPass>>(from: storagePath)
        let cap = signer.inbox.claim<&FlowYieldVaultsEarlyAccess.EarlyAccessPass>(
            FlowYieldVaultsEarlyAccess.inboxName(passUUID: passUUID),
            provider: provider
        ) ?? panic("No pass found in inbox")
        signer.storage.save(cap, to: storagePath)
    }
}
