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
//
// Value-type result envelopes (`EpisodeHit`, `BriefingResult`, etc.) live in
// `PodcastAgentToolValues.swift`.

// MARK: - Search & retrieval

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

    /// Compile and persist a new wiki page. Throws when the AI provider key is
    /// missing or when the RAG index has no evidence for the requested topic.
    /// `kind` is "topic", "person", or "show" (defaults to "topic" for unknown values).
    /// `scope` is an optional podcast UUID string; nil produces a global page.
    func createWikiPage(title: String, kind: String, scope: PodcastID?) async throws -> WikiCreateResult

    /// List existing wiki pages from the inventory. Fast — does not decode page bodies.
    /// `scope` is an optional podcast UUID string; nil returns all pages.
    func listWikiPages(scope: PodcastID?, limit: Int) async throws -> [WikiPageListing]

    /// Delete the wiki page at `slug` in the given scope.
    /// `scope` is an optional podcast UUID string; nil targets global pages.
    /// No-ops when the page does not exist.
    func deleteWikiPage(slug: String, scope: PodcastID?) async throws
}

// MARK: - Composer / summarizer / fetcher

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

    /// Scan a subscribed podcast's episodes and return the EpisodeID whose
    /// `enclosureURL` matches `audioURLString`. Returns `nil` when not found.
    /// Used by `download_and_transcribe` (external path) to locate an episode
    /// after an auto-subscribe.
    func episodeIDForAudioURL(_ audioURLString: String, podcastID: PodcastID) async -> EpisodeID?
}

// MARK: - Player / library / peer publishing

/// Player + UI host (lane 1/2/9). The agent uses this to mutate what the user
/// sees and hears.
public protocol PlaybackHostProtocol: Sendable {
    /// Open the player at a specific episode/timestamp. Implementation owns
    /// AVPlayer state and Now Playing center.
    func playEpisodeAt(episodeID: EpisodeID, timestampSeconds: Double) async

    /// Pause active playback and flush persisted position state.
    func pausePlayback() async

    /// Update the now-playing context without immediately starting playback —
    /// e.g. preload artwork, seed Now Playing center.
    func setNowPlaying(episodeID: EpisodeID, timestampSeconds: Double?) async

    /// Set playback rate. Implementations may clamp to their supported range.
    func setPlaybackRate(_ rate: Double) async -> Double

    /// Arm or clear the sleep timer. `mode` is `off`, `minutes`, or
    /// `end_of_episode`.
    func setSleepTimer(mode: String, minutes: Int?) async -> String

    /// Navigate the UI to a named route. Routes are app-defined strings, e.g.
    /// `"library"`, `"now_playing"`, `"briefings"`, `"wiki/zone-2"`.
    func openScreen(route: String) async

    /// Play a publicly-accessible episode by URL without requiring a prior
    /// follow. When `feedURLString` is supplied, the system fetches the
    /// source podcast's metadata (artwork, title, author) and parents the
    /// episode to a real `Podcast` row — the user remains unsubscribed.
    /// When `feedURLString` is nil, the episode parents to the built-in
    /// "Unknown" podcast row.
    func playExternalEpisode(
        audioURL: URL,
        title: String,
        feedURLString: String?,
        durationSeconds: TimeInterval?,
        timestampSeconds: Double
    ) async

    /// Enqueue one or more time-bounded episode segments and optionally start
    /// playing the first one immediately. Used by the `queue_episode_segments`
    /// agent tool. Returns a summary of what was queued.
    func queueEpisodeSegments(
        segments: [EpisodeSegment],
        playNow: Bool
    ) async -> QueueSegmentsResult
}

