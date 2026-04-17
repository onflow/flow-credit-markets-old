access(all) contract FlowYieldVaults {

    access(all) event PositionCreated()

    access(all) entitlement Action

    access(all) resource Position {
        access(all) fun deposit() {
            return
        }

        access(all) fun withdraw() {
            return
        }
    }

    // Will be access(all) after early access
    access(account) fun createPosition(): @Position {
        let position <- create Position()
        emit PositionCreated()
        return <- position
    }

    init() {}
}
