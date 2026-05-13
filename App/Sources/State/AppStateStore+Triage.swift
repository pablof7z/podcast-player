import Foundation

// MARK: - AppStateStore + Triage
//
// Mutation surface for the AI Inbox triage pass. The triage pass produces
// one decision per untriaged episode; callers funnel the full batch through
// `applyTriageDecisions(_:)` to land them in a single mutation batch so
// SwiftUI surfaces re-render once per pass instead of once per episode.

extension AppStateStore {

    /// One row produced by the triage pass — an episode id paired with the
    /// agent's decision and (for `.inbox`) the one-line rationale shown on
    /// the Home Inbox card.
    struct TriagePatch: Sendable, Hashable {
        let episodeID: UUID
        let decision: TriageDecision
        let rationale: String?
    }

    /// Apply a batch of triage decisions to `state.episodes`. Single
    /// mutation batch + projection invalidation; missing episode IDs
    /// (e.g. removed between the LLM call and the apply) are silently
    /// skipped. Safe to call with an empty array.
    func applyTriageDecisions(_ patches: [TriagePatch]) {
        guard !patches.isEmpty else { return }
        let byID = Dictionary(uniqueKeysWithValues: patches.map { ($0.episodeID, $0) })
        var episodes = state.episodes
        var changed = false
        for idx in episodes.indices {
            guard let patch = byID[episodes[idx].id] else { continue }
            // Skip if the same decision is already recorded — avoids
            // writing a no-op patch that would still bust the projection
            // cache and trigger a full re-encode of the episodes array.
            if episodes[idx].triageDecision == patch.decision,
               episodes[idx].triageRationale == patch.rationale {
                continue
            }
            episodes[idx].triageDecision = patch.decision
            episodes[idx].triageRationale = patch.decision == .inbox ? patch.rationale : nil
            changed = true
        }
        guard changed else { return }
        performMutationBatch {
            state.episodes = episodes
            invalidateEpisodeProjections()
        }
    }

    /// Clear a single episode's triage state. Used when the user
    /// manually rescues an archived episode (future surface) or when a
    /// re-triage pass wants to overwrite a previous run.
    func clearTriageDecision(_ episodeID: UUID) {
        guard let idx = state.episodes.firstIndex(where: { $0.id == episodeID }) else { return }
        guard state.episodes[idx].triageDecision != nil else { return }
        var episodes = state.episodes
        episodes[idx].triageDecision = nil
        episodes[idx].triageRationale = nil
        performMutationBatch {
            state.episodes = episodes
            invalidateEpisodeProjections()
        }
    }
}
