import "FlowYieldVaults"

access(all) contract FlowYieldVaultsEarlyAccess {

    access(all) event AccessGranted(addr: Address)
    access(all) event AccessRevoked(addr: Address)

    access(all) var allowlist: {Address: Bool}
    access(all) let adminStoragePath: StoragePath

    access(all) resource AdminHandle {
        access(all) fun grantAccess(to addr: Address) {
            if FlowYieldVaultsEarlyAccess.allowlist[addr] != true {
                emit AccessGranted(addr: addr)
            }
            FlowYieldVaultsEarlyAccess.allowlist[addr] = true
        }

        access(all) fun revokeAccess(from addr: Address) {
            if FlowYieldVaultsEarlyAccess.allowlist[addr] == true {
                emit AccessRevoked(addr: addr)
            }
            let _ = FlowYieldVaultsEarlyAccess.allowlist.remove(key: addr)
        }
    }

    access(all) resource EarlyAccessPosition {
        access(all) var position: @FlowYieldVaults.Position

        access(all) fun withdraw(signer: &Account) {
            pre {
                FlowYieldVaultsEarlyAccess.isAllowed(signer: signer): "Signer is not in the allowlist"
            }
            self.position.withdraw()
        }

        access(all) fun deposit(signer: &Account) {
            pre {
                FlowYieldVaultsEarlyAccess.isAllowed(signer: signer): "Signer is not in the allowlist"
            }
            self.position.deposit()
        }

        init() {
            self.position <- FlowYieldVaults.createPosition()
        }
    }

    access(all) fun createPosition(signer: &Account): @EarlyAccessPosition {
        pre {
            self.isAllowed(signer: signer): "Signer is not in the allowlist"
        }
        return <- create EarlyAccessPosition()
    }

    view access(self) fun isAllowed(signer: &Account): Bool {
        return self.allowlist[signer.address] == true
    }

    init() {
        self.allowlist = {}
        self.adminStoragePath = /storage/FlowYieldVaultsEarlyAccessAdmin
        self.account.storage.save(<- create AdminHandle(), to: self.adminStoragePath)
    }
}
