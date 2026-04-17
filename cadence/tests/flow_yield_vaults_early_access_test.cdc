import Test
import BlockchainHelpers

import "helpers/deployment_helpers.cdc"
import "helpers/yield_vault_helpers.cdc"
import "FlowYieldVaultsEarlyAccess"

access(all) var admin = Test.getAccount(Address(0x0000000000000007))
access(all) let userA = Test.createAccount()
access(all) let userB = Test.createAccount()

access(all) let defaultPath = /storage/FlowYieldVaultsEarlyAccessPosition

access(all) var snapshot: UInt64 = 0

access(all) fun beforeEach() {
    if snapshot != getCurrentBlockHeight() {
        Test.reset(to: snapshot)
    }
}

access(all) fun setup() {
    deployAllContracts()
    snapshot = getCurrentBlockHeight()
}

access(all) fun test_is_allowed_false_by_default() {
    Test.assertEqual(false, hasEarlyAccess(userA.address))
    expectFailedWithError(createPosition(signer: userA, path: defaultPath), "Signer is not in the allowlist")
}

access(all) fun test_grant() {
    grantEarlyAccess(admin: admin, addr: userA.address)
    Test.assertEqual(true, hasEarlyAccess(userA.address))
    Test.assertEqual(false, hasEarlyAccess(userB.address))
    Test.expect(createPosition(signer: userA, path: defaultPath), Test.beSucceeded())
    Test.expect(deposit(signer: userA), Test.beSucceeded())
    expectFailedWithError(createPosition(signer: userB, path: defaultPath), "Signer is not in the allowlist")
}

access(all) fun test_revoke() {
    revokeEarlyAccess(admin: admin, addr: userA.address)
    Test.assertEqual(false, hasEarlyAccess(userA.address))
    expectFailedWithError(createPosition(signer: userA, path: defaultPath), "Signer is not in the allowlist")

    grantEarlyAccess(admin: admin, addr: userA.address)
    revokeEarlyAccess(admin: admin, addr: userA.address)
    Test.assertEqual(false, hasEarlyAccess(userA.address))
    expectFailedWithError(createPosition(signer: userA, path: defaultPath), "Signer is not in the allowlist")
}

access(all) fun test_grant_events() {
    grantEarlyAccess(admin: admin, addr: userA.address)
    var events = Test.eventsOfType(Type<FlowYieldVaultsEarlyAccess.AccessGranted>())
    Test.assertEqual(1, events.length)
    let ev = events[0] as! FlowYieldVaultsEarlyAccess.AccessGranted
    Test.assertEqual(userA.address, ev.addr)

    grantEarlyAccess(admin: admin, addr: userA.address)
    events = Test.eventsOfType(Type<FlowYieldVaultsEarlyAccess.AccessGranted>())
    Test.assertEqual(1, events.length)
}

access(all) fun test_revoke_events() {
    revokeEarlyAccess(admin: admin, addr: userA.address)
    var events = Test.eventsOfType(Type<FlowYieldVaultsEarlyAccess.AccessRevoked>())
    Test.assertEqual(0, events.length)

    grantEarlyAccess(admin: admin, addr: userA.address)
    revokeEarlyAccess(admin: admin, addr: userA.address)
    events = Test.eventsOfType(Type<FlowYieldVaultsEarlyAccess.AccessRevoked>())
    Test.assertEqual(1, events.length)
    let ev = events[0] as! FlowYieldVaultsEarlyAccess.AccessRevoked
    Test.assertEqual(userA.address, ev.addr)

    revokeEarlyAccess(admin: admin, addr: userA.address)
    events = Test.eventsOfType(Type<FlowYieldVaultsEarlyAccess.AccessRevoked>())
    Test.assertEqual(1, events.length)
}

access(all) fun test_grant_idempotent() {
    grantEarlyAccess(admin: admin, addr: userA.address)
    grantEarlyAccess(admin: admin, addr: userA.address)
}

access(all) fun test_revoke_idempotent() {
    revokeEarlyAccess(admin: admin, addr: userA.address)

    grantEarlyAccess(admin: admin, addr: userA.address)
    revokeEarlyAccess(admin: admin, addr: userA.address)
    revokeEarlyAccess(admin: admin, addr: userA.address)
}

access(all) fun test_revoke_and_re_grant() {
    grantEarlyAccess(admin: admin, addr: userA.address)
    revokeEarlyAccess(admin: admin, addr: userA.address)
    grantEarlyAccess(admin: admin, addr: userA.address)
    Test.assertEqual(true, hasEarlyAccess(userA.address))
    Test.expect(createPosition(signer: userA, path: defaultPath), Test.beSucceeded())
}

access(all) fun test_early_access_is_reusable() {
    grantEarlyAccess(admin: admin, addr: userA.address)
    Test.expect(createPosition(signer: userA, path: /storage/a), Test.beSucceeded())
    Test.expect(createPosition(signer: userA, path: /storage/b), Test.beSucceeded())
    Test.expect(createPosition(signer: userA, path: /storage/c), Test.beSucceeded())
}

// userA (allowed) creates a position and shares a borrow capability with userB (not allowed) via inbox.
// userA retains ownership; userB must not be able to use it.
access(all) fun test_transferred_position_blocked_for_non_allowed_user() {
    grantEarlyAccess(admin: admin, addr: userA.address)
    Test.expect(createPosition(signer: userA, path: defaultPath), Test.beSucceeded())
    Test.expect(transferPositionToInbox(signer: userA, recipient: userB.address), Test.beSucceeded())
    expectFailedWithError(claimPositionAndDeposit(signer: userB, provider: userA.address), "Signer is not in the allowlist")
}

// userA (allowed) creates a position and shares a borrow capability with userB (also allowed) via inbox.
// userA retains ownership; userB must be able to use it.
access(all) fun test_transferred_position_allowed_for_allowed_user() {
    grantEarlyAccess(admin: admin, addr: userA.address)
    grantEarlyAccess(admin: admin, addr: userB.address)
    Test.expect(createPosition(signer: userA, path: defaultPath), Test.beSucceeded())
    Test.expect(transferPositionToInbox(signer: userA, recipient: userB.address), Test.beSucceeded())
    // userB claims the capability and tries to deposit — succeeds because userB is in the allowlist
    Test.expect(claimPositionAndDeposit(signer: userB, provider: userA.address), Test.beSucceeded())
}

access(self) fun expectFailedWithError(_ res: Test.TransactionResult, _ error: String) {
    Test.expect(res, Test.beFailed())
    Test.assertError(res, errorMessage: error)
}