/// Library, transcript, feed, and local episode-state mutations.
public protocol PodcastLibraryProtocol: Sendable {
    func markEpisodePlayed(episodeID: EpisodeID) async throws -> EpisodeMutationResult
    func markEpisodeUnplayed(episodeID: EpisodeID) async throws -> EpisodeMutationResult
    func downloadEpisode(episodeID: EpisodeID) async throws -> EpisodeMutationResult
    func requestTranscription(episodeID: EpisodeID) async throws -> TranscriptRequestResult
    /// Start the download (for offline) and **await** the full transcription pipeline.
    /// Blocks until the transcript reaches `.ready` or `.failed` — use this when the
    /// agent must have the transcript available before proceeding (e.g. `query_transcripts`).
    func downloadAndTranscribe(episodeID: EpisodeID) async throws -> TranscriptRequestResult
    func refreshFeed(podcastID: PodcastID) async throws -> FeedRefreshResult
    /// Create a clip on behalf of the user. `transcriptText` is pre-filled when
    /// the agent already has it from a prior `query_transcripts` call; otherwise
    /// the implementation should attempt to extract it from the local transcript.
    func createClip(
        episodeID: EpisodeID,
        startSeconds: Double,
        endSeconds: Double,
        caption: String?,
        transcriptText: String?
    ) async throws -> ClipResult
}

/// Resolves the user's trusted-friends list for the `send_friend_message`
/// tool. Gates outbound notes so the agent cannot fire kind:1 events at
/// arbitrary pubkeys on the user's identity.
public protocol FriendDirectoryProtocol: Sendable {
    /// `true` iff `pubkeyHex` matches a friend stored in the user's local
    /// Friends list. Comparison is case-insensitive on the hex string.
    func isKnownFriend(pubkeyHex: String) async -> Bool
}

/// Publishes peer-conversation events on the user's Nostr identity. Used by
/// the `end_conversation` and `send_friend_message` agent tools. Implementations
/// are responsible for signing with the user's agent key, attaching NIP-10
/// reply tags when a peer context is present, and pushing the event to the
/// configured relay.
public protocol PeerEventPublisherProtocol: Sendable {
    /// Publish a kind:1 reply inside an existing peer conversation. Attaches
    /// NIP-10 `e`/`p` tags from `peerContext` plus any `extraTags`.
    func publishConversationReply(
        peerContext: PeerConversationContext,
        body: String,
        extraTags: [[String]]
    ) async throws -> String

    /// Publish a kind:1 note p-tagged at the friend, optionally threaded
    /// under an existing peer-conversation root.
    func publishFriendMessage(
        friendPubkeyHex: String,
        body: String,
        peerContext: PeerConversationContext?
    ) async throws -> String
}

// MARK: - Inventory queries

/// Plain-English library inventory queries. None of these go through RAG —
/// the agent uses them to answer "what am I subscribed to?" or "what was I
/// listening to?" without spending a search budget. Detail / discovery /
/// content lookups still go through the search and wiki protocols.
public protocol PodcastInventoryProtocol: Sendable {
    /// Every show the user is subscribed to, sorted by title. Caps at
    /// `limit` if the library is huge; the agent can ask for more in a
    /// follow-up call.
    func listSubscriptions(limit: Int) async -> [SubscriptionSummary]

    /// Episodes belonging to a specific subscription, newest publish-date
    /// first. Returns `nil` if the podcast isn't in the user's library.
    func listEpisodes(podcastID: PodcastID, limit: Int) async -> [EpisodeInventoryRow]?

    /// Episodes the user has started but not finished, newest publish-date
    /// first. Drives "what was I listening to?" answers without semantic
    /// search.
    func listInProgress(limit: Int) async -> [EpisodeInventoryRow]

    /// Recently published episodes the user has not played, newest first.
    /// Mirrors what the Today tab's New Episodes feed shows the user.
    func listRecentUnplayed(limit: Int) async -> [EpisodeInventoryRow]
}

/// LLM-derived category inventory and membership mutations.
public protocol PodcastCategoryProtocol: Sendable {
    /// Categories generated for the user's library. `includePodcasts` controls
    /// whether each category carries compact show rows or only counts.
    func listCategories(limit: Int, includePodcasts: Bool) async -> [PodcastCategorySummary]

