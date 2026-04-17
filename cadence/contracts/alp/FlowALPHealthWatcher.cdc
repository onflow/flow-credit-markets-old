import "FlowALPHealthWatcherIdea"

// -----------------------------------------------------------------------------
// ⚠️  DISCLAIMER — DRAFT / SUBJECT TO CHANGE
// -----------------------------------------------------------------------------
// This is a placeholder health-watcher implementation that exists only to
// unblock the FlowYieldVaults lending-strategy prototype. The real watcher
// semantics (registration, triggering, callbacks) will replace this whole
// contract. Do not build on it outside of this repo.
// -----------------------------------------------------------------------------

access(all) contract FlowALPHealthWatcher {

    access(all) resource Watcher: FlowALPHealthWatcherIdea.Watcher {}

    access(all) fun createWatcher(): @Watcher {
        return <- create Watcher()
    }
}
