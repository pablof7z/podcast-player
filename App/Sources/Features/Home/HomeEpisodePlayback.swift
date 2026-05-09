import SwiftUI

// MARK: - HomeEpisodePlayback

/// Adapts a real `Episode` (Lane 2) into the `MockPlayerEpisode` shape the
/// player UI binds against today. When Lane 1's real `PlaybackState` lands
/// (renamed from `MockPlaybackState`), the Player agent will replace this
/// adapter with a direct `play(episode:)` on the engine. Until then this is
/// the binding seam between Home and Player.
///
/// Lives in the Home lane on purpose: `Features/Player/*` is owned by another
/// agent. Extending `MockPlaybackState` from a Home-owned file keeps the
/// adapter discoverable here without touching the player surface.
@MainActor
extension MockPlaybackState {

    /// Loads a real `Episode` into the player and starts playback.
    ///
    /// - Parameters:
    ///   - episode: The episode to play. Its `playbackPosition` seeds the
    ///     player's `currentTime` so resume works.
    ///   - subscription: Optional show context used for the display name and
    ///     artwork fallback. Pass `nil` only when the show is unknown.
    func play(episode: Episode, in subscription: PodcastSubscription?) {
        let projection = MockPlayerEpisode(
            id: episode.id.uuidString,
            showName: subscription?.title ?? "",
            episodeNumber: nil,
            title: episode.title,
            chapterTitle: nil,
            duration: episode.duration ?? 0,
            primaryArtColor: AppTheme.Tint.agentSurface,
            secondaryArtColor: .secondary
        )
        self.episode = projection
        self.transcript = []
        self.currentTime = max(0, min(episode.playbackPosition, projection.duration))
        self.play()
    }
}
