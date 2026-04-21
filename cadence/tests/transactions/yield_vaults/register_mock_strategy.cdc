import "FlowYieldVaults"
import "MockStrategy"

transaction(name: String) {

    let admin: &FlowYieldVaults.Admin

    prepare(signer: auth(BorrowValue) &Account) {
        self.admin = signer.storage.borrow<&FlowYieldVaults.Admin>(from: FlowYieldVaults.adminStoragePath)
            ?? panic("FlowYieldVaults.Admin not found at \(FlowYieldVaults.adminStoragePath)")
    }

    execute {
        self.admin.registerStrategy(name: name, strategy: MockStrategy.createStrategy())
    }
}