    /// Move a subscribed podcast into an existing generated category.
    func changePodcastCategory(
        podcastID: PodcastID,
        category: PodcastCategoryReference
    ) async throws -> PodcastCategoryChangeResult
}

/// HTTP-bearing online lookup (lane 9).
public protocol PerplexityClientProtocol: Sendable {
    /// Run an online search. May throw on transport errors, missing API key,
    /// or rate limits.
    func search(query: String) async throws -> PerplexityResult
}

/// TTS episode generation and voice configuration (lane 10).
protocol TTSPublisherProtocol: Sendable {
    func defaultVoiceID() -> String
    func setDefaultVoiceID(_ voiceID: String)
    func generateAndPublish(
        title: String,
        description: String?,
        turns: [TTSTurn],
        playNow: Bool,
        generationSource: Episode.GenerationSource?
    ) async throws -> TTSEpisodeResult
}

/// Global podcast directory search (iTunes Search API).
public protocol PodcastDirectoryProtocol: Sendable {
    /// Search for shows or episodes in the Apple Podcasts directory.
    /// `type` selects podcast-level or episode-level results.
    func searchDirectory(
        query: String,
        type: PodcastDirectorySearchType,
        limit: Int
    ) async throws -> [PodcastDirectoryHit]

    /// Resolve an iTunes collection ID (the numeric string the directory
    /// returns alongside each podcast hit) to the canonical RSS feed URL.
    /// Returns `nil` when the lookup endpoint has no row for the ID.
    /// Throws on transport / parse failure.
    func lookupFeedURL(forCollectionID collectionID: String) async throws -> String?
}

/// Subscribing to a new podcast feed by URL.
public protocol PodcastSubscribeProtocol: Sendable {
    /// Fetch and persist a podcast feed. Idempotent — if the URL is already
    /// in the user's library the result carries `alreadySubscribed: true`.
    func subscribe(feedURLString: String) async throws -> PodcastSubscribeResult

    /// Capture a podcast's metadata + episodes into the store WITHOUT
    /// creating a `PodcastSubscription` (no follow flip). Wraps
    /// `SubscriptionService.ensurePodcast(feedURLString:)`. Used by the
    /// `list_episodes` external-input paths so the agent can offer episode
    /// lists for shows the user has not (yet) subscribed to.
    func ensurePodcast(feedURLString: String) async throws -> PodcastEnsureResult
}

// MARK: - Aggregate

/// Bundle of every protocol the podcast tool surface needs. Construct once at
/// app startup; pass to `AgentTools.dispatchPodcast(...)` for every tool call.
///
/// `peerContext` is the only per-call-mutable field — the orchestrator should
/// build a fresh `PodcastAgentToolDeps` (or use `withPeerContext(_:)`) for each
/// Nostr peer-conversation turn so peer-only tools (`end_conversation`,
/// `send_friend_message`) can resolve the active root + inbound event.
struct PodcastAgentToolDeps: Sendable {
    let rag: PodcastAgentRAGSearchProtocol
    let wiki: WikiStorageProtocol
    let briefing: BriefingComposerProtocol
    let summarizer: EpisodeSummarizerProtocol
    let fetcher: EpisodeFetcherProtocol
    let playback: PlaybackHostProtocol
    let library: PodcastLibraryProtocol
    let inventory: PodcastInventoryProtocol
    let categories: PodcastCategoryProtocol
    let peerPublisher: PeerEventPublisherProtocol
    let friendDirectory: FriendDirectoryProtocol
    let perplexity: PerplexityClientProtocol
    let ttsPublisher: TTSPublisherProtocol
    let directory: PodcastDirectoryProtocol
    let subscribe: PodcastSubscribeProtocol
    /// Set by the Nostr peer-agent entrypoint per inbound turn. Nil for owner
    /// chat / voice / other entrypoints — peer-only tools early-return a clean
    /// tool error in that case.
    let peerContext: PeerConversationContext?
    /// Set by `AgentChatSession` per dispatch to the active in-app conversation
    /// UUID. Used by `generate_tts_episode` to tag the resulting episode with
    /// its source conversation so the player can surface a tappable link.
    let chatConversationID: UUID?
    /// Hook for marking a peer-conversation root as ended (drives the
    /// "agent has signed off" UI affordance). Implemented by the live wiring;
    /// no-op in tests by default.
    let endConversationSink: PeerConversationEndSink

