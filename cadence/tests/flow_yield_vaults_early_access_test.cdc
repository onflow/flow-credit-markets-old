import Test
import BlockchainHelpers

import "helpers/deployment_helpers.cdc"
import "helpers/yield_vault_early_access_helpers.cdc"
import "FlowYieldVaultsEarlyAccess"

access(all) var admin = Test.getAccount(Address(0x0000000000000007))
access(all) let userA = Test.createAccount()
access(all) let userB = Test.createAccount()

access(all) let defaultPath = /storage/FlowYieldVaultsEarlyAccessPosition

access(all) var snapshot: UInt64 = 0
access(all) fun beforeEach() { Test.reset(to: snapshot) }

access(all) fun setup() {
    deploy("cadence/contracts/actions/FlowActionsIdea.cdc")
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsInterfaces.cdc")
    deploy("cadence/tests/mocks/MockFlowYieldVaults.cdc")
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsEarlyAccess.cdc")
    Test.expect(
        setYieldVaultsImpl(admin: admin, txPath: "cadence/tests/transactions/yield_vaults/early_access/set_mock_yield_vaults_implementation.cdc"),
        Test.beSucceeded()
    )
    snapshot = getCurrentBlockHeight()
}

access(all) fun test_no_pass() {
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: defaultPath),
        errorMessageSubstring: "No valid early access pass"
    )
}

access(all) fun test_grant() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.expect(claimPass(user: userA, passUUID: passUUID, provider: admin.address), Test.beSucceeded())
    Test.assert(hasEarlyAccess(passUUID))
    Test.expect(createYieldVault(signer: userA, name: "mock", path: defaultPath), Test.beSucceeded())
    expectFailedWithError(
        createYieldVault(signer: userB, name: "mock", path: defaultPath),
        errorMessageSubstring: "No valid early access pass"
    )
}

access(all) fun test_revoke() {
    let passUUIDA = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.expect(claimPass(user: userA, passUUID: passUUIDA, provider: admin.address), Test.beSucceeded())

    Test.expect(revokeEarlyAccess(admin: admin, passUUID: passUUIDA), Test.beSucceeded())
    Test.assert(!hasEarlyAccess(passUUIDA))
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: defaultPath),
        errorMessageSubstring: "No valid early access pass"
    )
}

access(all) fun test_use_position_after_revoke() {
    let passUUIDA = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.expect(claimPass(user: userA, passUUID: passUUIDA, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: defaultPath), Test.beSucceeded())
    Test.expect(revokeEarlyAccess(admin: admin, passUUID: passUUIDA), Test.beSucceeded())
    Test.expect(deposit(signer: userA, path: defaultPath), Test.beSucceeded())
}

access(all) fun test_multiple_grants() {
    let passUUID1 = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    let passUUID2 = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.assert(hasEarlyAccess(passUUID1))
    Test.assert(hasEarlyAccess(passUUID2))
}

access(all) fun test_multiple_revoke() {
    Test.expect(revokeEarlyAccess(admin: admin, passUUID: 0), Test.beFailed())
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.expect(revokeEarlyAccess(admin: admin, passUUID: passUUID), Test.beSucceeded())
    Test.expect(revokeEarlyAccess(admin: admin, passUUID: passUUID), Test.beFailed())
}

access(all) fun test_revoke_and_re_grant() {
    let passUUID1 = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.expect(revokeEarlyAccess(admin: admin, passUUID: passUUID1), Test.beSucceeded())
    let passUUID2 = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.expect(claimPass(user: userA, passUUID: passUUID2, provider: admin.address), Test.beSucceeded())
    Test.assert(hasEarlyAccess(passUUID2))
    Test.expect(createYieldVault(signer: userA, name: "mock", path: defaultPath), Test.beSucceeded())
}

access(all) fun test_pass_is_reusable() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.expect(claimPass(user: userA, passUUID: passUUID, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/b), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/c), Test.beSucceeded())
}

access(all) fun test_allowance_exhausted() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 1)
    Test.expect(claimPass(user: userA, passUUID: passUUID, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: /storage/b),
        errorMessageSubstring: "No remaining allowance"
    )
}

