import Test

/// Last error returned by `Test.deployContract`; captured so that
/// `Test.expect(err, Test.beNil())` can assert a successful deploy.
access(self) var err: Test.Error? = nil
/// Tracks whether `FlowActions` has been deployed in the current test run.
access(self) var actionsDeployed = false
/// Tracks whether the `FlowALP*` contracts have been deployed.
access(self) var alpDeployed = false
/// Tracks whether the `FlowYieldVaults*` contracts have been deployed.
access(self) var yieldVaultsDeployed = false

/// Deploys every production contract in the correct dependency order:
/// `FlowActions` → `FlowALP*` → `FlowYieldVaults*`.
/// Each group can also be deployed individually via the helpers below.
access(all) fun deployAllContracts() {
    deployFlowActions()
    deployFlowALP()
    deployFlowYieldVaults()
}

/// Deploys `FlowActions`.
/// Panics if called more than once.
access(all) fun deployFlowActions() {
    pre {
        !actionsDeployed: "FlowActions already deployed"
    }
    actionsDeployed = true
    deploy("cadence/contracts/actions/FlowActionsIdea.cdc")
}

/// Deploys the `FlowALP` suite (`FlowALP`, `FlowALPHealthWatcher`).
/// Requires `FlowActions` to be deployed first.
/// Panics if called more than once.
access(all) fun deployFlowALP() {
    pre {
        actionsDeployed: "FlowActions must be deployed first"
        !alpDeployed: "FlowALP already deployed"
    }
    alpDeployed = true
    deploy("cadence/contracts/alp/FlowALPTypesIdea.cdc")
    deploy("cadence/contracts/alp/FlowALPInterfaceIdea.cdc")
    deploy("cadence/contracts/alp/FlowALPHealthWatcherIdea.cdc")
    deploy("cadence/contracts/alp/FlowALP.cdc")
    deploy("cadence/contracts/alp/FlowALPHealthWatcher.cdc")
}

/// Deploys the `FlowYieldVaults` suite
/// (`FlowYieldVaultsInterfaces`, `FlowYieldVaultsLendingStrategies`,
/// `FlowYieldVaults`, `FlowYieldVaultsEarlyAccess`).
/// Requires `FlowActions` and `FlowALP` to be deployed first.
/// Panics if called more than once.
access(all) fun deployFlowYieldVaults() {
    pre {
        actionsDeployed: "FlowActions must be deployed first"
        alpDeployed: "FlowALP must be deployed first"
        !yieldVaultsDeployed: "FlowYieldVaults already deployed"
    }
    yieldVaultsDeployed = true
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsInterfaces.cdc")
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsLendingStrategies.cdc")
    deploy("cadence/contracts/yield_vaults/FlowYieldVaults.cdc")
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsEarlyAccess.cdc")
}

/// Deploys a single contract from a repo-relative source path and asserts
/// the deploy succeeded. The contract name is taken from the filename
/// (stripping the trailing `.cdc`), which must match the contract
/// declaration inside the file.
///
/// **Parameters**
/// - `path`: Repo-relative path to the `.cdc` contract source.
access(all) fun deploy(_ path: String) {
    let parts = path.split(separator: "/")
    let filename = parts[parts.length - 1]
    let name = filename.slice(from: 0, upTo: filename.length - 4) // strip ".cdc"
    err = Test.deployContract(name: name, path: path, arguments: [])
    Test.expect(err, Test.beNil())
}
