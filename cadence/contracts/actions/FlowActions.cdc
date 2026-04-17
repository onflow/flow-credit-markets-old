import "FungibleToken"

access(all) contract FlowActions {

    // Interfaces are not fixed and still under development.
    // This is the typical EVM interface translated to cadence.
    // Necessary to setup FlowYieldVaults structure.
    access(all) struct interface Swapper {
        access(all) token0: Type
        access(all) token1: Type
        access(all) fee: UInt32

        /// Exact Input: "I have this many tokens, give me whatever they are worth"
        access(all) fun quoteExactInput(
            zeroForOne: Bool,
            amountIn: UFix64
        ): UFix64

        /// Exact Output: "I want exactly this many tokens, how much do I need to pay?"
        access(all) fun quoteExactOutput(
            zeroForOne: Bool,
            amountOut: UFix64
        ): UFix64

        access(all) fun swap(
            zeroForOne: Bool,
            inVault: @{FungibleToken.Vault}
        ): @{FungibleToken.Vault}
    }

    /// FYV needs this functionality but it doesn't have to be implemented like this!
    /// this is dangerous!! if a 3rd party provides a type and we are executing
    /// createEmptyVault any code can be run. (reentrancy, etc)
    access(all) fun getEmptyVault(_ vaultType: Type): @{FungibleToken.Vault} {
        post {
            result.getType() == vaultType:
            "Invalid Vault returned - expected \(vaultType.identifier) but returned \(result.getType().identifier)"
        }
        return <- getAccount(vaultType.address!)
            .contracts
            .borrow<&{FungibleToken}>(name: vaultType.contractName!)!
            .createEmptyVault(vaultType: vaultType)
    }
}
