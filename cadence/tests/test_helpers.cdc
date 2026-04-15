import Test

access(all) fun _executeScript(_ path: String, _ args: [AnyStruct]): Test.ScriptResult {
    return Test.executeScript(Test.readFile(path), args)
}

access(all) fun _executeTransaction(_ path: String, _ args: [AnyStruct], _ signer: Test.TestAccount): Test.TransactionResult {
    let txn = Test.Transaction(
        code: Test.readFile(path),
        authorizers: [signer.address],
        signers: [signer],
        arguments: args
    )
    return Test.executeTransaction(txn)
}

access(all) fun actionsCount(): Int {
    let result = _executeScript("../scripts/fyv/count.cdc", [])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue as! Int
}

access(all) fun incrementFYVCount(amount: Int, signer: Test.TestAccount) {
    let result = _executeTransaction("transactions/fyv/count.cdc", [amount], signer)
    Test.expect(result, Test.beSucceeded())
}