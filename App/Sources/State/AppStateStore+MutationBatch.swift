import Foundation
import WidgetKit

// MARK: - AppStateStore + Mutation batching

extension AppStateStore {

    /// Central `state.didSet` handler. Most mutations should persist and
    /// refresh derived indexes immediately, but import/refresh flows can wrap
    /// many state edits in `performMutationBatch` so the expensive work runs
    /// once after the batch lands.
    func handleStateDidSet(previousEpisodes: [Episode]) {
        if Self.episodesFingerprintChanged(previousEpisodes, state.episodes) {
            markEpisodeProjectionsDirty()
        }
        markStateSideEffectsDirty()
    }

    func performMutationBatch(_ body: () -> Void) {
        mutationBatchDepth += 1
        defer {
            mutationBatchDepth -= 1
            if mutationBatchDepth == 0 {
                flushDeferredMutationWork()
            }
        }
        body()
    }

    func markEpisodeProjectionsDirty() {
        if mutationBatchDepth > 0 {
            deferredEpisodeProjectionRebuild = true
        } else {
            recomputeEpisodeProjections()
        }
    }

    private func markStateSideEffectsDirty() {
        if mutationBatchDepth > 0 {
            deferredStateSideEffects = true
        } else {
            runStateSideEffects()
        }
    }

    private func flushDeferredMutationWork() {
        if deferredEpisodeProjectionRebuild {
            deferredEpisodeProjectionRebuild = false
            recomputeEpisodeProjections()
        }
        if deferredStateSideEffects {
            deferredStateSideEffects = false
            runStateSideEffects()
        }
    }

    private func runStateSideEffects() {
        let snapshot = state
        persistence.save(snapshot)
        scheduleSpotlightReindex(for: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        iCloudSettingsSync.shared.push(state.settings)
    }

    func scheduleSpotlightReindex(for snapshot: AppState, delay: Duration = .milliseconds(750)) {
        spotlightReindexTask?.cancel()
        spotlightReindexTask = Task { [snapshot] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                SpotlightIndexer.reindex(state: snapshot)
            }.value
        }
    }
}
