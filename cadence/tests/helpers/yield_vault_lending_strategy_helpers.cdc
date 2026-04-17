import Test

access(all) fun createLendingStrategy(name: String, signer: Test.TestAccount): Test.TransactionResult {
    return executeTransaction(
        "cadence/tests/transactions/yield_vaults/create_mock_lending_strategy.cdc",
        [name],
        signer
    )
}

access(all) fun createAndSaveYieldVault(name: String, path: StoragePath, signer: Test.TestAccount): Test.TransactionResult {
    return executeTransaction(
        "cadence/tests/transactions/yield_vaults/create_and_save_yield_vault.cdc",
        [name, path],
        signer
    )
}

access(all) fun depositToYieldVault(path: StoragePath, amount: UFix64, signer: Test.TestAccount): Test.TransactionResult {
    return executeTransaction(
        "cadence/tests/transactions/yield_vaults/deposit_to_yield_vault.cdc",
        [path, amount],
        signer
    )
}

access(all) fun withdrawFromYieldVault(path: StoragePath, amount: UFix64, signer: Test.TestAccount): Test.TransactionResult {
    return executeTransaction(
        "cadence/tests/transactions/yield_vaults/withdraw_from_yield_vault.cdc",
        [path, amount],
        signer
    )
}

access(self) fun executeTransaction(_ path: String, _ args: [AnyStruct], _ signer: Test.TestAccount): Test.TransactionResult {
    return Test.executeTransaction(Test.Transaction(
        code: Test.readFile(path),
        authorizers: [signer.address],
        signers: [signer],
        arguments: args
    ))
}
