import Foundation
import os.log

// MARK: - TranscriptIngestService
//
// Owns the end-to-end transcript ingestion pipeline:
//   1. Pick a publisher transcript URL (or fall back to ElevenLabs Scribe).
//   2. Fetch + parse via `PublisherTranscriptIngestor`.
//   3. Slice into `Chunk`s via `ChunkBuilder`, supplying podcast/episode FKs.
//   4. Embed + upsert via `RAGService.shared.index` (which calls the embedder).
//   5. Persist the parsed `Transcript` JSON to disk for the EpisodeDetail view.
//   6. Update `Episode.transcriptState` on the live `AppStateStore`.
//
// The service stays `@MainActor` because every input + output it touches
// (state store, episode model, status flips) lives on the main actor; the
// expensive bits (network, SQLite, embedding) all hop off via `await`.

@MainActor
final class TranscriptIngestService {

    // MARK: Singleton

    static let shared = TranscriptIngestService()

    // MARK: Logger

    nonisolated private static let logger = Logger.app("TranscriptIngestService")

    // MARK: Dependencies

    private let rag: RAGService
    private let ingestor: PublisherTranscriptIngestor
    private let scribe: ElevenLabsScribeClient
    private let chunkBuilder: ChunkBuilder
    private let store: TranscriptStore
    private let elevenLabsKey: @Sendable () -> String?

    // MARK: In-flight tracking (dedup)

    private var inFlight: Set<UUID> = []

    // MARK: Init

    init(
        rag: RAGService = .shared,
        ingestor: PublisherTranscriptIngestor = PublisherTranscriptIngestor(),
        scribe: ElevenLabsScribeClient = ElevenLabsScribeClient(),
        chunkBuilder: ChunkBuilder = ChunkBuilder(),
        store: TranscriptStore = .shared,
        elevenLabsKey: @escaping @Sendable () -> String? = {
            (try? ElevenLabsCredentialStore.apiKey()).flatMap { $0.isEmpty ? nil : $0 }
        }
    ) {
        self.rag = rag
        self.ingestor = ingestor
        self.scribe = scribe
        self.chunkBuilder = chunkBuilder
        self.store = store
        self.elevenLabsKey = elevenLabsKey
    }

    // MARK: Public API

    /// Ingest the transcript for one episode. Resolves the publisher URL +
    /// type from `AppStateStore`, fetches, parses, chunks, embeds, upserts,
    /// then persists the parsed transcript to disk and updates state.
    /// Idempotent — repeat calls for the same episode no-op while a prior
    /// call is in flight.
    func ingest(episodeID: UUID) async {
        guard let appStore = rag.appStore else {
            Self.logger.warning(
                "ingest(\(episodeID, privacy: .public)): no AppStateStore attached — skipping"
            )
            return
        }
        guard !inFlight.contains(episodeID) else {
            Self.logger.debug(
                "ingest(\(episodeID, privacy: .public)): already in flight — skipping"
            )
            return
        }
        guard let episode = appStore.episode(id: episodeID) else {
            Self.logger.warning(
                "ingest(\(episodeID, privacy: .public)): episode not found in store"
            )
            return
        }

        inFlight.insert(episodeID)
        defer { inFlight.remove(episodeID) }

        // Path A: publisher transcript URL.
        if let url = episode.publisherTranscriptURL {
            appStore.setEpisodeTranscriptState(episodeID, state: .fetchingPublisher)
            do {
                let transcript = try await ingestor.ingest(
                    url: url,
                    mimeHint: episode.publisherTranscriptType?.rawValue,
                    episodeID: episodeID,
                    language: "en-US"
                )
                try await persistAndIndex(
                    transcript: transcript,
                    episode: episode,
                    source: .publisher,
                    appStore: appStore
                )
                return
            } catch {
                Self.logger.notice(
                    "publisher transcript fetch failed for \(episodeID, privacy: .public): \(String(describing: error), privacy: .public) — trying Scribe fallback"
                )
                // Fall through to Scribe path.
            }
        }

        // Path B: ElevenLabs Scribe (only if a key is configured *and* the
        // user has opted in to the Scribe fallback under Settings → Transcripts).
        guard appStore.state.settings.autoFallbackToScribe else {
            Self.logger.info(
                "publisher transcript missing for \(episodeID, privacy: .public) and Scribe fallback disabled in settings — leaving transcriptState=.none"
            )
            appStore.setEpisodeTranscriptState(episodeID, state: .none)
            return
        }
        guard let key = elevenLabsKey(), !key.isEmpty else {
            Self.logger.info(
                "no publisher transcript and no ElevenLabs key for \(episodeID, privacy: .public) — leaving transcriptState=.none"
            )
            appStore.setEpisodeTranscriptState(episodeID, state: .none)
            return
        }
        await runScribe(for: episode, appStore: appStore)
    }

