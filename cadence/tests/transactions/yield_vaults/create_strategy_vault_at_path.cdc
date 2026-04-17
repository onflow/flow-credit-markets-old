import "FlowYieldVaults"
import "FlowYieldVaultsInterfaces"

transaction(name: String, path: StoragePath) {
    prepare(signer: auth(Storage) &Account) {
        let admin = signer.storage.borrow<&FlowYieldVaults.Admin>(from: FlowYieldVaults.adminStoragePath)
            ?? panic("FlowYieldVaults.Admin not found at \(FlowYieldVaults.adminStoragePath)")
        let vault <- admin.createYieldVault(name: name)
        signer.storage.save(<- vault, to: path)
        let ref = signer.storage.borrow<&{FlowYieldVaultsInterfaces.YieldVault}>(from: path)
            ?? panic("vault does not conform to FlowYieldVaultsInterfaces.YieldVault at \(path)")
    }
}
