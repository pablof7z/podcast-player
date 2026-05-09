import Foundation

// MARK: - Episodes

extension AppStateStore {

    // MARK: - Reads

    /// Returns the live episode record matching `id`, or `nil` when not found.
    func episode(id: UUID) -> Episode? {
        state.episodes.first { $0.id == id }
    }

    /// Episodes belonging to the given subscription, newest publish-date first.
    func episodes(forSubscription id: UUID) -> [Episode] {
        state.episodes
            .filter { $0.subscriptionID == id }
            .sorted { $0.pubDate > $1.pubDate }
    }

    /// Episodes the user has started but not finished, ordered by most recent
    /// activity. "Started" is `playbackPosition > 0`. "Finished" is `played`.
    /// Used by the Home tab's in-progress carousel.
    var inProgressEpisodes: [Episode] {
        state.episodes
            .filter { !$0.played && $0.playbackPosition > 0 }
            .sorted { $0.pubDate > $1.pubDate }
    }

    /// Recently published, unplayed episodes across all subscriptions.
    /// Used by the Home tab's "new" feed.
    func recentEpisodes(limit: Int = 30) -> [Episode] {
        state.episodes
            .filter { !$0.played }
            .sorted { $0.pubDate > $1.pubDate }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Writes

    /// Inserts new episodes and updates existing ones (matched by `guid`)
    /// for the given subscription. Episodes whose `guid` already exists in
    /// the store are merged: the publisher fields refresh while the user-
    /// mutable playback state (`playbackPosition`, `played`, `downloadState`,
    /// `transcriptState`) is preserved.
    func upsertEpisodes(_ incoming: [Episode], forSubscription subscriptionID: UUID) {
        guard !incoming.isEmpty else { return }
        var updated = state.episodes
        let existingByGUID = Dictionary(
            updated.enumerated()
                .filter { $0.element.subscriptionID == subscriptionID }
                .map { ($0.element.guid, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        for episode in incoming {
            if let idx = existingByGUID[episode.guid] {
                let prior = updated[idx]
                var merged = episode
                merged.id = prior.id
                merged.playbackPosition = prior.playbackPosition
                merged.played = prior.played
                merged.downloadState = prior.downloadState
                merged.transcriptState = prior.transcriptState
                updated[idx] = merged
            } else {
                updated.append(episode)
            }
        }
        state.episodes = updated
    }

    /// Persists a playback-position update without rewriting the entire episode.
    /// Called frequently from the audio engine's progress observer.
    func setEpisodePlaybackPosition(_ id: UUID, position: TimeInterval) {
        guard let idx = state.episodes.firstIndex(where: { $0.id == id }) else { return }
        guard state.episodes[idx].playbackPosition != position else { return }
        state.episodes[idx].playbackPosition = position
    }

    /// Marks the episode as fully played (sets `played = true`, zeroes the
    /// position so a re-play starts from the top).
    func markEpisodePlayed(_ id: UUID) {
        guard let idx = state.episodes.firstIndex(where: { $0.id == id }) else { return }
        state.episodes[idx].played = true
        state.episodes[idx].playbackPosition = 0
    }

    /// Reverts an accidental "mark played".
    func markEpisodeUnplayed(_ id: UUID) {
        guard let idx = state.episodes.firstIndex(where: { $0.id == id }) else { return }
        state.episodes[idx].played = false
    }

    /// Updates the episode's local download lifecycle (queued / downloading /
    /// downloaded / failed). The audio engine reads `downloaded` to decide
    /// between streaming and local file URLs.
    func setEpisodeDownloadState(_ id: UUID, state newState: DownloadState) {
        guard let idx = state.episodes.firstIndex(where: { $0.id == id }) else { return }
        state.episodes[idx].downloadState = newState
    }

    /// Updates the episode's transcript ingestion lifecycle.
    func setEpisodeTranscriptState(_ id: UUID, state newState: TranscriptState) {
        guard let idx = state.episodes.firstIndex(where: { $0.id == id }) else { return }
        state.episodes[idx].transcriptState = newState
    }
}
