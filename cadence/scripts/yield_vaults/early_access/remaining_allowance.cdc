import "FlowYieldVaultsEarlyAccess"

access(all) fun main(passUUID: UInt64): UInt64 {
    return FlowYieldVaultsEarlyAccess.remainingAllowance(passUUID: passUUID)
}
