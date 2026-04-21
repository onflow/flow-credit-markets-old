import Test

access(all) fun grantEarlyAccess(admin: Test.TestAccount, user: Test.TestAccount, allowance: UInt64): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/early_access/grant_access.cdc",
        [user.address, allowance],
        admin
    )
}

access(all) fun claimPass(user: Test.TestAccount, provider: Address): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/early_access/claim_pass.cdc",
        [provider, nil],
        user
    )
}

access(all) fun claimPassWithPath(user: Test.TestAccount, provider: Address, path: StoragePath): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/early_access/claim_pass.cdc",
        [provider, path],
        user
    )
}

access(all) fun revokeEarlyAccess(admin: Test.TestAccount, addr: Address): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/early_access/revoke_access.cdc",
        [addr],
        admin
    )
}

access(all) fun setAllowance(admin: Test.TestAccount, addr: Address, newAllowance: UInt64): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/early_access/adjust_allowance.cdc",
        [addr, newAllowance],
        admin
    )
}

access(all) fun createYieldVault(signer: Test.TestAccount, name: String, path: StoragePath): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/create_position.cdc",
        [name, nil, path],
        signer
    )
}

access(all) fun createYieldVaultAtEarlyAccessPath(signer: Test.TestAccount, name: String, earlyAccessPath: StoragePath, vaultPath: StoragePath): Test.TransactionResult {
    return executeTransaction(
        "cadence/transactions/yield_vaults/create_position.cdc",
        [name, earlyAccessPath, vaultPath],
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

access(all) fun hasEarlyAccess(_ addr: Address): Bool {
    let result = executeScript("cadence/scripts/yield_vaults/early_access/has_early_access.cdc", [addr])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! Bool
}

access(all) fun remainingAllowance(_ addr: Address): UInt64 {
    let result = executeScript("cadence/scripts/yield_vaults/early_access/remaining_allowance.cdc", [addr])
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
