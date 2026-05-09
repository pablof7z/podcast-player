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
/// by topic across titles, summaries, and claim bodies without dragging the
/// caller through the inventory + JSON-decode dance.
struct LiveWikiStorageAdapter: WikiStorageProtocol {

    let storage: WikiStorage

    init(storage: WikiStorage = .shared) {
        self.storage = storage
    }

    func queryWiki(topic: String, scope: PodcastID?, limit: Int) async throws -> [WikiHit] {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        let scopeFilter: WikiScope? = scope.flatMap { UUID(uuidString: $0) }.map { .podcast($0) }
        let storage = storage
        let queryTokens = Self.tokenize(trimmed)
        let boundedLimit = max(1, limit)
        return try await Task.detached(priority: .utility) {
            let pages = try storage.allPages()
            let scored = pages.compactMap { page -> (page: WikiPage, score: Double, excerpt: String)? in
                if let scopeFilter, page.scope != scopeFilter { return nil }
                let score = Self.score(page: page, query: trimmed, tokens: queryTokens)
                guard score > 0 else { return nil }
                return (page, score, Self.excerpt(from: page, query: trimmed, tokens: queryTokens))
            }
            let filtered = scored
                .sorted {
                    if $0.score != $1.score { return $0.score > $1.score }
                    return $0.page.generatedAt > $1.page.generatedAt
                }
                .prefix(boundedLimit)
            return filtered.map { hit in
                WikiHit(
                    pageID: hit.page.id.uuidString,
                    title: hit.page.title,
                    excerpt: String(hit.excerpt.prefix(280)),
                    score: hit.score
                )
            }
        }.value
    }

    private static func score(page: WikiPage, query: String, tokens: Set<String>) -> Double {
        let title = page.title.lowercased()
        let summary = page.summary.lowercased()
        let claims = page.allClaims.map { $0.text.lowercased() }
        var score = 0.0
        if title == query { score += 12 }
        if title.contains(query) { score += 8 }
        if summary.contains(query) { score += 5 }
        score += Double(claims.filter { $0.contains(query) }.count) * 4

        let corpusTokens = tokenize(([page.title, page.summary] + page.allClaims.map(\.text)).joined(separator: " "))
        let overlap = tokens.intersection(corpusTokens).count
        score += Double(overlap)
        return score
    }

    private static func excerpt(from page: WikiPage, query: String, tokens: Set<String>) -> String {
        let candidates = [page.summary] + page.allClaims.map(\.text)
        if let exact = candidates.first(where: { $0.lowercased().contains(query) }) {
            return exact
        }
        let best = candidates.max { lhs, rhs in
            tokenScore(lhs, tokens: tokens) < tokenScore(rhs, tokens: tokens)
        }
        if let best, !best.isBlank {
            return best
        }
        return page.summary
    }

    private static func tokenScore(_ text: String, tokens: Set<String>) -> Int {
        tokens.intersection(tokenize(text)).count
    }

    private static func tokenize(_ text: String) -> Set<String> {
        Set(text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 })
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
