import Test
import BlockchainHelpers

import "../helpers/deployment_helpers.cdc"
import "../helpers/yield_vault_helpers.cdc"
import "../helpers/yield_vault_lending_strategy_helpers.cdc"
import "FlowYieldVaults"
import "FlowYieldVaultsLendingStrategies"

access(all) var admin = Test.getAccount(0x0000000000000007)

access(all) var snapshot: UInt64 = 0
access(all) fun beforeEach() { Test.reset(to: snapshot) }

access(all) fun setup() {
    // ALP suite (interface/types first, then concrete impls)
    deploy("cadence/contracts/actions/FlowActionsIdea.cdc")
    deploy("cadence/contracts/alp/FlowALPTypesIdea.cdc")
    deploy("cadence/contracts/alp/FlowALPInterfaceIdea.cdc")
    deploy("cadence/contracts/alp/FlowALPHealthWatcherIdea.cdc")
    deploy("cadence/contracts/alp/FlowALP.cdc")
    deploy("cadence/contracts/alp/FlowALPHealthWatcher.cdc")

    // Yield vaults: interface → lending strategy → registry
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsInterfaces.cdc")
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsLendingStrategies.cdc")
    deploy("cadence/contracts/yield_vaults/FlowYieldVaults.cdc")

    // Test-only tokens / swapper / ALP mock
    deploy("cadence/tests/mocks/MockToken.cdc")
    deploy("cadence/tests/mocks/MockSwapper.cdc")
    deploy("cadence/tests/mocks/MockALP.cdc")

    snapshot = getCurrentBlockHeight()
}
