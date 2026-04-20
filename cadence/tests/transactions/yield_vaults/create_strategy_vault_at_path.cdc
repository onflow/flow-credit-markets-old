import "TestYieldVaultGateway"
import "FlowYieldVaultsInterfaces"

transaction(name: String, path: StoragePath) {
    prepare(signer: auth(Storage) &Account) {
        let vault <- TestYieldVaultGateway.createYieldVault(name: name)
        signer.storage.save(<- vault, to: path)
        let _ = signer.storage.borrow<&{FlowYieldVaultsInterfaces.YieldVault}>(from: path)
            ?? panic("vault does not conform to FlowYieldVaultsInterfaces.YieldVault at \(path)")
    }
}