access(all) fun test_two_users_independent() {
    let passUUIDA = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    let passUUIDB = grantEarlyAccess(admin: admin, user: userB, allowance: 3)
    Test.expect(claimPass(user: userA, passUUID: passUUIDA, provider: admin.address), Test.beSucceeded())
    Test.expect(claimPass(user: userB, passUUID: passUUIDB, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: defaultPath), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userB, name: "mock", path: defaultPath), Test.beSucceeded())
    Test.expect(revokeEarlyAccess(admin: admin, passUUID: passUUIDA), Test.beSucceeded())
    Test.assert(!hasEarlyAccess(passUUIDA))
    Test.assert(hasEarlyAccess(passUUIDB))
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: /storage/a2),
        errorMessageSubstring: "No valid early access pass"
    )
    Test.expect(createYieldVault(signer: userB, name: "mock", path: /storage/b2), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userB, name: "mock", path: /storage/b3), Test.beSucceeded())
}

access(all) fun test_remainingPositions_reflects_allowance() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.assertEqual(3 as UInt64, remainingAllowance(passUUID))
}

access(all) fun test_remainingPositions_decrements_on_createYieldVault() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.expect(claimPass(user: userA, passUUID: passUUID, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    Test.assertEqual(2 as UInt64, remainingAllowance(passUUID))
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/b), Test.beSucceeded())
    Test.assertEqual(1 as UInt64, remainingAllowance(passUUID))
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/c), Test.beSucceeded())
    Test.assertEqual(0 as UInt64, remainingAllowance(passUUID))
}

access(all) fun test_remainingPositions_is_zero_after_exhausted() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 1)
    Test.expect(claimPass(user: userA, passUUID: passUUID, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    Test.assertEqual(0 as UInt64, remainingAllowance(passUUID))
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: /storage/b),
        errorMessageSubstring: "No remaining allowance"
    )
}

access(all) fun test_remainingPositions_fails_for_nonexistent_pass() {
    Test.expectFailure(fun () {
        let _ = FlowYieldVaultsEarlyAccess.remainingAllowance(passUUID: 0)
    }, errorMessageSubstring: "Pass not found")
}

access(all) fun test_remainingPositions_two_users_independent() {
    let passUUIDA = grantEarlyAccess(admin: admin, user: userA, allowance: 5)
    let passUUIDB = grantEarlyAccess(admin: admin, user: userB, allowance: 2)
    Test.expect(claimPass(user: userA, passUUID: passUUIDA, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    Test.assertEqual(4 as UInt64, remainingAllowance(passUUIDA))
    Test.assertEqual(2 as UInt64, remainingAllowance(passUUIDB))
}

access(all) fun test_setAllowance() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 1)
    Test.assertEqual(1 as UInt64, remainingAllowance(passUUID))
    Test.expect(setAllowance(admin: admin, passUUID: passUUID, newAllowance: 5), Test.beSucceeded())
    Test.assertEqual(5 as UInt64, remainingAllowance(passUUID))
    Test.expect(claimPass(user: userA, passUUID: passUUID, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/b), Test.beSucceeded())
    Test.assertEqual(3 as UInt64, remainingAllowance(passUUID))
}

access(all) fun test_setAllowance_to_zero_blocks_createYieldVault() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.expect(setAllowance(admin: admin, passUUID: passUUID, newAllowance: 0), Test.beSucceeded())
    Test.assertEqual(0 as UInt64, remainingAllowance(passUUID))
    Test.assert(hasEarlyAccess(passUUID))
    Test.expect(claimPass(user: userA, passUUID: passUUID, provider: admin.address), Test.beSucceeded())
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: defaultPath),
        errorMessageSubstring: "No remaining allowance"
    )
}

access(all) fun test_grant_events() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    let events = Test.eventsOfType(Type<FlowYieldVaultsEarlyAccess.PassIssued>())
    Test.assertEqual(1, events.length)
    let ev = events[0] as! FlowYieldVaultsEarlyAccess.PassIssued
    Test.assertEqual(userA.address, ev.addr)
    Test.assertEqual(3 as UInt64, ev.allowance)
    Test.assertEqual(passUUID, ev.passUUID)
}

access(all) fun test_revoke_events() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.expect(revokeEarlyAccess(admin: admin, passUUID: passUUID), Test.beSucceeded())
    var events = Test.eventsOfType(Type<FlowYieldVaultsEarlyAccess.PassRevoked>())
    Test.assertEqual(1, events.length)
    let ev = events[0] as! FlowYieldVaultsEarlyAccess.PassRevoked
    Test.assertEqual(passUUID, ev.passUUID)
}