    init(
        rag: PodcastAgentRAGSearchProtocol,
        wiki: WikiStorageProtocol,
        briefing: BriefingComposerProtocol,
        summarizer: EpisodeSummarizerProtocol,
        fetcher: EpisodeFetcherProtocol,
        playback: PlaybackHostProtocol,
        library: PodcastLibraryProtocol,
        inventory: PodcastInventoryProtocol,
        categories: PodcastCategoryProtocol,
        peerPublisher: PeerEventPublisherProtocol,
        friendDirectory: FriendDirectoryProtocol,
        perplexity: PerplexityClientProtocol,
        ttsPublisher: TTSPublisherProtocol,
        directory: PodcastDirectoryProtocol,
        subscribe: PodcastSubscribeProtocol,
        peerContext: PeerConversationContext? = nil,
        chatConversationID: UUID? = nil,
        endConversationSink: PeerConversationEndSink = NoopPeerConversationEndSink()
    ) {
        self.rag = rag
        self.wiki = wiki
        self.briefing = briefing
        self.summarizer = summarizer
        self.fetcher = fetcher
        self.playback = playback
        self.library = library
        self.inventory = inventory
        self.categories = categories
        self.peerPublisher = peerPublisher
        self.friendDirectory = friendDirectory
        self.perplexity = perplexity
        self.ttsPublisher = ttsPublisher
        self.directory = directory
        self.subscribe = subscribe
        self.peerContext = peerContext
        self.chatConversationID = chatConversationID
        self.endConversationSink = endConversationSink
    }

    /// Returns a copy with the supplied peer context. Used by the Nostr
    /// inbound entrypoint to thread per-turn context without rebuilding adapters.
    func withPeerContext(_ ctx: PeerConversationContext?) -> PodcastAgentToolDeps {
        PodcastAgentToolDeps(
            rag: rag,
            wiki: wiki,
            briefing: briefing,
            summarizer: summarizer,
            fetcher: fetcher,
            playback: playback,
            library: library,
            inventory: inventory,
            categories: categories,
            peerPublisher: peerPublisher,
            friendDirectory: friendDirectory,
            perplexity: perplexity,
            ttsPublisher: ttsPublisher,
            directory: directory,
            subscribe: subscribe,
            peerContext: ctx,
            chatConversationID: chatConversationID,
            endConversationSink: endConversationSink
        )
    }

    /// Returns a copy with the supplied in-app chat conversation ID. Called
    /// by `AgentChatSession` per dispatch so `generate_tts_episode` can tag
    /// the resulting episode with its source conversation.
    func withChatConversationID(_ id: UUID?) -> PodcastAgentToolDeps {
        PodcastAgentToolDeps(
            rag: rag,
            wiki: wiki,
            briefing: briefing,
            summarizer: summarizer,
            fetcher: fetcher,
            playback: playback,
            library: library,
            inventory: inventory,
            categories: categories,
            peerPublisher: peerPublisher,
            friendDirectory: friendDirectory,
            perplexity: perplexity,
            ttsPublisher: ttsPublisher,
            directory: directory,
            subscribe: subscribe,
            peerContext: peerContext,
            chatConversationID: id,
            endConversationSink: endConversationSink
        )
    }
}

/// Records that a peer-conversation root has been ended by the agent.
/// Lives on `PodcastAgentToolDeps` so the test surface can supply a no-op.
public protocol PeerConversationEndSink: Sendable {
    func markEnded(rootEventID: String) async
}

public struct NoopPeerConversationEndSink: PeerConversationEndSink {
    init() {}
    public func markEnded(rootEventID: String) async {}
}
