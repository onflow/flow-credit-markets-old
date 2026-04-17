import "FlowYieldVaultsEarlyAccess"

transaction(recipient: Address) {
    prepare(signer: auth(Storage, Capabilities, Inbox) &Account) {
        let cap = signer.capabilities.storage.issue<&FlowYieldVaultsEarlyAccess.EarlyAccessPosition>(
            /storage/FlowYieldVaultsEarlyAccessPosition
        )
        signer.inbox.publish(cap, name: "EarlyAccessPosition", recipient: recipient)
    }
}
