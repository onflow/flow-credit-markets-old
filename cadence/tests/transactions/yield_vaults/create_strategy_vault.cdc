import "TestYieldVaultGateway"

transaction(name: String) {
    prepare(_: &Account) {}

    execute {
        let vault <- TestYieldVaultGateway.createYieldVault(name: name)
        destroy vault
    }
}
