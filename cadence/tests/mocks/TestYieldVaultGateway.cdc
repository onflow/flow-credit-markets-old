import "FlowYieldVaults"
import "FlowYieldVaultsInterfaces"

/// Test-only helper deployed alongside `FlowYieldVaults` so that tests can
/// invoke the `access(account)` `createYieldVault` directly, without going
/// through the early-access gate. Production callers must use
/// `FlowYieldVaultsEarlyAccess` (for now) or `FlowYieldVaults` directly
/// once the gate is lifted.
access(all) contract TestYieldVaultGateway {
    access(all) fun createYieldVault(name: String): @{FlowYieldVaultsInterfaces.YieldVault} {
        return <- FlowYieldVaults.createYieldVault(name: name)
    }
}
