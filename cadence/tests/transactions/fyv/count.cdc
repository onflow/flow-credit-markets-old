import "FlowYieldVaults"

transaction(amount: Int) {
    prepare(signer: &Account) {}

    execute {
        for i in InclusiveRange(0, amount-1) {
            FlowYieldVaults.increment()
        }
    }
}