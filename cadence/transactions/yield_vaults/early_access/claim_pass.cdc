import "FlowYieldVaultsEarlyAccess"

/// Claims the most recently issued pass for the signer from the provider's inbox.
/// Use when you want to claim the latest pass without knowing its UUID; the UUID is
/// looked up automatically from `mostRecentIssuedPassUUID`.
///
/// **Parameters**
/// - `provider`: Address of the account that issued the pass.
/// - `path`: Storage path for the pass capability; defaults to
///   `passCapabilityStoragePath` if `nil`.
transaction(provider: Address, path: StoragePath?) {
    prepare(signer: auth(Storage, Inbox) &Account) {
        let passUUID = FlowYieldVaultsEarlyAccess.mostRecentIssuedPassUUID[signer.address]
            ?? panic("No pass issued to this address")
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
