import "FlowYieldVaultsEarlyAccess"

// Claim an EarlyAccessPosition capability from inbox and immediately try to use it.
// The deposit call will fail if the signer is not in the allowlist.
transaction(provider: Address) {
    prepare(signer: auth(Inbox) &Account) {
        let cap = signer.inbox.claim<&FlowYieldVaultsEarlyAccess.EarlyAccessPosition>(
            "EarlyAccessPosition",
            provider: provider
        ) ?? panic("No EarlyAccessPosition found in inbox")
        let pos = cap.borrow() ?? panic("Capability invalid")
        pos.deposit(signer: signer)
    }
}
