import Test

access(all)
fun deployContracts() {
    var err = Test.deployContract(
        name: "FlowActions",
        path: "../contracts/FlowActions.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "FlowALP",
        path: "../contracts/alp/FlowALP.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "FlowYieldVaults",
        path: "../contracts/yield_vaults/FlowYieldVaults.cdc",
        arguments: []
    )
}