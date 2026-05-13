import Foundation

// MARK: - AutoDownloadPolicy

extension EpisodeDownloadService {

    /// Evaluates the per-podcast `AutoDownloadPolicy` against a batch of
    /// episode IDs that were just inserted by `upsertEpisodes`. Queues the
    /// matching ones via `download(episodeID:)`.
    ///
    /// - Parameter newEpisodeIDs: episodes inserted in publish-date order
    ///   (newest first is fine — we sort defensively).
    func evaluateAutoDownload(forPodcast podcastID: UUID, newEpisodeIDs: [UUID]) {
        guard !newEpisodeIDs.isEmpty,
              let store = appStore,
              store.podcast(id: podcastID) != nil else { return }
        // Honour any per-category auto-download override before falling back
        // to the per-podcast policy. `effectiveAutoDownload` resolves to the
        // subscription's `autoDownload` when no category settings apply.
        let policy = store.effectiveAutoDownload(forPodcast: podcastID)
        if case .off = policy.mode { return }
        // Resolve each ID to an Episode and sort by pubDate desc.
        let episodes: [Episode] = newEpisodeIDs
            .compactMap { store.episode(id: $0) }
            .sorted { $0.pubDate > $1.pubDate }
        let targets: [Episode]
        switch policy.mode {
        case .off:
            return
        case .latestN(let n):
            targets = Array(episodes.prefix(max(0, n)))
        case .allNew:
            targets = episodes
        }
        if policy.wifiOnly, !isOnWiFi {
            for episode in targets {
                queueAutoDownload(episode)
            }
            logger.notice(
                "auto-download queued for \(podcastID, privacy: .public) — Wi-Fi unavailable"
            )
            return
        }
        for episode in targets {
            // Only queue ones we don't already have on disk / in flight.
            switch episode.downloadState {
            case .downloaded, .downloading:
                continue
            default:
                download(episodeID: episode.id)
            }
        }
    }

    func resumeQueuedDownloadsIfPossible() {
        guard isOnWiFi, let store = appStore else { return }
        let queued = store.state.episodes.filter {
            if case .queued = $0.downloadState { return true }
            return false
        }
        for episode in queued {
            let policy = store.effectiveAutoDownload(forPodcast: episode.podcastID)
            if case .off = policy.mode { continue }
            download(episodeID: episode.id)
        }
    }

    private func queueAutoDownload(_ episode: Episode) {
        guard let store = appStore else { return }
        switch episode.downloadState {
        case .downloaded, .downloading, .queued:
            return
        case .notDownloaded, .failed:
            store.setEpisodeDownloadState(episode.id, state: .queued)
        }
    }
}
