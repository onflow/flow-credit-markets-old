import "FlowYieldVaultsEarlyAccess"

/// Claims the pass issued to the signer from the provider's inbox and
/// saves the capability into the signer's storage.
///
/// **Parameters**
/// - `provider`: Address of the account that issued the pass.
/// - `path`: Storage path for the pass capability; defaults to
///   `passCapabilityStoragePath` if `nil`.
transaction(provider: Address, path: StoragePath?) {
    prepare(signer: auth(Storage, Inbox) &Account) {
        var storagePath = FlowYieldVaultsEarlyAccess.passCapabilityStoragePath
        if let p = path {
            storagePath = p
        }
        let _ = signer.storage.load<Capability<&FlowYieldVaultsEarlyAccess.EarlyAccessPass>>(from: storagePath)
        let capability = signer.inbox.claim<&FlowYieldVaultsEarlyAccess.EarlyAccessPass>(
            FlowYieldVaultsEarlyAccess.inboxName(addr: signer.address),
            provider: provider
        ) ?? panic("No pass found in inbox")
        signer.storage.save(capability, to: storagePath)
    }
}
