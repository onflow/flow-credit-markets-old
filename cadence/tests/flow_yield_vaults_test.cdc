import Test
import BlockchainHelpers

import "helpers/deployment_helpers.cdc"
import "helpers/yield_vault_helpers.cdc"
import "FlowYieldVaults"

access(all) var admin = Test.getAccount(Address(0x0000000000000007))

access(all) var snapshot: UInt64 = 0
access(all) fun beforeEach() { Test.reset(to: snapshot) }

access(all) fun setup() {
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsInterfaces.cdc")
    deploy("cadence/contracts/yield_vaults/FlowYieldVaults.cdc")
    deploy("cadence/tests/mocks/MockStrategy.cdc")
    deploy("cadence/tests/mocks/TestYieldVaultGateway.cdc")
    snapshot = getCurrentBlockHeight()
}

access(all) fun test_strategyCount_starts_at_zero() {
    Test.assertEqual(0 as UInt64, strategyCount())
}

access(all) fun test_strategyNames_starts_empty() {
    Test.assertEqual(0, strategyNames().length)
}

access(all) fun test_registerStrategy_increments_count() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.assertEqual(1 as UInt64, strategyCount())
}

access(all) fun test_registerStrategy_emits_event() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    let events = Test.eventsOfType(Type<FlowYieldVaults.StrategyCreated>())
    Test.assertEqual(1, events.length)
    Test.assertEqual("a", (events[0] as! FlowYieldVaults.StrategyCreated).name)
}

access(all) fun test_registerStrategy_multiple_names() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(registerMockStrategy(name: "b", signer: admin), Test.beSucceeded())
    Test.expect(registerMockStrategy(name: "c", signer: admin), Test.beSucceeded())
    Test.assertEqual(3 as UInt64, strategyCount())
    let names = strategyNames()
    Test.assertEqual(3, names.length)
    Test.assert(names.contains("a"))
    Test.assert(names.contains("b"))
    Test.assert(names.contains("c"))
}

access(all) fun test_registerStrategy_duplicate_name_fails() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    expectFailedWithError(
        registerMockStrategy(name: "a", signer: admin),
        errorMessageSubstring: "Strategy already registered"
    )
}

access(all) fun test_createStrategyVault_unknown_fails() {
    expectFailedWithError(
        createStrategyVault(name: "missing", signer: admin),
        errorMessageSubstring: "Strategy not found"
    )
}

access(all) fun test_createStrategyVault_conforms_to_YieldVault_interface() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(
        createStrategyVaultAtPath(name: "a", path: /storage/yieldVaultTypeCheck, signer: admin),
        Test.beSucceeded()
    )
}

access(all) fun test_createStrategyVault_emits_event() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "a", signer: admin), Test.beSucceeded())
    let events = Test.eventsOfType(Type<FlowYieldVaults.StrategyVaultCreated>())
    Test.assertEqual(1, events.length)
    Test.assertEqual("a", (events[0] as! FlowYieldVaults.StrategyVaultCreated).name)
}

access(all) fun test_createStrategyVault_multiple_times_same_name() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(createStrategyVault(name: "a", signer: admin), Test.beSucceeded())
    Test.assertEqual(3, Test.eventsOfType(Type<FlowYieldVaults.StrategyVaultCreated>()).length)
}

access(all) fun test_removeStrategy_removes_entry() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(registerMockStrategy(name: "b", signer: admin), Test.beSucceeded())
    Test.expect(removeStrategy(name: "a", signer: admin), Test.beSucceeded())
    let names = strategyNames()
    Test.assertEqual(1, names.length)
    Test.assert(!names.contains("a"))
    Test.assert(names.contains("b"))
}

access(all) fun test_removeStrategy_emits_event() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(removeStrategy(name: "a", signer: admin), Test.beSucceeded())
    let events = Test.eventsOfType(Type<FlowYieldVaults.StrategyRemoved>())
    Test.assertEqual(1, events.length)
    Test.assertEqual("a", (events[0] as! FlowYieldVaults.StrategyRemoved).name)
}

access(all) fun test_removeStrategy_unknown_fails() {
    expectFailedWithError(
        removeStrategy(name: "missing", signer: admin),
        errorMessageSubstring: "Strategy not found"
    )
}

access(all) fun test_removeStrategy_blocks_createYieldVault() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(removeStrategy(name: "a", signer: admin), Test.beSucceeded())
    expectFailedWithError(
        createStrategyVault(name: "a", signer: admin),
        errorMessageSubstring: "Strategy not found"
    )
}

access(all) fun test_strategyInfos_starts_empty() {
    Test.assertEqual(0, strategyInfos().keys.length)
}

access(all) fun test_strategyInfos_returns_descriptions() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(registerMockStrategy(name: "b", signer: admin), Test.beSucceeded())
    let infos = strategyInfos()
    Test.assertEqual(2, infos.keys.length)
    Test.assertEqual("mock strategy", infos["a"]!)
    Test.assertEqual("mock strategy", infos["b"]!)
}

access(all) fun test_strategyInfos_reflects_removal() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(registerMockStrategy(name: "b", signer: admin), Test.beSucceeded())
    Test.expect(removeStrategy(name: "a", signer: admin), Test.beSucceeded())
    let infos = strategyInfos()
    Test.assertEqual(1, infos.keys.length)
    Test.assertEqual(nil, infos["a"])
    Test.assertEqual("mock strategy", infos["b"]!)
}

access(all) fun test_register_after_remove_succeeds() {
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(removeStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.expect(registerMockStrategy(name: "a", signer: admin), Test.beSucceeded())
    Test.assertEqual(1 as UInt64, strategyCount())
    Test.assert(strategyNames().contains("a"))
}

access(self) fun expectFailedWithError(_ res: Test.TransactionResult, errorMessageSubstring: String) {
    Test.expect(res, Test.beFailed())
    Test.assertError(res, errorMessage: errorMessageSubstring)
}
