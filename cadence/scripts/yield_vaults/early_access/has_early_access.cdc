import "FlowYieldVaultsEarlyAccess"

access(all) fun main(addr: Address): Bool {
    return FlowYieldVaultsEarlyAccess.passExists(addr: addr)
}
