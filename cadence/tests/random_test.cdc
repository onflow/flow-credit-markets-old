// PLACEHOLDER: this test suite exists to verify that the CI pipeline correctly
// runs Cadence tests, scripts, and transactions. The assertions here are not
// meaningful coverage of contract behavior — replace with real tests once the
// contracts have behavior to exercise.
import Test
import BlockchainHelpers

import "helpers/deployment_helpers.cdc"
import "helpers/actions_helpers.cdc"

access(all) var signer = Test.createAccount()

access(all) var snapShot: UInt64 = 0
access(all) fun beforeEach() { Test.reset(to: snapShot) }

access(all) fun setup() {
    deployAllContracts()
    snapShot = getCurrentBlockHeight()
}

access(all) fun test_script() {
    let result = actionsCount()
    Test.assertEqual(0, result)
    Test.expect(result, Test.beGreaterThan(-1))
    Test.assert(true, message: "Test should be true")
}

access(all) fun test_transaction() {
    actionsIncrementCount(signer: signer)
}
