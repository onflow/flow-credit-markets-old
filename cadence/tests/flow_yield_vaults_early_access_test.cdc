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
    deploy("cadence/contracts/actions/FlowActions.cdc")
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsInterfaces.cdc")
    Test.expect(Test.deployContract(
        name: "FlowYieldVaults",
            path: "cadence/tests/mocks/MockFlowYieldVaults.cdc",
            arguments: []
        ),
        Test.beNil()
    )
    deploy("cadence/contracts/yield_vaults/FlowYieldVaultsEarlyAccess.cdc")
    snapshot = getCurrentBlockHeight()
}

access(all) fun test_no_pass() {
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: defaultPath),
        errorMessageSubstring: "No valid early access pass"
    )
}

access(all) fun test_grant() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.assert(hasEarlyAccess(userA.address))
    Test.expect(createYieldVault(signer: userA, name: "mock", path: defaultPath), Test.beSucceeded())
    expectFailedWithError(
        createYieldVault(signer: userB, name: "mock", path: defaultPath),
        errorMessageSubstring: "No valid early access pass"
    )
}

access(all) fun test_revoke() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())

    Test.expect(revokeEarlyAccess(admin: admin, addr: userA.address), Test.beSucceeded())
    Test.assert(!hasEarlyAccess(userA.address))
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: defaultPath),
        errorMessageSubstring: "No valid early access pass"
    )
}

access(all) fun test_use_position_after_revoke() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: defaultPath), Test.beSucceeded())
    Test.expect(revokeEarlyAccess(admin: admin, addr: userA.address), Test.beSucceeded())
    Test.expect(deposit(signer: userA, path: defaultPath), Test.beSucceeded())
}

access(all) fun test_reissue_replaces_allowance() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 1), Test.beSucceeded())
    Test.assertEqual(1 as UInt64, remainingAllowance(userA.address))
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 5), Test.beSucceeded())
    Test.assertEqual(5 as UInt64, remainingAllowance(userA.address))
    Test.assert(hasEarlyAccess(userA.address))
}

access(all) fun test_reissue_invalidates_previously_claimed_capability() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())

    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 5), Test.beSucceeded())

    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: /storage/b),
        errorMessageSubstring: "No valid early access pass"
    )

    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/b), Test.beSucceeded())
    Test.assertEqual(4 as UInt64, remainingAllowance(userA.address))
}

access(all) fun test_multiple_revoke() {
    Test.expect(revokeEarlyAccess(admin: admin, addr: userA.address), Test.beFailed())
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(revokeEarlyAccess(admin: admin, addr: userA.address), Test.beSucceeded())
    Test.expect(revokeEarlyAccess(admin: admin, addr: userA.address), Test.beFailed())
}

access(all) fun test_revoke_and_re_grant() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(revokeEarlyAccess(admin: admin, addr: userA.address), Test.beSucceeded())
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.assert(hasEarlyAccess(userA.address))
    Test.expect(createYieldVault(signer: userA, name: "mock", path: defaultPath), Test.beSucceeded())
}

access(all) fun test_pass_is_reusable() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/b), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/c), Test.beSucceeded())
}

access(all) fun test_allowance_exhausted() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 1), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: /storage/b),
        errorMessageSubstring: "No remaining allowance"
    )
}

access(all) fun test_two_users_independent() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(grantEarlyAccess(admin: admin, user: userB, allowance: 3), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.expect(claimPass(user: userB, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: defaultPath), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userB, name: "mock", path: defaultPath), Test.beSucceeded())
    Test.expect(revokeEarlyAccess(admin: admin, addr: userA.address), Test.beSucceeded())
    Test.assert(!hasEarlyAccess(userA.address))
    Test.assert(hasEarlyAccess(userB.address))
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: /storage/a2),
        errorMessageSubstring: "No valid early access pass"
    )
    Test.expect(createYieldVault(signer: userB, name: "mock", path: /storage/b2), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userB, name: "mock", path: /storage/b3), Test.beSucceeded())
}

access(all) fun test_remainingPositions_reflects_allowance() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.assertEqual(3 as UInt64, remainingAllowance(userA.address))
}

access(all) fun test_remainingPositions_decrements_on_createYieldVault() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    Test.assertEqual(2 as UInt64, remainingAllowance(userA.address))
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/b), Test.beSucceeded())
    Test.assertEqual(1 as UInt64, remainingAllowance(userA.address))
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/c), Test.beSucceeded())
    Test.assertEqual(0 as UInt64, remainingAllowance(userA.address))
}

access(all) fun test_remainingPositions_is_zero_after_exhausted() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 1), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    Test.assertEqual(0 as UInt64, remainingAllowance(userA.address))
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: /storage/b),
        errorMessageSubstring: "No remaining allowance"
    )
}

