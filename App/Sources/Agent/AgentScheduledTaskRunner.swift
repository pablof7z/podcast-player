import Foundation
import os.log

/// Fires due recurring tasks as headless `AgentChatSession` runs.
///
/// Lifecycle: created in `AppMain.task` alongside `NostrRelayService`.
/// `podcastDepsProvider` is late-bound from `RootView.task(id:)` once
/// `PlaybackState` is ready — the same pattern the Nostr responder uses.
@MainActor
final class AgentScheduledTaskRunner {
    private let logger = Logger.app("AgentScheduledTaskRunner")
    private let store: AppStateStore

    /// Wired by `RootView` after `PlaybackState` is available.
    var podcastDepsProvider: (() -> PodcastAgentToolDeps)?

    init(store: AppStateStore) {
        self.store = store
    }

    /// Fires one headless session per due task. Tasks are marked run BEFORE
    /// the session starts so a crash mid-run doesn't chain-fire on restart.
    /// `nextRunAt` is advanced to `now + interval` (not the missed scheduled
    /// time), giving miss-once semantics when the app was offline for multiple
    /// periods.
    func runDueTasksIfNeeded() {
        let due = store.scheduledTasks.filter { $0.isDue }
        guard !due.isEmpty else { return }
        for task in due {
            store.markTaskRun(id: task.id)
            Task { await runTask(task) }
        }
    }

    private func runTask(_ task: AgentScheduledTask) async {
        // Credential checking is Rust-owned; the Rust backend returns an error
        // envelope when no key is configured, which surfaces as a failed agent turn.
        let deps = podcastDepsProvider?()
        let session = AgentChatSession(
            store: store,
            podcastDeps: deps,
            history: .shared,
            resumeWindow: 0,
            drainPendingContext: false
        )
        session.isScheduledTask = true
        await session.send(task.prompt, source: .scheduledTask)
        logger.info("Scheduled task '\(task.label, privacy: .public)' completed")
    }
}
