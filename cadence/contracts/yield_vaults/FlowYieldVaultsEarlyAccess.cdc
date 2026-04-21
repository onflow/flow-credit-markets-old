import "FlowYieldVaults"
import "FlowYieldVaultsInterfaces"

/// Gates yield vault creation during the early access period.
/// An `Admin` resource issues and manages `EarlyAccessPass` resources,
/// keyed by recipient address: each address has at most one pass.
/// Pass holders call `createYieldVault` to create yield vaults
/// until their allowance is exhausted.
access(all) contract FlowYieldVaultsEarlyAccess {

    /// Emitted when a pass is issued (or re-issued) to an address.
    access(all) event PassIssued(addr: Address, allowance: UInt64)
    /// Emitted when a pass is revoked and destroyed by the admin.
    access(all) event PassRevoked(addr: Address)
    /// Emitted when a pass is used to create a yield vault.
    access(all) event PassUsed(addr: Address, remainingAllowance: UInt64)

    /// Storage path where the `Admin` resource is saved.
    access(all) let adminStoragePath: StoragePath
    /// Storage path where pass capabilities are stored for claiming.
    access(all) let passCapabilityStoragePath: StoragePath

    /// Held in the holder's storage; gates yield vault creation during early access.
    access(all) resource EarlyAccessPass {
        /// Address this pass was issued to; stamped at creation and never changes.
        access(all) let addr: Address
        /// Number of yield vaults the holder may still create.
        access(all) var remainingAllowance: UInt64

        /// Consumes one unit of allowance and creates a new yield vault.
        /// Panics if allowance is exhausted.
        ///
        /// **Parameters**
        /// - `name`: Name of the registered strategy to create a vault for.
        ///
        /// **Returns** A new `YieldVault` to be saved in the caller's storage.
        access(all) fun createYieldVault(name: String): @{FlowYieldVaultsInterfaces.YieldVault} {
            pre { self.remainingAllowance > 0: "No remaining allowance" }
            self.remainingAllowance = self.remainingAllowance - 1
            let vault <- FlowYieldVaults.createYieldVault(name: name)
            emit PassUsed(addr: self.addr, remainingAllowance: self.remainingAllowance)
            return <- vault
        }

        access(contract) fun setAllowance(_ newAllowance: UInt64) {
            self.remainingAllowance = newAllowance
        }

        init(addr: Address, allowance: UInt64) {
            self.addr = addr
            self.remainingAllowance = allowance
        }
    }

    access(all) resource Admin {
        /// Issues a pass to `addr` and publishes the capability to their inbox.
        /// If a pass already exists for `addr`, its `remainingAllowance` is
        /// replaced with the new `allowance`, and any previously issued
        /// capabilities for that pass are invalidated.
        ///
        /// **Parameters**
        /// - `addr`: Recipient who will claim the pass from their inbox.
        /// - `allowance`: Number of yield vaults the pass holder may create.
        access(all) fun issuePass(to addr: Address, allowance: UInt64) {
            let path = FlowYieldVaultsEarlyAccess.passStoragePath(addr: addr)
            if FlowYieldVaultsEarlyAccess.checkPass(addr: addr) {
                let pass = FlowYieldVaultsEarlyAccess.borrowPass(addr: addr)
                pass.setAllowance(allowance)
                FlowYieldVaultsEarlyAccess.deletePassCapabilities(addr: addr)
            } else {
                let pass <- create EarlyAccessPass(addr: addr, allowance: allowance)
                FlowYieldVaultsEarlyAccess.account.storage.save(<- pass, to: path)
            }
            FlowYieldVaultsEarlyAccess.publishPassCapability(addr: addr)
            emit PassIssued(addr: addr, allowance: allowance)
        }

        /// Destroys the pass, deletes its capability controllers, and retracts
        /// the inbox entry if still unclaimed. Panics if no pass exists for `addr`.
        /// Any previously claimed capability becomes dead (`borrow()` returns `nil`).
        ///
        /// **Parameters**
        /// - `addr`: Recipient whose pass should be revoked.
        access(all) fun revokePass(addr: Address) {
            let pass <- FlowYieldVaultsEarlyAccess.loadPass(addr: addr)
            destroy pass
            FlowYieldVaultsEarlyAccess.deletePassCapabilities(addr: addr)
            FlowYieldVaultsEarlyAccess.unpublishPassCapability(addr: addr)
            emit PassRevoked(addr: addr)
        }

        /// Replaces the remaining allowance on an existing pass.
        /// Panics if no pass exists for `addr`.
        ///
        /// **Parameters**
        /// - `addr`: Recipient whose pass allowance should be updated.
        /// - `newAllowance`: New vault budget; `0` immediately blocks creation.
        access(all) fun setAllowance(addr: Address, newAllowance: UInt64) {
            let pass = FlowYieldVaultsEarlyAccess.borrowPass(addr: addr)
            pass.setAllowance(newAllowance)
        }

    }

    /// Returns whether a pass is currently held for the given address.
    ///
    /// **Parameters**
    /// - `addr`: Recipient to check.
    ///
    /// **Returns** `true` if a pass exists for `addr`, `false` otherwise.
    view access(all) fun passExists(addr: Address): Bool {
        return self.checkPass(addr: addr)
    }

    /// Returns the remaining allowance of the pass issued to `addr`.
    /// Panics if no pass exists for `addr`.
    ///
    /// **Parameters**
    /// - `addr`: Recipient whose pass to query.
    ///
    /// **Returns** Number of yield vaults the pass holder may still create.
    view access(all) fun remainingAllowance(addr: Address): UInt64 {
        let pass = self.borrowPass(addr: addr)
        return pass.remainingAllowance
    }

    /// Returns the inbox key used to publish and claim a pass capability
    /// for the given address.
    ///
    /// **Parameters**
    /// - `addr`: Recipient whose inbox entry name to compute.
    ///
    /// **Returns** The inbox key string for the given address.
    view access(all) fun inboxName(addr: Address): String {
        return "EarlyAccessPass_\(addr.toString())"
    }

    access(self) fun loadPass(addr: Address): @EarlyAccessPass {
        return <- (self.account.storage.load<@EarlyAccessPass>(from: self.passStoragePath(addr: addr)) ?? panic("Pass not found"))
    }

    view access(self) fun checkPass(addr: Address): Bool {
        return self.account.storage.check<@EarlyAccessPass>(from: self.passStoragePath(addr: addr))
    }

    view access(self) fun borrowPass(addr: Address): &EarlyAccessPass {
        return self.account.storage.borrow<&EarlyAccessPass>(from: self.passStoragePath(addr: addr)) ?? panic("Pass not found")
    }

    access(self) fun publishPassCapability(addr: Address) {
        let capability = self.account.capabilities.storage.issue<&EarlyAccessPass>(self.passStoragePath(addr: addr))
        self.account.inbox.publish(capability, name: self.inboxName(addr: addr), recipient: addr)
    }

    access(self) fun unpublishPassCapability(addr: Address) {
        let _ = self.account.inbox.unpublish<&EarlyAccessPass>(self.inboxName(addr: addr))
    }

    access(self) fun deletePassCapabilities(addr: Address) {
        let controllers = self.account.capabilities.storage.getControllers(forPath: self.passStoragePath(addr: addr))
        for controller in controllers {
            controller.delete()
        }
    }

    view access(self) fun passStoragePath(addr: Address): StoragePath {
        return StoragePath(identifier: "FlowYieldVaultsEarlyAccessPass_\(addr.toString())")!
    }

    init() {
        self.adminStoragePath = StoragePath(identifier: "FlowYieldVaultsEarlyAccessAdmin")!
        self.passCapabilityStoragePath = StoragePath(identifier: "FlowYieldVaultsEarlyAccessPassCapability")!
        self.account.storage.save(<- create Admin(), to: self.adminStoragePath)
    }
}
