import Foundation

// MARK: - PodcastAgentToolDeps
//
// This file defines the dependency surface that the lane-10 podcast tools
// dispatch into. Every protocol here is intentionally **value-typed in / value-typed
// out** so the caller can supply mocks in tests and lane-1..9 implementations at
// merge time.
//
// Lane 10 owns the tool surface; other lanes own the protocol implementations.
// At wire-up time the orchestrator constructs a single `PodcastAgentToolDeps`
// (typically in `AppStateStore` or an `AgentChatSession` factory) and passes it
// to `AgentTools.dispatchPodcast(...)`.
//
// All protocols are declared `Sendable` because the dispatch is `async` and may
// hop actors. Implementations that touch `@MainActor` state should mark their
// methods `@MainActor`; the protocol surface tolerates either.

// MARK: - Value types

/// Identifier for an episode. Stringly-typed at the tool boundary so we don't
/// couple lane 10 to lane 2/3's `Episode` model. The orchestrator's adapter
/// translates between this string ID and whatever underlying type wins.
public typealias EpisodeID = String

/// Identifier for a podcast subscription. Same rationale as `EpisodeID`.
public typealias PodcastID = String

/// A search hit returned by `search_episodes` or `find_similar_episodes`.
public struct EpisodeHit: Sendable, Equatable {
    public let episodeID: EpisodeID
    public let podcastID: PodcastID
    public let title: String
    public let podcastTitle: String
    public let publishedAt: Date?
    public let durationSeconds: Int?
    public let snippet: String?
    public let score: Double?

    public init(
        episodeID: EpisodeID,
        podcastID: PodcastID,
        title: String,
        podcastTitle: String,
        publishedAt: Date? = nil,
        durationSeconds: Int? = nil,
        snippet: String? = nil,
        score: Double? = nil
    ) {
        self.episodeID = episodeID
        self.podcastID = podcastID
        self.title = title
        self.podcastTitle = podcastTitle
        self.publishedAt = publishedAt
        self.durationSeconds = durationSeconds
        self.snippet = snippet
        self.score = score
    }
}

/// A transcript chunk hit returned by `query_transcripts`.
public struct TranscriptHit: Sendable, Equatable {
    public let episodeID: EpisodeID
    public let startSeconds: Double
    public let endSeconds: Double
    public let speaker: String?
    public let text: String
    public let score: Double?

    public init(
        episodeID: EpisodeID,
        startSeconds: Double,
        endSeconds: Double,
        speaker: String? = nil,
        text: String,
        score: Double? = nil
    ) {
        self.episodeID = episodeID
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.speaker = speaker
        self.text = text
        self.score = score
    }
}

/// A wiki page hit returned by `query_wiki`.
public struct WikiHit: Sendable, Equatable {
    public let pageID: String
    public let title: String
    public let excerpt: String
    public let score: Double?

    public init(pageID: String, title: String, excerpt: String, score: Double? = nil) {
        self.pageID = pageID
        self.title = title
        self.excerpt = excerpt
        self.score = score
    }
}

/// A composed briefing artifact. The agent renders this back to the user as a
/// single hero card; lane 8 owns the actual TTS rendering.
public struct BriefingResult: Sendable, Equatable {
    public let briefingID: String
    public let title: String
    public let estimatedSeconds: Int
    public let episodeIDs: [EpisodeID]
    public let scriptPreview: String?

    public init(
        briefingID: String,
        title: String,
        estimatedSeconds: Int,
        episodeIDs: [EpisodeID],
        scriptPreview: String? = nil
    ) {
        self.briefingID = briefingID
        self.title = title
        self.estimatedSeconds = estimatedSeconds
        self.episodeIDs = episodeIDs
        self.scriptPreview = scriptPreview
    }
}

/// A summary returned by `summarize_episode`.
public struct EpisodeSummary: Sendable, Equatable {
    public let episodeID: EpisodeID
    public let summary: String
    public let bulletPoints: [String]

    public init(episodeID: EpisodeID, summary: String, bulletPoints: [String] = []) {
        self.episodeID = episodeID
        self.summary = summary
        self.bulletPoints = bulletPoints
    }
}

/// A Perplexity search result.
public struct PerplexityResult: Sendable, Equatable {
    public struct Source: Sendable, Equatable {
        public let title: String
        public let url: String
        public init(title: String, url: String) {
            self.title = title
            self.url = url
        }
    }
    public let answer: String
    public let sources: [Source]

    public init(answer: String, sources: [Source]) {
        self.answer = answer
        self.sources = sources
    }
}

// MARK: - Protocols

