import Foundation

// MARK: - Episodes

extension AppStateStore {

    // MARK: - Reads
    //
    // Reads fold the position-debounce cache into the result so a freshly-
    // updated playhead is visible to UI surfaces (in-progress carousel,
    // resume-from-position, episode detail) without waiting for the next
    // disk flush. See `AppStateStore+PositionDebounce.swift` for the
    // cache's lifecycle.

    /// Returns the live episode record matching `id`, or `nil` when not found.
    func episode(id: UUID) -> Episode? {
        guard var found = state.episodes.first(where: { $0.id == id }) else { return nil }
        if let cached = cachedPosition(for: id) {
            found.playbackPosition = cached
        }
        return found
    }

    /// Episodes belonging to the given subscription, newest publish-date first.
    ///
    /// O(1) lookup against `episodeIndexesByShow` plus an O(K) position-cache fold
    /// (K = pending position writes, typically ≤ 1). Was O(N) filter + O(N
    /// log N) sort, called from `ShowDetailView`'s body for every render —
    /// 2,853 episodes for "The Daily" alone.
    func episodes(forSubscription id: UUID) -> [Episode] {
        episodesForShowView(id)
    }

    /// Episodes the user has started but not finished, ordered by most recent
    /// activity. "Started" is `playbackPosition > 0`. "Finished" is `played`.
    /// Used by the Home tab's in-progress carousel.
    ///
    /// Backed by `inProgressEpisodesCached`. The read-side helper folds the
    /// position-debounce cache so an episode whose first tick hasn't flushed
    /// yet still surfaces here.
    var inProgressEpisodes: [Episode] {
        inProgressEpisodesView()
    }

    /// Recently published, unplayed episodes across all subscriptions.
    /// Used by the Home tab's "new" feed.
    ///
    /// Backed by `recentEpisodesCached` (top `Self.recentEpisodesCacheLimit`).
    /// Larger limits fall back to a one-off recompute against `state.episodes`.
    func recentEpisodes(limit: Int = 30) -> [Episode] {
        recentEpisodesView(limit: limit)
    }

    // MARK: - Writes