access(all) fun test_used_events() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.expect(claimPass(user: userA, passUUID: passUUID, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    let events = Test.eventsOfType(Type<FlowYieldVaultsEarlyAccess.PassUsed>())
    Test.assertEqual(1, events.length)
    let ev = events[0] as! FlowYieldVaultsEarlyAccess.PassUsed
    Test.assertEqual(passUUID, ev.passUUID)
    Test.assertEqual(2 as UInt64, ev.remainingAllowance)
}

access(all) fun test_invalid_pass_uuid() {
    Test.assert(!FlowYieldVaultsEarlyAccess.passExists(passUUID: 0))
    Test.expectFailure(
        fun () {
            let _ = FlowYieldVaultsEarlyAccess.remainingAllowance(passUUID: 0)
        }, errorMessageSubstring: "Pass not found"
    )
}

access(all) fun test_claim_by_address() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 3)
    Test.expect(claimPassByAddress(user: userA, provider: admin.address), Test.beSucceeded())
    Test.assert(hasEarlyAccess(passUUID))
    Test.expect(createYieldVault(signer: userA, name: "mock", path: defaultPath), Test.beSucceeded())
}

access(all) fun test_claim_by_address_gets_most_recent() {
    let _ = grantEarlyAccess(admin: admin, user: userA, allowance: 1)
    let passUUID2 = grantEarlyAccess(admin: admin, user: userA, allowance: 5)
    Test.expect(claimPassByAddress(user: userA, provider: admin.address), Test.beSucceeded())
    Test.assertEqual(5 as UInt64, remainingAllowance(passUUID2))
    Test.expect(createYieldVault(signer: userA, name: "mock", path: defaultPath), Test.beSucceeded())
}

access(all) fun test_claim_by_address_fails_if_no_pass_issued() {
    expectFailedWithError(
        claimPassByAddress(user: userA, provider: admin.address),
        errorMessageSubstring: "No pass issued to this address"
    )
}

access(all) fun test_claim_with_custom_path() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 1)
    let customPath = /storage/myCustomEarlyAccessPath
    Test.expect(claimPassWithPath(user: userA, passUUID: passUUID, provider: admin.address, path: customPath), Test.beSucceeded())
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: defaultPath),
        errorMessageSubstring: "No valid early access pass"
    )
    Test.expect(
        createYieldVaultAtEarlyAccessPath(signer: userA, name: "mock", earlyAccessPath: customPath, vaultPath: defaultPath),
        Test.beSucceeded()
    )
}

access(all) fun test_double_claim_fails() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 1)
    Test.expect(claimPass(user: userA, passUUID: passUUID, provider: admin.address), Test.beSucceeded())
    expectFailedWithError(
        claimPass(user: userA, passUUID: passUUID, provider: admin.address),
        errorMessageSubstring: "No pass found in inbox"
    )
}

access(all) fun test_claim_nonexistent_pass_fails() {
    expectFailedWithError(
        claimPass(user: userA, passUUID: 99999, provider: admin.address),
        errorMessageSubstring: "No pass found in inbox"
    )
}

access(all) fun test_claim_after_revoke_fails() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 1)
    Test.expect(revokeEarlyAccess(admin: admin, passUUID: passUUID), Test.beSucceeded())
    expectFailedWithError(
        claimPass(user: userA, passUUID: passUUID, provider: admin.address),
        errorMessageSubstring: "No pass found in inbox"
    )
}

access(all) fun test_claim_by_address_fails_after_revoke() {
    let passUUID = grantEarlyAccess(admin: admin, user: userA, allowance: 1)
    Test.expect(revokeEarlyAccess(admin: admin, passUUID: passUUID), Test.beSucceeded())
    expectFailedWithError(
        claimPassByAddress(user: userA, provider: admin.address),
        errorMessageSubstring: "No pass found in inbox"
    )
}

access(self) fun expectFailedWithError(_ res: Test.TransactionResult, errorMessageSubstring: String) {
    Test.expect(res, Test.beFailed())
    Test.assertError(res, errorMessage: errorMessageSubstring)
}
