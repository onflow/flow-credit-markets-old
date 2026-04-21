import Test

// PLACEHOLDER: wraps the stub count script used to verify CI script execution.
// Replace alongside scripts/actions/count.cdc once real state exists.
access(all) fun actionsCount(): Int {
    let result = executeScript("cadence/scripts/actions/count.cdc", [])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue as! Int
}

// PLACEHOLDER: wraps the stub increment transaction used to verify CI
// transaction execution. Replace alongside transactions/actions/increment.cdc
// once real mutations exist.
access(all) fun actionsIncrementCount(signer: Test.TestAccount) {
    let result = executeTransaction("cadence/tests/transactions/actions/increment.cdc", [], signer)
    Test.expect(result, Test.beSucceeded())
}

access(self) fun executeScript(_ path: String, _ args: [AnyStruct]): Test.ScriptResult {
    return Test.executeScript(Test.readFile(path), args)
}

access(self) fun executeTransaction(_ path: String, _ args: [AnyStruct], _ signer: Test.TestAccount): Test.TransactionResult {
    let txn = Test.Transaction(
        code: Test.readFile(path),
        authorizers: [signer.address],
        signers: [signer],
        arguments: args
    )
    return Test.executeTransaction(txn)
}
