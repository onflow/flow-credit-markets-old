// -----------------------------------------------------------------------------
// ⚠️  DISCLAIMER — DRAFT / SUBJECT TO CHANGE
// -----------------------------------------------------------------------------
// This contract is a placeholder shim needed only to wire up the
// FlowYieldVaults lending-strategy prototype. The `Callback` and `Watcher`
// shapes will change once the real ALP health-monitoring design lands.
// Do not build on this contract outside of this repo.
// -----------------------------------------------------------------------------

access(all) contract interface FlowALPHealthWatcherIdea {

    access(all) struct interface Callback {
        access(all) fun healthWatcherCallback()
    }

    access(all) resource interface Watcher {}

    access(contract) fun createWatcher(): @{Watcher}
}
