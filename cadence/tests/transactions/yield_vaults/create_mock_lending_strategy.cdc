import "FlowYieldVaults"
import "FlowYieldVaultsLendingStrategies"
import "MockSwapper"
import "MockToken"

transaction(name: String) {

    let admin: &FlowYieldVaults.Admin

    prepare(signer: auth(BorrowValue) &Account) {
        self.admin = signer.storage.borrow<&FlowYieldVaults.Admin>(from: FlowYieldVaults.adminStoragePath)
            ?? panic("FlowYieldVaults.Admin not found at \(FlowYieldVaults.adminStoragePath)")
    }

    execute {
        let tokenType = Type<@MockToken.Vault>()
        let strategy = FlowYieldVaultsLendingStrategies.createLendingStrategy(
            collateralDebtSwapper: MockSwapper.createSwapper(token0: tokenType, token1: tokenType),
            debtYieldSwapper: MockSwapper.createSwapper(token0: tokenType, token1: tokenType),
            yieldTokenType: tokenType,
            debtTokenType: tokenType,
            collateralTokenType: tokenType,
            alpContractName: "MockALP",
            minHealth: 1.5,
            maxHealth: 2.0
        )
        self.admin.registerStrategy(name: name, strategy: strategy)
    }
}
