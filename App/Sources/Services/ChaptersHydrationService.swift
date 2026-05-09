import Foundation
import os.log

// MARK: - ChaptersHydrationService

/// Coordinates async fetches of Podcasting 2.0 `chaptersURL` JSON and writes
/// the resulting chapters back to `AppStateStore`. UI surfaces (`PlayerView`,
/// `EpisodeDetailView`) call `hydrateIfNeeded(_:)` from `.task`; the service
/// deduplicates concurrent and repeat requests so opening an episode several
/// times in one session never spawns more than one fetch per URL.
///
/// Errors are logged and swallowed — chapters are nice-to-have. A failed
/// fetch is recorded in `attempted` so we don't retry that URL within the
/// same app launch.
@MainActor
final class ChaptersHydrationService {

    static let shared = ChaptersHydrationService()

    private static let logger = Logger.app("ChaptersHydration")

    private let client: ChaptersClient
    /// Tracks which `chaptersURL`s we've already fetched (or are fetching)
    /// this session. Keyed by absolute URL so two episodes that happen to
    /// reference the same JSON file share one network round-trip.
    private var attempted: [URL: Task<Void, Never>] = [:]

    init(client: ChaptersClient = ChaptersClient()) {
        self.client = client
    }

    /// Fetch chapters for `episode` if it has a `chaptersURL` and doesn't
    /// already have inline chapters. Idempotent per session — calling this
    /// repeatedly for the same episode never re-fetches.
    func hydrateIfNeeded(episode: Episode, store: AppStateStore) {
        guard let url = episode.chaptersURL else { return }
        // Inline chapters from the RSS extension take priority — if a feed
        // ships both `<podcast:chapters>` and `chaptersURL`, the inline
        // version is authoritative.
        if let existing = episode.chapters, !existing.isEmpty { return }
        guard attempted[url] == nil else { return }

        let episodeID = episode.id
        let task = Task { [client] in
            do {
                let chapters = try await client.fetch(url: url)
                store.setEpisodeChapters(episodeID, chapters: chapters)
                Self.logger.info("Hydrated \(chapters.count) chapters for episode \(episodeID, privacy: .public)")
            } catch {
                Self.logger.notice(
                    "Chapters fetch failed for \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
        attempted[url] = task
    }

    /// Test hook: clears the per-session dedup cache so a fresh fetch can
    /// be observed. Production code never needs this.
    func resetForTesting() {
        for (_, task) in attempted { task.cancel() }
        attempted.removeAll()
    }
}