    /// Convenience: walk the store and ingest up to `maxCount` episodes that
    /// are not yet `.ready` and have a publisher transcript URL. Useful as a
    /// background warmup once the user lands on the library.
    func ingestPending(maxCount: Int = 5) async {
        guard let appStore = rag.appStore else {
            Self.logger.warning("ingestPending: no AppStateStore attached — skipping")
            return
        }
        let candidates = appStore.state.episodes
            .filter { $0.publisherTranscriptURL != nil && !Self.isReady($0.transcriptState) }
            .sorted { $0.pubDate > $1.pubDate }
            .prefix(maxCount)
        for episode in candidates {
            await ingest(episodeID: episode.id)
        }
    }

    // MARK: - Private pipeline

    private func runScribe(for episode: Episode, appStore: AppStateStore) async {
        appStore.setEpisodeTranscriptState(episode.id, state: .transcribing(progress: 0))
        do {
            let job = try await scribe.submit(
                audioURL: episode.enclosureURL,
                episodeID: episode.id,
                languageHint: nil
            )
            let transcript = try await scribe.pollResult(job)
            try await persistAndIndex(
                transcript: transcript,
                episode: episode,
                source: .scribe,
                appStore: appStore
            )
        } catch {
            let message = String(describing: error)
            Self.logger.error(
                "Scribe ingest failed for \(episode.id, privacy: .public): \(message, privacy: .public)"
            )
            appStore.setEpisodeTranscriptState(
                episode.id,
                state: .failed(message: error.localizedDescription)
            )
        }
    }

    private func persistAndIndex(
        transcript: Transcript,
        episode: Episode,
        source: TranscriptState.Source,
        appStore: AppStateStore
    ) async throws {
        // 1. Build chunks with the episode's podcast (subscription) FK.
        let chunkable = ChunkableTranscript(
            transcript: transcript,
            podcastID: episode.subscriptionID
        )
        let chunks = chunkBuilder.build(from: chunkable)

        // 2. Drop any prior chunks for this episode so re-ingestion replaces
        //    rather than accumulates. The vector store's upsert path is
        //    already idempotent on `chunk.id`, but old chunks (e.g. from a
        //    Scribe re-run with different segment boundaries) would otherwise
        //    linger.
        try await rag.index.deleteAll(forEpisodeID: episode.id)

        // 3. Embed + upsert. `VectorIndex.upsert` calls the embeddings client
        //    internally; if no API key is configured this throws and we
        //    surface the failure on `transcriptState`.
        if !chunks.isEmpty {
            try await rag.index.upsert(chunks: chunks)
        }

        // 4. Persist the parsed transcript so the EpisodeDetail view can
        //    render it without re-fetching.
        try store.save(transcript)

        // 5. Flip state to .ready.
        appStore.setEpisodeTranscriptState(
            episode.id,
            state: .ready(source: source)
        )

        // 6. Fire-and-forget AI chapter compilation when the episode lacks
        //    publisher chapters. The compiler is internally idempotent and
        //    early-returns when chapters already exist, so re-runs of the
        //    ingest pipeline are cheap.
        let episodeID = episode.id
        Task { @MainActor [weak appStore] in
            guard let appStore else { return }
            await AIChapterCompiler.shared.compileIfNeeded(episodeID: episodeID, store: appStore)
        }

        Self.logger.info(
            "ingested transcript for \(episode.id, privacy: .public) — \(chunks.count, privacy: .public) chunks, source=\(String(describing: source), privacy: .public)"
        )
    }

    // MARK: - Helpers

    private static func isReady(_ state: TranscriptState) -> Bool {
        if case .ready = state { return true }
        return false
    }
}

// MARK: - ChunkableTranscript
//
// Adapter that lets `Transcript` (which has no `podcastID` and stores
// timestamps in seconds) satisfy the `TranscriptLike` / `TranscriptSegment`
// protocol pair `ChunkBuilder` requires.

struct ChunkableTranscript: TranscriptLike {

    typealias Segment = ChunkableSegment

    let transcript: Transcript
    let podcastID: UUID

    var episodeID: UUID { transcript.episodeID }
    var segments: [ChunkableSegment] {
        transcript.segments.map { ChunkableSegment(segment: $0) }
    }
}

struct ChunkableSegment: TranscriptSegment {
    let segment: Segment

    var text: String { segment.text }
    var startMS: Int { Int((segment.start * 1000).rounded()) }
    var endMS: Int { Int((segment.end * 1000).rounded()) }
    var speakerID: UUID? { segment.speakerID }
}
