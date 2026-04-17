import "FlowYieldVaultsEarlyAccess"

transaction(path: StoragePath) {
    // Two fields are intentional: createPosition requires &Account (non-auth) for the allowlist
    // check, while saving requires auth(Storage). Both must be captured in prepare since
    // auth capabilities cannot be obtained outside of that phase.
    let signer: &Account
    let signerStorage: auth(Storage) &Account

    prepare(signer: auth(Storage) &Account) {
        self.signer = signer
        self.signerStorage = signer
    }

    execute {
        let pm <- FlowYieldVaultsEarlyAccess.createPosition(signer: self.signer)
        self.signerStorage.storage.save(<-pm, to: path)
    }
}
