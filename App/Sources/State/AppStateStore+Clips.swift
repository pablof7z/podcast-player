import Foundation
import os.log

// MARK: - Clips

/// CRUD surface for user-authored transcript excerpts. Mirrors the pattern
/// used by `+Notes` and `+Memories` so all clip mutations route through one
/// place and the `state.didSet` observer in `AppStateStore` picks them up
/// for persistence + Spotlight + widget refresh.
///
/// Auto-snip and the in-app composer both land here so a clip captured from
/// the lock-screen and a clip composed from a transcript share the same
/// storage and the same observer chain.
extension AppStateStore {

    nonisolated private static let clipsLogger = Logger.app("AppStateStore+Clips")

    func addClip(_ clip: Clip) {
        state.clips.append(clip)
        // Wiring contract per `identity-05-synthesis.md` §5.3: every clip
        // source signs and publishes (kind 9802 / NIP-84) except `.agent`,
        // which stays local. Fire-and-forget so a relay outage never blocks
        // the user's local capture.
        if clip.source != .agent {
            Task { try? await UserIdentityStore.shared.publishUserClip(clip) }
        }
    }

    /// Convenience: build + persist in one call. Used by `AutoSnipController`
    /// (auto / headphone / lock-screen pathways). The transcript window may be
    /// `nil` when the episode hasn't been ingested yet — we collapse to an
    /// empty string so the rest of the share stack stays string-typed.
    @discardableResult
    func addClip(
        episodeID: UUID,
        subscriptionID: UUID,
        startMs: Int,
        endMs: Int,
        transcriptText: String? = nil,
        speakerID: UUID? = nil,
        source: Clip.Source = .auto,
        caption: String? = nil
    ) -> Clip {
        let clip = Clip(
            episodeID: episodeID,
            subscriptionID: subscriptionID,
            startMs: startMs,
            endMs: endMs,
            caption: caption,
            speakerID: speakerID?.uuidString,
            transcriptText: transcriptText ?? "",
            source: source
        )
        // Route through the primary `addClip(_:)` so the publish wiring
        // fires uniformly for every entry-point (composer + auto-snip).
        addClip(clip)
        return clip
    }

    func deleteClip(id: UUID) {
        guard let idx = state.clips.firstIndex(where: { $0.id == id }) else { return }
        state.clips.remove(at: idx)
    }

    func clip(id: UUID) -> Clip? {
        state.clips.first(where: { $0.id == id })
    }

    /// Clips for a single episode, newest first. Used by the episode detail
    /// surface and (eventually) the global clips list.
    func clips(forEpisode id: UUID) -> [Clip] {
        state.clips
            .filter { $0.episodeID == id }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
