import Test
import "FlowYieldVaultsEarlyAccess"

access(all) fun setYieldVaultsImpl(admin: Test.TestAccount, txPath: String): Test.TransactionResult {
    return executeTransaction(txPath, [], admin)
}

access(all) fun grantEarlyAccess(admin: Test.TestAccount, user: Test.TestAccount, allowance: UInt64): UInt64 {
    let result = executeTransaction(
        "cadence/transactions/yield_vaults/early_access/grant_access.cdc",
        [user.address, allowance],
        admin
    )
    Test.expect(result, Test.beSucceeded())
    let events = Test.eventsOfType(Type<FlowYieldVaultsEarlyAccess.PassIssued>())
    return (events[events.length - 1] as! FlowYieldVaultsEarlyAccess.PassIssued).passUUID
}

access(all) fun claimPass(user: Test.TestAccount, passUUID: UInt64, provider: Address): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/early_access/claim_pass_uuid.cdc",
        [passUUID, provider, nil],
        user
    )
}

access(all) fun claimPassWithPath(user: Test.TestAccount, passUUID: UInt64, provider: Address, path: StoragePath): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/early_access/claim_pass_uuid.cdc",
        [passUUID, provider, path],
        user
    )
}

access(all) fun claimPassByAddress(user: Test.TestAccount, provider: Address): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/early_access/claim_pass.cdc",
        [provider, nil],
        user
    )
}

access(all) fun revokeEarlyAccess(admin: Test.TestAccount, passUUID: UInt64): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/early_access/revoke_access.cdc",
        [passUUID],
        admin
    )
}

access(all) fun setAllowance(admin: Test.TestAccount, passUUID: UInt64, newAllowance: UInt64): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/early_access/adjust_allowance.cdc",
        [passUUID, newAllowance],
        admin
    )
}

access(all) fun createYieldVault(signer: Test.TestAccount, strategyID: UInt64, path: StoragePath): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/create_position.cdc",
        [strategyID, nil, path],
        signer
    )
}

access(all) fun createYieldVaultAtEarlyAccessPath(signer: Test.TestAccount, strategyID: UInt64, earlyAccessPath: StoragePath, vaultPath: StoragePath): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/create_position.cdc",
        [strategyID, earlyAccessPath, vaultPath],
        signer
    )
}

access(all) fun deposit(signer: Test.TestAccount, path: StoragePath): Test.TransactionResult {
    return executeTransaction(
        "cadence/tests/transactions/yield_vaults/mock_deposit.cdc",
        [path],
        signer
    )
}

access(all) fun hasEarlyAccess(_ passUUID: UInt64): Bool {
    let result = executeScript("cadence/scripts/yield_vaults/early_access/has_early_access.cdc", [passUUID])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! Bool
}

access(all) fun remainingAllowance(_ passUUID: UInt64): UInt64 {
    let result = executeScript("cadence/scripts/yield_vaults/early_access/remaining_allowance.cdc", [passUUID])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! UInt64
}

access(self) fun executeScript(_ path: String, _ args: [AnyStruct]): Test.ScriptResult {
    return Test.executeScript(Test.readFile(path), args)
}

access(self) fun executeTransaction(_ path: String, _ args: [AnyStruct], _ signer: Test.TestAccount): Test.TransactionResult {
    return Test.executeTransaction(Test.Transaction(
        code: Test.readFile(path),
        authorizers: [signer.address],
        signers: [signer],
        arguments: args
    ))
}
