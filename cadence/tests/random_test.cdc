import Test
import BlockchainHelpers

import "deployment_helpers.cdc"
import "test_helpers.cdc"

access(all) var signer = Test.createAccount()

access(all) var snapShot: UInt64 = 0

access(all) fun beforeEach() {
    if snapShot != getCurrentBlockHeight() {
        Test.reset(to: snapShot)
    }
}

access(all) fun setup() {
    deployContracts()
    snapShot = getCurrentBlockHeight()
}

access(all) fun test_deploy_contracts() {
    Test.assert(true, message: "Test should be true")
    let measured = 1.0
    Test.assertEqual(1.0, measured)
    Test.expect(measured, Test.beGreaterThan(0.5))

    var count = actionsCount()
    Test.assertEqual(count, 0)
    incrementFYVCount(amount: 10, signer: signer)
    count = actionsCount()
    Test.assertEqual(count, 10)
}

access(all) fun test_actions_count_1() {
    var count = actionsCount()
    Test.assertEqual(count, 0)
    incrementFYVCount(amount: 10, signer: signer)
    count = actionsCount()
    Test.assertEqual(count, 10)
}

access(all) fun test_actions_count_2() {
    var count = actionsCount()
    Test.assertEqual(count, 0)
    incrementFYVCount(amount: 10, signer: signer)
    count = actionsCount()
    Test.assertEqual(count, 10)
}