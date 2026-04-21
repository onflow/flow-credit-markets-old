import Test

access(all) fun strategyCount(): UInt64 {
    let result = executeScript("cadence/scripts/yield_vaults/get_strategy_count.cdc", [])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! UInt64
}

access(all) fun strategyInfos(): {String: {String: String}} {
    let result = executeScript("cadence/scripts/yield_vaults/get_strategy_infos.cdc", [])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! {String: {String: String}}
}

access(all) fun registerMockStrategy(name: String, signer: Test.TestAccount): Test.TransactionResult {
    return executeTransaction("cadence/tests/transactions/yield_vaults/register_mock_strategy.cdc", [name], signer)
}

access(all) fun removeStrategy(name: String, signer: Test.TestAccount): Test.TransactionResult {
    return executeTransaction("cadence/tests/transactions/yield_vaults/remove_strategy.cdc", [name], signer)
}

access(all) fun createStrategyVault(name: String, signer: Test.TestAccount): Test.TransactionResult {
    return executeTransaction("cadence/tests/transactions/yield_vaults/create_strategy_vault.cdc", [name], signer)
}

access(all) fun createStrategyVaultAtPath(name: String, path: StoragePath, signer: Test.TestAccount): Test.TransactionResult {
    return executeTransaction(
        "cadence/tests/transactions/yield_vaults/create_strategy_vault_at_path.cdc",
        [name, path],
        signer
    )
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
