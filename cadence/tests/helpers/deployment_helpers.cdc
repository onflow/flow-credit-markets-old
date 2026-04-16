import Test

access(self) var err: Test.Error? = nil
access(self) var actionsDeployed = false
access(self) var alpDeployed = false
access(self) var yieldVaultsDeployed = false

access(all) fun deployAllContracts() {
    deployFlowActions()
    deployFlowALP()
    deployFlowYieldVaults()
}

access(all) fun deployFlowActions() {
    pre {
        !actionsDeployed: "FlowActions already deployed"
    }
    actionsDeployed = true
    err = Test.deployContract(
        name: "FlowActions",
        path: "../contracts/actions/FlowActions.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all) fun deployFlowALP() {
    pre {
        actionsDeployed: "FlowActions must be deployed first"
        !alpDeployed: "FlowALP already deployed"
    }
    alpDeployed = true
    err = Test.deployContract(
        name: "FlowALP",
        path: "../contracts/alp/FlowALP.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all) fun deployFlowYieldVaults() {
    pre {
        alpDeployed: "FlowALP must be deployed first"
        !yieldVaultsDeployed: "FlowYieldVaults already deployed"
    }
    yieldVaultsDeployed = true
    err = Test.deployContract(
        name: "FlowYieldVaults",
        path: "../contracts/yield_vaults/FlowYieldVaults.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}
