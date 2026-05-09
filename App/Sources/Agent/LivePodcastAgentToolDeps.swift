import Foundation
import os.log

// MARK: - LivePodcastAgentToolDeps
//
// Wires the lane-10 podcast tool surface (`AgentTools.dispatchPodcast`) to the
// real services that ship in the app:
//
//   • `PodcastAgentRAGSearchProtocol`  → `LivePodcastRAGAdapter`
//   • `WikiStorageProtocol`            → `LiveWikiStorageAdapter`
//   • `BriefingComposerProtocol`       → `LiveBriefingComposerAdapter`
//   • `EpisodeSummarizerProtocol`      → `LiveEpisodeSummarizerAdapter`
//   • `EpisodeFetcherProtocol`         → `LiveEpisodeFetcherAdapter`
//   • `PlaybackHostProtocol`           → `LivePlaybackHostAdapter`
//   • `PerplexityClientProtocol`       → `PerplexityClient`
//
// Constructed once per `AgentChatSession` / `AgentRelayBridge`, the bundle
// holds weak references to `AppStateStore` and `PlaybackState` so the agent
// adapters never extend their lifetimes. Heavy adapters (RAG, Briefing,
// Summarizer) live in their own files; the small ones live here.

@MainActor
enum LivePodcastAgentToolDeps {

    static let logger = Logger.app("AgentTools")

    /// Build a `PodcastAgentToolDeps` bundle wired to the live services.
    /// Call once at session construction; pass the result through to
    /// `AgentTools.dispatchPodcast(...)` for every tool call.
    static func make(
        store: AppStateStore,
        playback: PlaybackState
    ) -> PodcastAgentToolDeps {
        PodcastAgentToolDeps(
            rag: LivePodcastRAGAdapter(store: store),
            wiki: LiveWikiStorageAdapter(),
            briefing: LiveBriefingComposerAdapter(store: store),
            summarizer: LiveEpisodeSummarizerAdapter(store: store),
            fetcher: LiveEpisodeFetcherAdapter(store: store),
            playback: LivePlaybackHostAdapter(store: store, playback: playback),
            perplexity: PerplexityClient()
        )
    }
}

// MARK: - Wiki adapter

/// Wraps `WikiStorage.shared` so the agent's `query_wiki` tool can find pages
/// by topic (substring title or summary match) without dragging the caller
/// through the inventory + JSON-decode dance.
struct LiveWikiStorageAdapter: WikiStorageProtocol {

    func queryWiki(topic: String, scope: PodcastID?, limit: Int) async throws -> [WikiHit] {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        let scopeFilter: WikiScope? = scope.flatMap { UUID(uuidString: $0) }.map { .podcast($0) }
        return try await Task.detached(priority: .utility) {
            let pages = try WikiStorage.shared.allPages()
            let filtered = pages
                .filter { page in
                    if let scopeFilter, page.scope != scopeFilter { return false }
                    return page.title.lowercased().contains(trimmed)
                        || page.summary.lowercased().contains(trimmed)
                }
                .sorted { $0.generatedAt > $1.generatedAt }
                .prefix(limit)
            return filtered.map { page in
                WikiHit(
                    pageID: page.id.uuidString,
                    title: page.title,
                    excerpt: String(page.summary.prefix(280)),
                    score: nil
                )
            }
        }.value
    }
}

// MARK: - Fetcher adapter

/// Resolves episode existence + display metadata from the in-memory
/// `AppStateStore`. Fast — every lookup is a linear scan over the episode
/// array, but the array is bounded by user subscriptions so this is fine.
struct LiveEpisodeFetcherAdapter: EpisodeFetcherProtocol {

    weak var store: AppStateStore?

    init(store: AppStateStore) {
        self.store = store
    }

    func episodeExists(episodeID: EpisodeID) async -> Bool {
        guard let uuid = UUID(uuidString: episodeID) else { return false }
        return await store?.episode(id: uuid) != nil
    }

    func episodeMetadata(
        episodeID: EpisodeID
    ) async -> (podcastTitle: String, episodeTitle: String, durationSeconds: Int?)? {
        guard let store, let uuid = UUID(uuidString: episodeID),
              let episode = await store.episode(id: uuid) else { return nil }
        let subscription = await store.state.subscriptions.first { $0.id == episode.subscriptionID }
        return (
            podcastTitle: subscription?.title ?? "",
            episodeTitle: episode.title,
            durationSeconds: episode.duration.map { Int($0) }
        )
    }
}

// MARK: - Playback adapter

/// Drives the live `PlaybackState` from agent tool calls. Uses weak refs so
/// the agent surface never extends the player's lifetime past the SwiftUI
/// scene that owns it.
final class LivePlaybackHostAdapter: PlaybackHostProtocol, @unchecked Sendable {

    private let logger = Logger.app("AgentTools")
    weak var store: AppStateStore?
    weak var playback: PlaybackState?

    init(store: AppStateStore, playback: PlaybackState) {
        self.store = store
        self.playback = playback
    }

    func playEpisodeAt(episodeID: EpisodeID, timestampSeconds: Double) async {
        await MainActor.run {
            guard let store, let playback,
                  let uuid = UUID(uuidString: episodeID),
                  let episode = store.episode(id: uuid) else {
                logger.error("playEpisodeAt: unknown episode \(episodeID, privacy: .public)")
                return
            }
            playback.setEpisode(episode)
            playback.seek(to: timestampSeconds)
            playback.play()
            logger.info("playEpisodeAt: started \(episode.title, privacy: .public) at \(timestampSeconds)")
        }
    }

    func setNowPlaying(episodeID: EpisodeID, timestampSeconds: Double?) async {
        await MainActor.run {
            guard let store, let playback,
                  let uuid = UUID(uuidString: episodeID),
                  let episode = store.episode(id: uuid) else {
                logger.error("setNowPlaying: unknown episode \(episodeID, privacy: .public)")
                return
            }
            playback.setEpisode(episode)
            if let ts = timestampSeconds {
                playback.seek(to: ts)
            }
            logger.info("setNowPlaying: \(episode.title, privacy: .public)")
        }
    }

    func openScreen(route: String) async {
        // Routing surface lives in `RootView`'s local `@State`; until a
        // dedicated navigator exists the best we can do is log so the agent's
        // intent is visible in Console.app and so tests can assert the call
        // shape unchanged.
        logger.info("openScreen: route='\(route, privacy: .public)' (no-op until nav router lands)")
    }
}