access(all) fun test_remainingPositions_fails_for_nonexistent_pass() {
    Test.expectFailure(fun () {
        let _ = FlowYieldVaultsEarlyAccess.remainingAllowance(addr: userA.address)
    }, errorMessageSubstring: "Pass not found")
}

access(all) fun test_remainingPositions_two_users_independent() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 5), Test.beSucceeded())
    Test.expect(grantEarlyAccess(admin: admin, user: userB, allowance: 2), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    Test.assertEqual(4 as UInt64, remainingAllowance(userA.address))
    Test.assertEqual(2 as UInt64, remainingAllowance(userB.address))
}

access(all) fun test_setAllowance() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 1), Test.beSucceeded())
    Test.assertEqual(1 as UInt64, remainingAllowance(userA.address))
    Test.expect(setAllowance(admin: admin, addr: userA.address, newAllowance: 5), Test.beSucceeded())
    Test.assertEqual(5 as UInt64, remainingAllowance(userA.address))
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/b), Test.beSucceeded())
    Test.assertEqual(3 as UInt64, remainingAllowance(userA.address))
}

access(all) fun test_setAllowance_to_zero_blocks_createYieldVault() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(setAllowance(admin: admin, addr: userA.address, newAllowance: 0), Test.beSucceeded())
    Test.assertEqual(0 as UInt64, remainingAllowance(userA.address))
    Test.assert(hasEarlyAccess(userA.address))
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    expectFailedWithError(
        createYieldVault(signer: userA, name: "mock", path: defaultPath),
        errorMessageSubstring: "No remaining allowance"
    )
}

access(all) fun test_grant_events() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    let events = Test.eventsOfType(Type<FlowYieldVaultsEarlyAccess.PassIssued>())
    Test.assertEqual(1, events.length)
    let ev = events[0] as! FlowYieldVaultsEarlyAccess.PassIssued
    Test.assertEqual(userA.address, ev.addr)
    Test.assertEqual(3 as UInt64, ev.allowance)
}

access(all) fun test_revoke_events() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(revokeEarlyAccess(admin: admin, addr: userA.address), Test.beSucceeded())
    var events = Test.eventsOfType(Type<FlowYieldVaultsEarlyAccess.PassRevoked>())
    Test.assertEqual(1, events.length)
    let ev = events[0] as! FlowYieldVaultsEarlyAccess.PassRevoked
    Test.assertEqual(userA.address, ev.addr)
}

access(all) fun test_used_events() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 3), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    Test.expect(createYieldVault(signer: userA, name: "mock", path: /storage/a), Test.beSucceeded())
    let events = Test.eventsOfType(Type<FlowYieldVaultsEarlyAccess.PassUsed>())
    Test.assertEqual(1, events.length)
    let ev = events[0] as! FlowYieldVaultsEarlyAccess.PassUsed
    Test.assertEqual(userA.address, ev.addr)
    Test.assertEqual(2 as UInt64, ev.remainingAllowance)
}

access(all) fun test_no_pass_for_addr() {
    Test.assert(!FlowYieldVaultsEarlyAccess.passExists(addr: userA.address))
    Test.expectFailure(
        fun () {
            let _ = FlowYieldVaultsEarlyAccess.remainingAllowance(addr: userA.address)
        }, errorMessageSubstring: "Pass not found"
    )
}

access(all) fun test_claim_with_custom_path() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 1), Test.beSucceeded())
    let customPath = /storage/myCustomEarlyAccessPath
    Test.expect(claimPassWithPath(user: userA, provider: admin.address, path: customPath), Test.beSucceeded())
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
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 1), Test.beSucceeded())
    Test.expect(claimPass(user: userA, provider: admin.address), Test.beSucceeded())
    expectFailedWithError(
        claimPass(user: userA, provider: admin.address),
        errorMessageSubstring: "No pass found in inbox"
    )
}

access(all) fun test_claim_without_grant_fails() {
    expectFailedWithError(
        claimPass(user: userA, provider: admin.address),
        errorMessageSubstring: "No pass found in inbox"
    )
}

access(all) fun test_claim_after_revoke_fails() {
    Test.expect(grantEarlyAccess(admin: admin, user: userA, allowance: 1), Test.beSucceeded())
    Test.expect(revokeEarlyAccess(admin: admin, addr: userA.address), Test.beSucceeded())
    expectFailedWithError(
        claimPass(user: userA, provider: admin.address),
        errorMessageSubstring: "No pass found in inbox"
    )
}

access(self) fun expectFailedWithError(_ res: Test.TransactionResult, errorMessageSubstring: String) {
    Test.expect(res, Test.beFailed())
    Test.assertError(res, errorMessage: errorMessageSubstring)
}
