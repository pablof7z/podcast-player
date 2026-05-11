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
//   • `TTSPublisherProtocol`           → `AgentTTSComposer`
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
        let inventory = LivePodcastInventoryAdapter(store: store)
        return PodcastAgentToolDeps(
            rag: LivePodcastRAGAdapter(store: store),
            wiki: LiveWikiStorageAdapter(),
            briefing: LiveBriefingComposerAdapter(store: store),
            summarizer: LiveEpisodeSummarizerAdapter(store: store),
            fetcher: LiveEpisodeFetcherAdapter(store: store),
            playback: LivePlaybackHostAdapter(store: store, playback: playback),
            library: LivePodcastLibraryAdapter(
                store: store,
                downloadService: .shared,
                transcriptService: .shared,
                refreshService: .shared
            ),
            inventory: inventory,
            categories: inventory,
            delegation: LiveTENEXDelegationBridge(store: store),
            perplexity: PerplexityClient(),
            ttsPublisher: AgentTTSComposer(store: store, playback: playback),
            directory: LivePodcastDirectoryAdapter(),
            subscribe: LivePodcastSubscribeAdapter(store: store)
        )
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

    func episodeIDForAudioURL(_ audioURLString: String, podcastID: PodcastID) async -> EpisodeID? {
        guard let store, let podcastUUID = UUID(uuidString: podcastID) else { return nil }
        let episodes = await store.episodes(forSubscription: podcastUUID)
        return episodes.first { $0.enclosureURL.absoluteString == audioURLString }?.id.uuidString
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

    func pausePlayback() async {
        await MainActor.run {
            guard let playback else {
                logger.error("pausePlayback: playback host missing")
                return
            }
            playback.pause()
            logger.info("pausePlayback: paused")
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

    func setPlaybackRate(_ rate: Double) async -> Double {
        await MainActor.run {
            guard let playback else {
                logger.error("setPlaybackRate: playback host missing")
                return 1.0
            }
            let clamped = min(max(rate, 0.5), 3.0)
            playback.engine.setRate(clamped)
            logger.info("setPlaybackRate: \(clamped)")
            return clamped
        }
    }

    func setSleepTimer(mode: String, minutes: Int?) async -> String {
        await MainActor.run {
            guard let playback else {
                logger.error("setSleepTimer: playback host missing")
                return "Unavailable"
            }
            let timer: PlaybackSleepTimer
            switch mode {
            case "off":
                timer = .off
            case "end_of_episode":
                timer = .endOfEpisode
            case "minutes":
                timer = .minutes(max(1, minutes ?? 30))
            default:
                timer = .off
            }
            playback.setSleepTimer(timer)
            logger.info("setSleepTimer: \(timer.label, privacy: .public)")
            return timer.label
        }
    }

    func openScreen(route: String) async {
        // Routing surface lives in `RootView`'s local `@State`; until a
        // dedicated navigator exists the best we can do is log so the agent's
        // intent is visible in Console.app and so tests can assert the call
        // shape unchanged.
        logger.info("openScreen: route='\(route, privacy: .public)' (no-op until nav router lands)")
    }

    func playExternalEpisode(
        audioURL: URL,
        title: String,
        podcastTitle: String?,
        imageURL: URL?,
        durationSeconds: TimeInterval?,
        timestampSeconds: Double
    ) async {
        await MainActor.run {
            guard let playback else {
                logger.error("playExternalEpisode: playback host missing")
                return
            }
            // Sentinel UUID marks this episode as external (not in any subscription).
            let sentinelSubscriptionID = UUID(uuidString: "00000000-EEEE-EEEE-EEEE-000000000000")!
            let episode = Episode(
                id: UUID(),
                subscriptionID: sentinelSubscriptionID,
                guid: audioURL.absoluteString,
                title: title,
                pubDate: Date(),
                duration: durationSeconds,
                enclosureURL: audioURL,
                imageURL: imageURL
            )
            playback.setEpisode(episode)
            if timestampSeconds > 0 { playback.seek(to: timestampSeconds) }
            playback.play()
            logger.info("playExternalEpisode: '\(title, privacy: .public)' at \(timestampSeconds)")
        }
    }

    func queueEpisodeSegments(
        segments: [EpisodeSegment],
        playNow: Bool
    ) async -> QueueSegmentsResult {
        await MainActor.run {
            guard let store, let playback else {
                logger.error("queueEpisodeSegments: playback host missing")
                return QueueSegmentsResult(segmentsQueued: 0, playingNow: false)
            }
            let items: [QueueItem] = segments.compactMap { seg in
                guard let uuid = UUID(uuidString: seg.episodeID) else { return nil }
                return QueueItem(
                    episodeID: uuid,
                    startSeconds: seg.startSeconds,
                    endSeconds: seg.endSeconds,
                    label: seg.label
                )
            }
            guard !items.isEmpty else {
                return QueueSegmentsResult(segmentsQueued: 0, playingNow: false)
            }
            let firstEpisodeTitle: String? = {
                guard let firstUUID = UUID(uuidString: segments[0].episodeID) else { return nil }
                return store.episode(id: firstUUID)?.title
            }()
            playback.enqueueSegments(items, playNow: playNow) { store.episode(id: $0) }
            logger.info("queueEpisodeSegments: queued \(items.count, privacy: .public) segments, playNow=\(playNow, privacy: .public)")
            return QueueSegmentsResult(
                segmentsQueued: items.count,
                playingNow: playNow,
                firstEpisodeTitle: firstEpisodeTitle
            )
        }
    }
}

// MARK: - Library adapter

final class LivePodcastLibraryAdapter: PodcastLibraryProtocol, @unchecked Sendable {

    weak var store: AppStateStore?
    private let downloadService: EpisodeDownloadService
    private let transcriptService: TranscriptIngestService
    private let refreshService: SubscriptionRefreshService

    init(
        store: AppStateStore,
        downloadService: EpisodeDownloadService,
        transcriptService: TranscriptIngestService,
        refreshService: SubscriptionRefreshService
    ) {
        self.store = store
        self.downloadService = downloadService
        self.transcriptService = transcriptService
        self.refreshService = refreshService
    }

    func markEpisodePlayed(episodeID: EpisodeID) async throws -> EpisodeMutationResult {
        try await mutateEpisode(episodeID: episodeID, state: "played") { store, id in
            store.markEpisodePlayed(id)
        }
    }

    func markEpisodeUnplayed(episodeID: EpisodeID) async throws -> EpisodeMutationResult {
        try await mutateEpisode(episodeID: episodeID, state: "unplayed") { store, id in
            store.markEpisodeUnplayed(id)
        }
    }

    func downloadEpisode(episodeID: EpisodeID) async throws -> EpisodeMutationResult {
        try await mutateEpisode(episodeID: episodeID, state: nil) { store, id in
            self.downloadService.attach(appStore: store)
            self.downloadService.download(episodeID: id)
        }
    }

    func requestTranscription(episodeID: EpisodeID) async throws -> TranscriptRequestResult {
        guard let uuid = UUID(uuidString: episodeID) else {
            throw PodcastAgentToolAdapterError.invalidID(episodeID)
        }
        guard let store else {
            throw PodcastAgentToolAdapterError.unavailable("AppStateStore")
        }
        guard let episode = await store.episode(id: uuid) else {
            throw PodcastAgentToolAdapterError.missingEpisode(episodeID)
        }
        if case .ready(let source) = episode.transcriptState {
            return TranscriptRequestResult(
                episodeID: episodeID,
                status: "ready",
                source: source.rawValue
            )
        }
        await MainActor.run {
            store.setEpisodeTranscriptState(uuid, state: .queued)
            Task { @MainActor in
                await self.transcriptService.ingest(episodeID: uuid)
            }
        }
        return TranscriptRequestResult(
            episodeID: episodeID,
            status: "queued",
            message: "Transcript ingestion started."
        )
    }

    func downloadAndTranscribe(episodeID: EpisodeID) async throws -> TranscriptRequestResult {
        guard let uuid = UUID(uuidString: episodeID) else {
            throw PodcastAgentToolAdapterError.invalidID(episodeID)
        }
        guard let store else {
            throw PodcastAgentToolAdapterError.unavailable("AppStateStore")
        }
        guard let episode = await store.episode(id: uuid) else {
            throw PodcastAgentToolAdapterError.missingEpisode(episodeID)
        }
        // Already transcribed — skip the pipeline.
        if case .ready(let source) = episode.transcriptState {
            return TranscriptRequestResult(
                episodeID: episodeID,
                status: "ready",
                source: source.rawValue,
                message: "Transcript already available."
            )
        }
        // Kick off download for offline playback (fire-and-forget).
        // Transcription below will use the remote enclosure URL while
        // the download proceeds in the background; Apple-native STT
        // will pick up the local file on the post-download ingest trigger.
        await MainActor.run {
            downloadService.attach(appStore: store)
            downloadService.download(episodeID: uuid)
        }
        // Await the full transcription pipeline. This call blocks until the
        // transcript is persisted (.ready) or the pipeline gives up (.failed).
        await transcriptService.ingest(episodeID: uuid)
        // Read the final state.
        let final = await store.episode(id: uuid) ?? episode
        switch final.transcriptState {
        case .ready(let src):
            return TranscriptRequestResult(
                episodeID: episodeID,
                status: "ready",
                source: src.rawValue
            )
        case .failed(let msg):
            return TranscriptRequestResult(
                episodeID: episodeID,
                status: "failed",
                message: msg
            )
        default:
            return TranscriptRequestResult(
                episodeID: episodeID,
                status: "unavailable",
                message: "Transcription could not complete. Check STT provider settings."
            )
        }
    }

    func createClip(
        episodeID: EpisodeID,
        startSeconds: Double,
        endSeconds: Double,
        caption: String?,
        transcriptText: String?
    ) async throws -> ClipResult {
        guard let uuid = UUID(uuidString: episodeID) else {
            throw PodcastAgentToolAdapterError.invalidID(episodeID)
        }
        guard let store else {
            throw PodcastAgentToolAdapterError.unavailable("AppStateStore")
        }
        guard let episode = await store.episode(id: uuid) else {
            throw PodcastAgentToolAdapterError.missingEpisode(episodeID)
        }
        let startMs = Int(startSeconds * 1000)
        let endMs = Int(endSeconds * 1000)
        let resolvedText: String
        if let supplied = transcriptText, !supplied.isEmpty {
            resolvedText = supplied
        } else {
            resolvedText = Self.extractTranscriptText(
                episodeID: uuid,
                startSeconds: startSeconds,
                endSeconds: endSeconds
            )
        }
        let clip = await MainActor.run {
            store.addClip(
                episodeID: uuid,
                subscriptionID: episode.subscriptionID,
                startMs: startMs,
                endMs: endMs,
                transcriptText: resolvedText,
                source: .agent,
                caption: caption
            )
        }
        return ClipResult(
            clipID: clip.id.uuidString,
            episodeID: episodeID,
            podcastID: episode.subscriptionID.uuidString,
            episodeTitle: episode.title,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            transcriptText: resolvedText,
            caption: caption
        )
    }

    private static func extractTranscriptText(
        episodeID: UUID,
        startSeconds: Double,
        endSeconds: Double
    ) -> String {
        guard let transcript = TranscriptStore.shared.load(episodeID: episodeID) else { return "" }
        let matching = transcript.segments.filter { $0.end > startSeconds && $0.start < endSeconds }
        return matching.map(\.text).joined(separator: " ")
    }

    func refreshFeed(podcastID: PodcastID) async throws -> FeedRefreshResult {
        guard let uuid = UUID(uuidString: podcastID) else {
            throw PodcastAgentToolAdapterError.invalidID(podcastID)
        }
        guard let store else {
            throw PodcastAgentToolAdapterError.unavailable("AppStateStore")
        }
        guard let before = await store.subscription(id: uuid) else {
            throw PodcastAgentToolAdapterError.missingPodcast(podcastID)
        }
        let priorCount = await store.episodes(forSubscription: uuid).count
        try await refreshService.refresh(uuid, store: store)
        let after = await store.subscription(id: uuid) ?? before
        let episodeCount = await store.episodes(forSubscription: uuid).count
        return FeedRefreshResult(
            podcastID: podcastID,
            title: after.title,
            episodeCount: episodeCount,
            newEpisodeCount: max(0, episodeCount - priorCount),
            refreshedAt: after.lastRefreshedAt
        )
    }

    private func mutateEpisode(
        episodeID: EpisodeID,
        state explicitState: String?,
        _ mutation: @escaping @MainActor (AppStateStore, UUID) -> Void
    ) async throws -> EpisodeMutationResult {
        guard let uuid = UUID(uuidString: episodeID) else {
            throw PodcastAgentToolAdapterError.invalidID(episodeID)
        }
        guard let store else {
            throw PodcastAgentToolAdapterError.unavailable("AppStateStore")
        }
        guard let before = await store.episode(id: uuid) else {
            throw PodcastAgentToolAdapterError.missingEpisode(episodeID)
        }
        await MainActor.run {
            mutation(store, uuid)
        }
        let after = await store.episode(id: uuid) ?? before
        let subscription = await store.subscription(id: after.subscriptionID)
        return EpisodeMutationResult(
            episodeID: episodeID,
            podcastID: after.subscriptionID.uuidString,
            episodeTitle: after.title,
            podcastTitle: subscription?.title,
            state: explicitState ?? Self.downloadStateLabel(after.downloadState)
        )
    }

    private static func downloadStateLabel(_ state: DownloadState) -> String {
        switch state {
        case .notDownloaded: return "not_downloaded"
        case .queued: return "queued"
        case .downloading: return "downloading"
        case .downloaded: return "downloaded"
        case .failed: return "failed"
        }
    }
}

enum PodcastAgentToolAdapterError: LocalizedError {
    case unavailable(String)
    case invalidID(String)
    case missingEpisode(String)
    case missingPodcast(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let name): return "\(name) is unavailable."
        case .invalidID(let value): return "Invalid UUID: \(value)"
        case .missingEpisode(let id): return "Episode not found: \(id)"
        case .missingPodcast(let id): return "Podcast not found: \(id)"
        }
    }
}
