import Foundation
import os.log

// MARK: - Clips
//
// Stub extension introduced by the auto-snip / AI-chapters agent. Provides
// the minimal surface the player and snip controller need: an `addClip` entry
// point that persists through `ClipStore`. The sister "clips" agent is
// expected to extend / replace this with full state-store integration; the
// call sites won't change.

extension AppStateStore {

    nonisolated private static let clipsLogger = Logger.app("AppStateStore+Clips")

    /// Persist a snip. Routes through `ClipStore` (file-backed, parallel to
    /// `TranscriptStore`) so the monolithic `AppState` blob doesn't grow on
    /// every capture and so the sister clips-agent can swap the implementation
    /// without breaking callers.
    @discardableResult
    func addClip(_ clip: Clip) -> Clip {
        do {
            try ClipStore.shared.save(clip)
        } catch {
            Self.clipsLogger.error(
                "addClip failed for \(clip.id, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
        return clip
    }

    /// Convenience: build + persist in one call. Used by `AutoSnipController`.
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
            transcriptText: transcriptText,
            speakerID: speakerID,
            source: source
        )
        return addClip(clip)
    }
}