    /// Inserts new episodes and updates existing ones (matched by `guid`)
    /// for the given subscription. Episodes whose `guid` already exists in
    /// the store are merged: the publisher fields refresh while the user-
    /// mutable playback state (`playbackPosition`, `played`, `downloadState`,
    /// `transcriptState`) is preserved.
    ///
    /// When `evaluateAutoDownload` is true, triggers
    /// `EpisodeDownloadService.evaluateAutoDownload(...)` for genuinely new
    /// episode IDs. Initial subscription/import paths pass false so historical
    /// back-catalog episodes do not queue thousands of downloads at once.
    @discardableResult
    func upsertEpisodes(
        _ incoming: [Episode],
        forSubscription subscriptionID: UUID,
        evaluateAutoDownload: Bool = false
    ) -> [UUID] {
        guard !incoming.isEmpty else { return [] }
        var updated = state.episodes
        let existingByGUID = Dictionary(
            updated.enumerated()
                .filter { $0.element.subscriptionID == subscriptionID }
                .map { ($0.element.guid, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        var newlyInserted: [UUID] = []
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
                newlyInserted.append(episode.id)
            }
        }
        performMutationBatch {
            state.episodes = updated
            // The didSet fingerprint catches count changes but misses pure
            // merges where count stays equal; explicit invalidation covers both.
            invalidateEpisodeProjections()
        }
        if evaluateAutoDownload, !newlyInserted.isEmpty {
            // Attach the service to this store on first reach so the
            // download lifecycle, the auto-download path, and the AudioEngine
            // local-file fallback all see the same `appStore`. Idempotent.
            EpisodeDownloadService.shared.attach(appStore: self)
            EpisodeDownloadService.shared.evaluateAutoDownload(
                forSubscription: subscriptionID,
                newEpisodeIDs: newlyInserted
            )
            // Fire publisher-transcript ingestion for the new IDs so we
            // don't depend on the user manually opening Episode Detail to
            // discover a transcript exists. Settings-gated; the service
            // bails fast when the toggle is off.
            TranscriptIngestService.shared.evaluateAutoIngest(
                newEpisodeIDs: newlyInserted
            )
        }
        return newlyInserted
    }

    // `setEpisodePlaybackPosition(_:position:)` is implemented in
    // `AppStateStore+PositionDebounce.swift`. It writes through an in-memory
    // cache and only mutates `state.episodes` (firing the expensive save) on
    // an eager-first / 5-second-trailing / 30-second-cap schedule. This is
    // the file's single highest-frequency caller; routing it through the
    // cache is the entire point of that companion file.

    /// Marks the episode as fully played (sets `played = true`, zeroes the
    /// position so a re-play starts from the top).
    ///
    /// **Flushes the position cache before mutating.** Without the flush,
    /// a cached non-zero position for `id` would still be in
    /// `positionCache`; clearing the cache *after* the played-true write
    /// is fine, but if the app crashed between the flush and the
    /// played=true save, the user would lose both the played flag *and*
    /// the actual end-position. Flushing first means the worst case is
    /// "played=false but position correct" — recoverable next time the
    /// user opens the episode.
    func markEpisodePlayed(_ id: UUID) {
        flushPendingPositions()
        guard let idx = state.episodes.firstIndex(where: { $0.id == id }) else { return }
        let wasDownloaded: Bool
        if case .downloaded = state.episodes[idx].downloadState { wasDownloaded = true }
        else { wasDownloaded = false }
        var episodes = state.episodes
        episodes[idx].played = true
        episodes[idx].playbackPosition = 0
        // The cache entry for this episode (if any) is now stale — we
        // just persisted position=0 deliberately. Drop it so the next
        // tick (e.g. a stray engine observer firing post-end) doesn't
        // resurrect a non-zero position on its first eager save.
        performMutationBatch {
            state.episodes = episodes
            positionCache.removeValue(forKey: id)
            // Cached unplayed counts + in-progress feed must drop this episode.
            invalidateEpisodeProjections()
        }
        // Honour the user's "Delete after played" setting. Runs after the
        // mutation batch so the played=true write is on disk before the
        // download service flips downloadState back to .notDownloaded.
        if wasDownloaded, state.settings.autoDeleteDownloadsAfterPlayed {
            EpisodeDownloadService.shared.delete(episodeID: id)
        }
    }

    /// Reverts an accidental "mark played".
    func markEpisodeUnplayed(_ id: UUID) {
        guard let idx = state.episodes.firstIndex(where: { $0.id == id }) else { return }
        var episodes = state.episodes
        episodes[idx].played = false
        performMutationBatch {
            state.episodes = episodes
            // Cached unplayed counts + recent feed must re-include this episode.
            invalidateEpisodeProjections()
        }
    }

    /// Updates the episode's local download lifecycle (queued / downloading /
    /// downloaded / failed). The audio engine reads `downloaded` to decide
    /// between streaming and local file URLs.
    func setEpisodeDownloadState(_ id: UUID, state newState: DownloadState) {
        guard let idx = state.episodes.firstIndex(where: { $0.id == id }) else { return }
        var episodes = state.episodes
        episodes[idx].downloadState = newState
        performMutationBatch {
            state.episodes = episodes
            // Cached `hasDownloadedByShow` set may now need to add or drop this subscription.
            invalidateEpisodeProjections()
        }
    }

    /// Updates the episode's transcript ingestion lifecycle.
    func setEpisodeTranscriptState(_ id: UUID, state newState: TranscriptState) {
        guard let idx = state.episodes.firstIndex(where: { $0.id == id }) else { return }
        var episodes = state.episodes
        episodes[idx].transcriptState = newState
        performMutationBatch {
            state.episodes = episodes
            // Cached `hasTranscribedByShow` set may now need to add or drop this subscription.
            invalidateEpisodeProjections()
        }
    }

    /// Persist hydrated chapters for an episode. Used by
    /// `ChaptersHydrationService` after asynchronously fetching the JSON
    /// referenced by `episode.chaptersURL`. No-op when `chapters` is empty
    /// AND the episode already has chapters — we never overwrite real data
    /// with an empty result.
    func setEpisodeChapters(_ id: UUID, chapters: [Episode.Chapter]) {
        guard let idx = state.episodes.firstIndex(where: { $0.id == id }) else { return }
        if chapters.isEmpty, let existing = state.episodes[idx].chapters, !existing.isEmpty {
            return
        }
        var episodes = state.episodes
        episodes[idx].chapters = chapters.isEmpty ? nil : chapters
        state.episodes = episodes
    }
}
