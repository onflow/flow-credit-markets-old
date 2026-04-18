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
    deploy("cadence/contracts/actions/FlowActions.cdc")
}

access(all) fun deployFlowALP() {
    pre {
        actionsDeployed: "FlowActions must be deployed first"
        !alpDeployed: "FlowALP already deployed"
    }
    alpDeployed = true
    deploy("cadence/contracts/alp/FlowALP.cdc")
}

access(all) fun deployFlowYieldVaults() {
    pre {
        alpDeployed: "FlowALP must be deployed first"
        !yieldVaultsDeployed: "FlowYieldVaults already deployed"
    }
    yieldVaultsDeployed = true
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsInterfaces.cdc")
    deploy("cadence/contracts/yield_vaults/FlowYieldVaults.cdc")
}

access(self) fun deploy(_ path: String) {
    let parts = path.split(separator: "/")
    let filename = parts[parts.length - 1]
    let name = filename.slice(from: 0, upTo: filename.length - 4) // strip ".cdc"
    err = Test.deployContract(name: name, path: path, arguments: [])
    Test.expect(err, Test.beNil())
}
