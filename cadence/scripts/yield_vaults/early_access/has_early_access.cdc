import "FlowYieldVaultsEarlyAccess"

access(all) fun main(passUUID: UInt64): Bool {
    return FlowYieldVaultsEarlyAccess.passExists(passUUID: passUUID)
}
