access(all) contract FlowYieldVaults {

    access(self) var counter: Int

    // Event to be emitted when the counter is incremented
    access(all) event CounterIncremented(newCount: Int)

    // Event to be emitted when the counter is decremented
    access(all) event CounterDecremented(newCount: Int)

    init() {
        self.counter = 0
    }

    // Public function to increment the counter
    access(all) fun increment() {
        self.counter = self.counter + 1
        emit CounterIncremented(newCount: self.counter)
    }

    // Public function to decrement the counter
    access(all) fun decrement() {
        self.counter = self.counter - 1
        emit CounterDecremented(newCount: self.counter)
    }

    // Public function to get the current count
    view access(all) fun count(): Int {
        return self.counter
    }
}
