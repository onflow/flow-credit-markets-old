access(all) contract MockContract {
    access(self) var counter: Int

    init() {
        self.counter = 0
    }

    access(all) fun increment() {
        self.counter = self.counter + 1
    }
}