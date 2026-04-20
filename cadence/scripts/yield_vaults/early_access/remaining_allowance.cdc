import "FlowYieldVaultsEarlyAccess"

access(all) fun main(addr: Address): UInt64 {
    return FlowYieldVaultsEarlyAccess.remainingAllowance(addr: addr)
}
