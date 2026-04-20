import "FlowYieldVaults"

/// Gates yield vault creation during the early access period.
/// An `Admin` resource issues and manages `EarlyAccessPass` resources.
/// Pass holders call `createYieldVault` to create yield vaults
/// until their allowance is exhausted.
access(all) contract FlowYieldVaultsEarlyAccess {

    /// Emitted when a new pass is issued to an address.
    access(all) event PassIssued(passUUID: UInt64, addr: Address, allowance: UInt64)
    /// Emitted when a pass is revoked and destroyed by the admin.
    access(all) event PassRevoked(passUUID: UInt64)
    /// Emitted when a pass is used to create a yield vault.
    access(all) event PassUsed(passUUID: UInt64, remainingAllowance: UInt64)

    /// Storage path where the `Admin` resource is saved.
    access(all) let adminStoragePath: StoragePath
    /// Storage path where pass capabilities are stored for claiming.
    access(all) let passCapabilityStoragePath: StoragePath
    /// Tracks the UUID of the last pass issued to each address;
    /// used by the address-based claim transaction.
    access(all) var mostRecentIssuedPassUUID: {Address: UInt64}

    /// Held in the holder's storage; gates yield vault creation during early access.
    access(all) resource EarlyAccessPass {
        /// Number of yield vaults the holder may still create.
        access(all) var remainingAllowance: UInt64

        /// Consumes one unit of allowance and creates a new yield vault.
        /// Panics if allowance is exhausted.
        ///
        /// **Parameters**
        /// - `strategyID`: Identifies the vault strategy to create.
        ///
        /// **Returns** A new `YieldVault` to be saved in the caller's storage.
        access(all) fun createYieldVault(strategyID: UInt64): @FlowYieldVaults.YieldVault {
            pre { self.remainingAllowance > 0: "No remaining allowance" }
            self.remainingAllowance = self.remainingAllowance - 1
            let vault <- FlowYieldVaults.createYieldVault(strategyID: strategyID)
            emit PassUsed(passUUID: self.uuid, remainingAllowance: self.remainingAllowance)
            return <- vault
        }

        access(contract) fun setAllowance(_ newAllowance: UInt64) {
            self.remainingAllowance = newAllowance
        }

        init(allowance: UInt64) {
            self.remainingAllowance = allowance
        }
    }

    access(all) resource Admin {
        /// Issues a pass to `addr`, publishes the capability to their inbox,
        /// and records it as their most recently issued pass
        /// (used by the address-based claim transaction).
        ///
        /// **Parameters**
        /// - `addr`: Recipient who will claim the pass from their inbox.
        /// - `allowance`: Number of yield vaults the pass holder may create.
        ///
        /// **Returns** The UUID of the newly created pass.
        access(all) fun issuePass(to addr: Address, allowance: UInt64): UInt64 {
            let pass <- create EarlyAccessPass(allowance: allowance)
            let passUUID = FlowYieldVaultsEarlyAccess.storePass(pass: <- pass)
            FlowYieldVaultsEarlyAccess.publishPassCapability(passUUID: passUUID, addr: addr)
            FlowYieldVaultsEarlyAccess.mostRecentIssuedPassUUID[addr] = passUUID
            emit PassIssued(passUUID: passUUID, addr: addr, allowance: allowance)
            return passUUID
        }

        /// Destroys the pass and attempts to retract the inbox capability.
        /// Panics if the pass is not found. If already claimed, the capability
        /// stays in the recipient's storage but becomes unborrow-able,
        /// blocking future vault creation.
        ///
        /// **Parameters**
        /// - `passUUID`: UUID of the target pass.
        access(all) fun revokePass(passUUID: UInt64) {
            let pass <- FlowYieldVaultsEarlyAccess.loadPass(passUUID: passUUID)
            destroy pass
            FlowYieldVaultsEarlyAccess.unpublishPassCapability(passUUID: passUUID)
            emit PassRevoked(passUUID: passUUID)
        }

        /// Replaces the remaining allowance on an existing pass.
        /// Panics if the pass is not found.
        ///
        /// **Parameters**
        /// - `passUUID`: UUID of the target pass.
        /// - `newAllowance`: New vault budget; `0` immediately blocks creation.
        access(all) fun setAllowance(passUUID: UInt64, newAllowance: UInt64) {
            let pass = FlowYieldVaultsEarlyAccess.borrowPass(passUUID: passUUID)
            pass.setAllowance(newAllowance)
        }

    }

    /// Returns whether a pass with the given UUID currently exists in storage.
    ///
    /// **Parameters**
    /// - `passUUID`: UUID of the target pass.
    ///
    /// **Returns** `true` if the pass exists, `false` otherwise.
    view access(all) fun passExists(passUUID: UInt64): Bool {
        return self.checkPass(passUUID: passUUID)
    }

    /// Returns the remaining allowance of the pass with the given UUID.
    /// Panics if the pass is not found.
    ///
    /// **Parameters**
    /// - `passUUID`: UUID of the target pass.
    ///
    /// **Returns** Number of yield vaults the pass holder may still create.
    view access(all) fun remainingAllowance(passUUID: UInt64): UInt64 {
        let pass = self.borrowPass(passUUID: passUUID)
        return pass.remainingAllowance
    }

    /// Returns the inbox key used to publish and claim a pass capability.
    ///
    /// **Parameters**
    /// - `passUUID`: UUID of the target pass.
    ///
    /// **Returns** The inbox key string for the given pass.
    view access(all) fun inboxName(passUUID: UInt64): String {
        return "EarlyAccessPass_\(passUUID)"
    }

    access(self) fun storePass(pass: @EarlyAccessPass): UInt64 {
        let uuid = pass.uuid
        self.account.storage.save(<- pass, to: FlowYieldVaultsEarlyAccess.passStoragePath(passUUID: uuid))
        return uuid
    }

    access(self) fun loadPass(passUUID: UInt64): @EarlyAccessPass {
        return <- (self.account.storage.load<@EarlyAccessPass>(from: self.passStoragePath(passUUID: passUUID)) ?? panic("Pass not found"))
    }

    view access(self) fun checkPass(passUUID: UInt64): Bool {
        return self.account.storage.check<@EarlyAccessPass>(from: self.passStoragePath(passUUID: passUUID))
    }

    view access(self) fun borrowPass(passUUID: UInt64): &EarlyAccessPass {
        return self.account.storage.borrow<&EarlyAccessPass>(from: self.passStoragePath(passUUID: passUUID)) ?? panic("Pass not found")
    }

    access(self) fun publishPassCapability(passUUID: UInt64, addr: Address) {
        let capability = self.account.capabilities.storage.issue<&EarlyAccessPass>(self.passStoragePath(passUUID: passUUID))
        self.account.inbox.publish(capability, name: self.inboxName(passUUID: passUUID), recipient: addr)
    }

    access(self) fun unpublishPassCapability(passUUID: UInt64) {
        let _ = self.account.inbox.unpublish<&EarlyAccessPass>(self.inboxName(passUUID: passUUID))
    }

    view access(self) fun passStoragePath(passUUID: UInt64): StoragePath {
        return StoragePath(identifier: "FlowYieldVaultsEarlyAccessPass_\(passUUID)")!
    }

    init() {
        self.adminStoragePath = StoragePath(identifier: "FlowYieldVaultsEarlyAccessAdmin")!
        self.passCapabilityStoragePath = StoragePath(identifier: "FlowYieldVaultsEarlyAccessPassCapability")!
        self.mostRecentIssuedPassUUID = {}
        self.account.storage.save(<- create Admin(), to: self.adminStoragePath)
    }
}
