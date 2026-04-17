import Test

access(all) fun revokeEarlyAccess(admin: Test.TestAccount, addr: Address) {
    let result = executeTransaction(
        "../transactions/yield_vaults/early_access/revoke_access.cdc",
        [addr],
        admin
    )
    Test.expect(result, Test.beSucceeded())
}

access(all) fun createPosition(signer: Test.TestAccount, path: StoragePath): Test.TransactionResult {
    return executeTransaction(
        "../transactions/yield_vaults/create_position.cdc",
        [path],
        signer
    )
}

access(all) fun deposit(signer: Test.TestAccount): Test.TransactionResult {
    return executeTransaction(
        "../transactions/yield_vaults/deposit.cdc",
        [/storage/FlowYieldVaultsEarlyAccessPosition],
        signer
    )
}

access(all) fun transferPositionToInbox(signer: Test.TestAccount, recipient: Address): Test.TransactionResult {
    return executeTransaction(
        "transactions/yield_vaults/transfer_position_to_inbox.cdc",
        [recipient],
        signer
    )
}

access(all) fun claimPositionAndDeposit(signer: Test.TestAccount, provider: Address): Test.TransactionResult {
    return executeTransaction(
        "transactions/yield_vaults/claim_position_and_deposit.cdc",
        [provider],
        signer
    )
}

access(all) fun hasEarlyAccess(_ addr: Address): Bool {
    let result = executeScript("../scripts/yield_vaults/has_early_access.cdc", [addr])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! Bool
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
