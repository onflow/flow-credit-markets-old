import Test

/// Deploys every production contract in the correct dependency order:
/// `FlowActions` → `FlowALP*` → `FlowYieldVaults*`.
/// Each group can also be deployed individually via the helpers below.
access(all) fun deployAllContracts() {
    deployFlowActions()
    deployFlowALP()
    deployFlowYieldVaults()
}

/// Deploys `FlowActions`.
access(all) fun deployFlowActions() {
    deploy("cadence/contracts/actions/FlowActions.cdc")
}

/// Deploys `FlowALP`.
/// Requires `FlowActions` to be deployed first.
access(all) fun deployFlowALP() {
    deploy("cadence/contracts/alp/FlowALP.cdc")
}

/// Deploys the `FlowYieldVaults` suite
/// (`FlowYieldVaultsInterfaces`, `FlowYieldVaults`, `FlowYieldVaultsEarlyAccess`).
/// Requires `FlowActions` and `FlowALP` to be deployed first.
access(all) fun deployFlowYieldVaults() {
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsInterfaces.cdc")
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsInterfaces.cdc")
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
    let err = Test.deployContract(name: name, path: path, arguments: [])
    Test.expect(err, Test.beNil())
}
