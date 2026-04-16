import Test

// PLACEHOLDER: wraps the stub count script used to verify CI script execution.
// Replace alongside scripts/alp/count.cdc once real state exists.
access(all) fun alpCount(): Int {
    let result = _executeScript("../scripts/alp/count.cdc", [])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue as! Int
}

access(self) fun _executeScript(_ path: String, _ args: [AnyStruct]): Test.ScriptResult {
    return Test.executeScript(Test.readFile(path), args)
}

access(self) fun _executeTransaction(_ path: String, _ args: [AnyStruct], _ signer: Test.TestAccount): Test.TransactionResult {
    let txn = Test.Transaction(
        code: Test.readFile(path),
        authorizers: [signer.address],
        signers: [signer],
        arguments: args
    )
    return Test.executeTransaction(txn)
}