/// RAG search across transcripts and wiki content (lane 4/7).
public protocol PodcastAgentRAGSearchProtocol: Sendable {
    /// Semantic + keyword episode discovery. `scope` is an optional podcast ID
    /// to constrain the search. Limit defaults to 10.
    func searchEpisodes(query: String, scope: PodcastID?, limit: Int) async throws -> [EpisodeHit]

    /// Semantic transcript chunk lookup. `scope` may be an `EpisodeID` (single
    /// episode), a `PodcastID` (whole podcast), or `nil` (everything).
    func queryTranscripts(query: String, scope: String?, limit: Int) async throws -> [TranscriptHit]

    /// Find episodes semantically similar to a seed episode.
    func findSimilarEpisodes(seedEpisodeID: EpisodeID, k: Int) async throws -> [EpisodeHit]
}

/// Knowledge wiki storage and retrieval (lane 5).
public protocol WikiStorageProtocol: Sendable {
    /// Look up a wiki page by topic. `scope` is an optional podcast ID.
    func queryWiki(topic: String, scope: PodcastID?, limit: Int) async throws -> [WikiHit]
}

/// Briefing composer (lane 8).
public protocol BriefingComposerProtocol: Sendable {
    /// Compose a personalized briefing.
    /// - Parameters:
    ///   - scope: keyword like `"this_week"`, `"unlistened"`, or a podcast ID.
    ///   - lengthMinutes: target length in minutes.
    ///   - style: optional style hint (`"news"`, `"deep_dive"`, etc).
    func composeBriefing(scope: String, lengthMinutes: Int, style: String?) async throws -> BriefingResult
}

/// Summarization for an individual episode (lane 5/8).
public protocol EpisodeSummarizerProtocol: Sendable {
    func summarizeEpisode(episodeID: EpisodeID, length: String?) async throws -> EpisodeSummary
}

/// Episode metadata + existence check (lane 2/3).
public protocol EpisodeFetcherProtocol: Sendable {
    /// Returns `true` iff an episode with the given ID exists in the local
    /// subscription graph. Used by `play_episode_at` and `set_now_playing` to
    /// validate before touching the player.
    func episodeExists(episodeID: EpisodeID) async -> Bool

    /// Returns `(podcastTitle, episodeTitle, durationSeconds?)` for an episode,
    /// or nil if not found. Best-effort metadata for tool result envelopes.
    func episodeMetadata(episodeID: EpisodeID) async -> (podcastTitle: String, episodeTitle: String, durationSeconds: Int?)?
}

/// Player + UI host (lane 1/2/9). The agent uses this to mutate what the user
/// sees and hears.
public protocol PlaybackHostProtocol: Sendable {
    /// Open the player at a specific episode/timestamp. Implementation owns
    /// AVPlayer state and Now Playing center.
    func playEpisodeAt(episodeID: EpisodeID, timestampSeconds: Double) async

    /// Update the now-playing context without immediately starting playback —
    /// e.g. preload artwork, seed Now Playing center.
    func setNowPlaying(episodeID: EpisodeID, timestampSeconds: Double?) async

    /// Navigate the UI to a named route. Routes are app-defined strings, e.g.
    /// `"library"`, `"now_playing"`, `"briefings"`, `"wiki/zone-2"`.
    func openScreen(route: String) async
}

/// HTTP-bearing online lookup (lane 9).
public protocol PerplexityClientProtocol: Sendable {
    /// Run an online search. May throw on transport errors, missing API key,
    /// or rate limits.
    func search(query: String) async throws -> PerplexityResult
}

// MARK: - Aggregate

/// Bundle of every protocol the podcast tool surface needs. Construct once at
/// app startup; pass to `AgentTools.dispatchPodcast(...)` for every tool call.
public struct PodcastAgentToolDeps: Sendable {
    public let rag: PodcastAgentRAGSearchProtocol
    public let wiki: WikiStorageProtocol
    public let briefing: BriefingComposerProtocol
    public let summarizer: EpisodeSummarizerProtocol
    public let fetcher: EpisodeFetcherProtocol
    public let playback: PlaybackHostProtocol
    public let perplexity: PerplexityClientProtocol

    public init(
        rag: PodcastAgentRAGSearchProtocol,
        wiki: WikiStorageProtocol,
        briefing: BriefingComposerProtocol,
        summarizer: EpisodeSummarizerProtocol,
        fetcher: EpisodeFetcherProtocol,
        playback: PlaybackHostProtocol,
        perplexity: PerplexityClientProtocol
    ) {
        self.rag = rag
        self.wiki = wiki
        self.briefing = briefing
        self.summarizer = summarizer
        self.fetcher = fetcher
        self.playback = playback
        self.perplexity = perplexity
    }
}
