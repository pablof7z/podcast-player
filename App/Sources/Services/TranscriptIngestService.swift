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
        // Per-category opt-out: if the user has disabled transcription for
        // the category this show belongs to, skip ingestion entirely.
        // Defaults to allow when the show isn't yet categorised.
        guard appStore.effectiveTranscriptionEnabled(forSubscription: episode.subscriptionID) else {
            Self.logger.info(
                "ingest(\(episodeID, privacy: .public)): transcription disabled for category — skipping"
            )
            return
        }

        inFlight.insert(episodeID)
        defer { inFlight.remove(episodeID) }

        // Path A: publisher transcript URL.
        //
        // Two error stages here, kept distinct so the log reflects which
        // step actually failed. The fetch+parse stage tells us whether
        // the publisher URL was usable at all; the persist stage tells
        // us whether on-disk storage worked. With the persistAndIndex
        // refactor, embedding failures no longer throw — so a thrown
        // error from `persistAndIndex` is a real disk problem, not a
        // missing-key one, and falling through to Scribe wouldn't help.
        if let url = episode.publisherTranscriptURL {
            appStore.setEpisodeTranscriptState(episodeID, state: .fetchingPublisher)
            let fetched: Transcript?
            do {
                fetched = try await ingestor.ingest(
                    url: url,
                    mimeHint: episode.publisherTranscriptType?.rawValue,
                    episodeID: episodeID,
                    language: "en-US"
                )
            } catch {
                Self.logger.notice(
                    "publisher transcript fetch failed for \(episodeID, privacy: .public): \(String(describing: error), privacy: .public) — trying Scribe fallback"
                )
                // Reset state so the Scribe path can take over cleanly.
                appStore.setEpisodeTranscriptState(episodeID, state: .none)
                fetched = nil
            }
            if let transcript = fetched {
                do {
                    try await persistAndIndex(
                        transcript: transcript,
                        episode: episode,
                        source: .publisher,
                        appStore: appStore
                    )
                    return
                } catch {
                    Self.logger.error(
                        "publisher transcript persist failed for \(episodeID, privacy: .public): \(String(describing: error), privacy: .public) — disk error, not falling through to Scribe"
                    )
                    appStore.setEpisodeTranscriptState(
                        episodeID,
                        state: .failed(message: error.localizedDescription)
                    )
                    return
                }
            }
            // fetched == nil: fetch threw above; let the Scribe path below run.
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

    /// Triggered from `AppStateStore.upsertEpisodes` whenever a feed refresh
    /// surfaces brand-new episode IDs. Filters to episodes the user would
    /// benefit from ingesting and dispatches an async `ingest` per candidate.
    ///
    /// **Inclusion rule** (the unlock for cross-episode RAG):
    ///   - Episode is not already `.ready`.
    ///   - At least one path is available — either a `publisherTranscriptURL`
    ///     with `autoIngestPublisherTranscripts` on, OR a configured
    ///     ElevenLabs key with `autoFallbackToScribe` on.
    ///
    /// `ingest()` itself handles per-category opt-out, dedup, and the
    /// publisher → Scribe fallback inside one call — so this method only has
    /// to decide *whether to bother trying*. Without the relaxed filter,
    /// shows that don't ship `<podcast:transcript>` (most indie podcasts)
    /// get NOTHING auto-fetched even with Scribe configured, and the agent's
    /// RAG layer comes up dark for those subscriptions.
    func evaluateAutoIngest(newEpisodeIDs: [UUID]) {
        guard !newEpisodeIDs.isEmpty else { return }
        guard let appStore = rag.appStore else {
            Self.logger.warning("evaluateAutoIngest: no AppStateStore attached — skipping")
            return
        }
        let episodes = newEpisodeIDs.compactMap { appStore.episode(id: $0) }
        let candidates = Self.autoIngestCandidates(
            among: episodes,
            settings: appStore.state.settings,
            elevenLabsKey: elevenLabsKey()
        )
        guard !candidates.isEmpty else { return }
        Self.logger.info(
            "evaluateAutoIngest: queueing \(candidates.count, privacy: .public) ingests (publisher+Scribe paths)"
        )
        for episodeID in candidates {
            Task { @MainActor [weak self] in
                await self?.ingest(episodeID: episodeID)
            }
        }
    }

    /// Pure decision logic for `evaluateAutoIngest`. Exposed `internal` so
    /// `TranscriptAutoIngestTests` can pin the branching without driving the
    /// full ingest pipeline (which needs network + ElevenLabs + sqlite-vec).
    ///
    /// Inclusion rule:
    ///   - Episode is not already `.ready`.
    ///   - At least one path is available — either the publisher transcript
    ///     URL is present and `autoIngestPublisherTranscripts` is on, OR the
    ///     ElevenLabs key is configured and `autoFallbackToScribe` is on.
    static func autoIngestCandidates(
        among episodes: [Episode],
        settings: Settings,
        elevenLabsKey: String?
    ) -> [UUID] {
        let publisherOn = settings.autoIngestPublisherTranscripts
        let scribeOn = settings.autoFallbackToScribe && !(elevenLabsKey ?? "").isEmpty
        guard publisherOn || scribeOn else { return [] }
        return episodes.compactMap { episode -> UUID? in
            guard !Self.isReady(episode.transcriptState) else { return nil }
            if episode.publisherTranscriptURL != nil {
                return publisherOn ? episode.id : nil
            }
            return scribeOn ? episode.id : nil
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
        // STEP 1: Persist + flip to `.ready` BEFORE embedding.
        //
        // The user's primary value out of this pipeline is "I can read the
        // transcript." Embedding for RAG search is a nice-to-have that
        // requires a separate provider key (`OpenRouter` / `Ollama`).
        // Folding embedding into the same throw-path used to mean: a fresh
        // user with no embeddings key never sees a transcript at all,
        // because `VectorIndex.upsert` throws `.missingAPIKey` and the
        // caller catches it and either falls through to Scribe (which
        // would hit the same throw) or sets `.failed`. This was the
        // default first-run experience and matches the reported bug:
        // "no transcript works, not even ElevenLabs Scribe."
        //
        // Save first, mark ready, then attempt embedding. RAG just won't
        // find this episode's content until the user adds an embeddings
        // key and explicitly re-embeds; the transcript itself is readable
        // immediately.
        try store.save(transcript)
        appStore.setEpisodeTranscriptState(
            episode.id,
            state: .ready(source: source)
        )

        // STEP 2: Best-effort embed. Failures are logged but don't throw.
        let chunkable = ChunkableTranscript(
            transcript: transcript,
            podcastID: episode.subscriptionID
        )
        let chunks = chunkBuilder.build(from: chunkable)

        do {
            // Drop any prior chunks for this episode so re-ingestion
            // replaces rather than accumulates. Idempotent on chunk.id,
            // but old chunks from a different segment-boundary run would
            // otherwise linger.
            try await rag.index.deleteAll(forEpisodeID: episode.id)
            if !chunks.isEmpty {
                try await rag.index.upsert(chunks: chunks)
            }
            Self.logger.info(
                "ingested transcript for \(episode.id, privacy: .public) — \(chunks.count, privacy: .public) chunks indexed, source=\(String(describing: source), privacy: .public)"
            )
        } catch {
            Self.logger.notice(
                "transcript saved for \(episode.id, privacy: .public) but RAG indexing failed: \(String(describing: error), privacy: .public) — episode is readable; search won't find it until the user re-embeds with a configured key"
            )
        }

        // STEP 3: Fire-and-forget AI chapter compilation when the episode
        // lacks publisher chapters. The compiler is internally idempotent and
        // early-returns when chapters already exist, so re-runs of the ingest
        // pipeline are cheap. Decoupled from the embed step because chapter
        // compilation runs even when embeddings can't (no API key).
        let episodeID = episode.id
        Task { @MainActor [weak appStore] in
            guard let appStore else { return }
            await AIChapterCompiler.shared.compileIfNeeded(episodeID: episodeID, store: appStore)
        }
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
