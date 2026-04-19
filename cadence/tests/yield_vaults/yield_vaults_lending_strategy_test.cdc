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

// --- strategy registration ---

access(all) fun test_createLendingStrategy_registers() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.assertEqual(1 as UInt64, strategyCount())
    Test.assert(strategyNames().contains("a"))
}

access(all) fun test_createLendingStrategy_multiple_names() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createLendingStrategy(name: "b", signer: admin), Test.beSucceeded())
    Test.expect(createLendingStrategy(name: "c", signer: admin), Test.beSucceeded())
    Test.assertEqual(3 as UInt64, strategyCount())
}

access(all) fun test_createLendingStrategy_duplicate_name_fails() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    let res = createLendingStrategy(name: "a", signer: admin)
    Test.expect(res, Test.beFailed())
    Test.assertError(res, errorMessage: "Strategy already registered")
}

access(all) fun test_createLendingStrategy_emits_FlowYieldVaults_event() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    let events = Test.eventsOfType(Type<FlowYieldVaults.StrategyCreated>())
    Test.assertEqual(1, events.length)
    Test.assertEqual("a", (events[0] as! FlowYieldVaults.StrategyCreated).name)
}

access(all) fun test_createLendingStrategy_emits_LendingStrategies_event() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.assertEqual(1, Test.eventsOfType(Type<FlowYieldVaultsLendingStrategies.LendingStrategyCreated>()).length)
}

access(all) fun test_createLendingStrategy_emits_both_events() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createLendingStrategy(name: "b", signer: admin), Test.beSucceeded())
    Test.assertEqual(2, Test.eventsOfType(Type<FlowYieldVaults.StrategyCreated>()).length)
    Test.assertEqual(2, Test.eventsOfType(Type<FlowYieldVaultsLendingStrategies.LendingStrategyCreated>()).length)
}

// --- yield vault creation from a lending strategy ---

access(all) fun test_createStrategyVault() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "a", signer: admin), Test.beSucceeded())
}

access(all) fun test_createStrategyVault_unknown_name_fails() {
    let res = createStrategyVault(name: "missing", signer: admin)
    Test.expect(res, Test.beFailed())
    Test.assertError(res, errorMessage: "Strategy not found")
}

access(all) fun test_createStrategyVault_emits_FlowYieldVaults_event() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "a", signer: admin), Test.beSucceeded())
    let events = Test.eventsOfType(Type<FlowYieldVaults.StrategyVaultCreated>())
    Test.assertEqual(1, events.length)
    Test.assertEqual("a", (events[0] as! FlowYieldVaults.StrategyVaultCreated).name)
}

access(all) fun test_createStrategyVault_emits_LendingStrategies_event() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "a", signer: admin), Test.beSucceeded())
    Test.assertEqual(1, Test.eventsOfType(Type<FlowYieldVaultsLendingStrategies.LendingStrategyVaultCreated>()).length)
}

access(all) fun test_createMultipleVaultsForSameStrategy() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "a", signer: admin), Test.beSucceeded())
    Test.assertEqual(3, Test.eventsOfType(Type<FlowYieldVaults.StrategyVaultCreated>()).length)
}

access(all) fun test_createVaultsForAllStrategies_emits_correct_event_count() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createLendingStrategy(name: "b", signer: admin), Test.beSucceeded())
    Test.expect(createLendingStrategy(name: "c", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "b", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "c", signer: admin), Test.beSucceeded())
    Test.assertEqual(3, Test.eventsOfType(Type<FlowYieldVaults.StrategyVaultCreated>()).length)
    Test.assertEqual(3, Test.eventsOfType(Type<FlowYieldVaultsLendingStrategies.LendingStrategyVaultCreated>()).length)
}

// --- deposit / withdraw on a lending-strategy yield vault ---

access(all) let vaultPath = /storage/testLendingYieldVault

access(all) fun test_deposit_empty_vault_succeeds() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createAndSaveYieldVault(name: "a", path: vaultPath, signer: admin), Test.beSucceeded())
    Test.expect(depositToYieldVault(path: vaultPath, amount: 0.0, signer: admin), Test.beSucceeded())
}

access(all) fun test_deposit_non_empty_vault_succeeds() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createAndSaveYieldVault(name: "a", path: vaultPath, signer: admin), Test.beSucceeded())
    Test.expect(depositToYieldVault(path: vaultPath, amount: 100.0, signer: admin), Test.beSucceeded())
}

access(all) fun test_withdraw_zero_succeeds() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createAndSaveYieldVault(name: "a", path: vaultPath, signer: admin), Test.beSucceeded())
    Test.expect(withdrawFromYieldVault(path: vaultPath, amount: 0.0, signer: admin), Test.beSucceeded())
}

access(all) fun test_deposit_then_withdraw_zero() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createAndSaveYieldVault(name: "a", path: vaultPath, signer: admin), Test.beSucceeded())
    Test.expect(depositToYieldVault(path: vaultPath, amount: 50.0, signer: admin), Test.beSucceeded())
    Test.expect(withdrawFromYieldVault(path: vaultPath, amount: 0.0, signer: admin), Test.beSucceeded())
}

access(all) fun test_deposit_then_withdraw_partial() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createAndSaveYieldVault(name: "a", path: vaultPath, signer: admin), Test.beSucceeded())
    Test.expect(depositToYieldVault(path: vaultPath, amount: 100.0, signer: admin), Test.beSucceeded())
    Test.expect(withdrawFromYieldVault(path: vaultPath, amount: 40.0, signer: admin), Test.beSucceeded())
}

access(all) fun test_deposit_then_withdraw_full() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createAndSaveYieldVault(name: "a", path: vaultPath, signer: admin), Test.beSucceeded())
    Test.expect(depositToYieldVault(path: vaultPath, amount: 100.0, signer: admin), Test.beSucceeded())
    Test.expect(withdrawFromYieldVault(path: vaultPath, amount: 100.0, signer: admin), Test.beSucceeded())
}

access(all) fun test_withdraw_more_than_deposited_fails() {
    Test.expect(createLendingStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createAndSaveYieldVault(name: "a", path: vaultPath, signer: admin), Test.beSucceeded())
    Test.expect(depositToYieldVault(path: vaultPath, amount: 100.0, signer: admin), Test.beSucceeded())
    Test.expect(withdrawFromYieldVault(path: vaultPath, amount: 200.0, signer: admin), Test.beFailed())
}
