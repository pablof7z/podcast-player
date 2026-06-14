import Foundation
import os.log

// MARK: - EpisodeMetadataIndexer
//
// Thin executor for the kernel-driven metadata-index backfill (D7).
//
// The kernel owns ALL policy:
//   - Which episodes are candidates (`PodcastUpdate.pendingMetadataIndexIds`)
//   - Batch size (kernel constant, surfaced via the push frame)
//   - Inter-batch pacing (`PodcastUpdate.metadataIndexInterBatchDelayMs`)
//   - Halt-on-failure: a zero-success batch causes the executor to stop
//
// The shell's only responsibilities:
//   1. Drain the kernel-provided batch of episode IDs
//   2. Build and upsert the embedding chunks
//   3. Dispatch `MarkEpisodesMetadataIndexed` on success
//
// Lifecycle:
//   `indexKernelBatch(ids:interBatchDelayMs:appStore:)` — called from the
//   kernel-projection observer whenever `pendingMetadataIndexIds` is
//   non-empty. Reentrancy-safe via the `inFlight` dedup set; concurrent
//   batches on the same ID are harmlessly coalesced.
//
// Coexistence with transcripts: `TranscriptIngestService.persistAndIndex`
// calls `rag.index.deleteAll(forEpisodeID:)` before upserting transcript
// chunks, so transcript ingestion automatically replaces a synthetic
// metadata chunk. The reverse race (metadata indexer running after a
// transcript already landed) is gated by the `metadataIndexed` flag,
// which transcript ingestion also flips on success.

@MainActor
final class EpisodeMetadataIndexer {

    // MARK: Singleton

    static let shared = EpisodeMetadataIndexer()

    // MARK: Logger

    nonisolated private static let logger = Logger.app("EpisodeMetadataIndexer")

    // MARK: Dependencies

    private let store: VectorStore

    // MARK: In-flight tracking (dedup)

    /// Set of episode IDs currently being indexed. Prevents a batch from the
    /// push frame racing with a concurrent incremental call on the same episode
    /// (e.g. a feed refresh fires while the previous batch is still in flight).
    private var inFlight: Set<UUID> = []

    // MARK: Init

    init(store: VectorStore = RAGService.shared.index) {
        self.store = store
    }

    // MARK: Public API

    /// Execute a single kernel-provided batch of episode IDs.
    ///
    /// Called from the projection observer whenever `PodcastUpdate.pendingMetadataIndexIds`
    /// is non-empty. Returns the count of episodes successfully indexed; `0` on
    /// embed failure. The observer must stop calling this on a zero result (halt-on-failure
    /// parity with the old `runBackfill` loop).
    ///
    /// The inter-batch delay is the caller's responsibility: sleep
    /// `interBatchDelayMs` milliseconds AFTER a successful (non-zero) return
    /// before processing the next frame's batch. This matches the old
    /// `interBatchDelayNanoseconds` throttle, now kernel-owned.
    @discardableResult
    func indexKernelBatch(
        ids: [UUID],
        appStore: AppStateStore
    ) async -> Int {
        return await indexEpisodes(ids: ids, appStore: appStore)
    }

    // MARK: Core

    /// Returns the number of episodes successfully indexed (and thus
    /// flagged `metadataIndexed = true`). Zero means the embed call
    /// failed; the caller should halt the backfill loop.
    @discardableResult
    private func indexEpisodes(ids: [UUID], appStore: AppStateStore) async -> Int {
        guard !ids.isEmpty else { return 0 }
        let claimable = ids.filter { !inFlight.contains($0) }
        guard !claimable.isEmpty else { return 0 }
        inFlight.formUnion(claimable)
        defer { inFlight.subtract(claimable) }

        // Resolve episodes + build chunks. Skip episodes that vanished
        // (deleted concurrently), episodes already indexed (transcript
        // beat us to it), and episodes with empty title+description.
        var chunks: [Chunk] = []
        var preparedIDs: [UUID] = []
        for id in claimable {
            guard let episode = appStore.episode(id: id),
                  !episode.metadataIndexed,
                  let chunk = Self.makeChunk(for: episode) else { continue }
            chunks.append(chunk)
            preparedIDs.append(id)
        }
        guard !chunks.isEmpty else { return 0 }

        do {
            try await store.upsert(chunks: chunks)
            appStore.setEpisodesMetadataIndexed(preparedIDs)
            Self.logger.debug(
                "indexed metadata for \(preparedIDs.count, privacy: .public) episodes"
            )
            return preparedIDs.count
        } catch {
            // Don't flip the flag — next kernel frame re-surfaces the same IDs.
            // Common causes: missing embeddings key, rate limits, transient
            // network errors — all resolved by a later run.
            Self.logger.notice(
                "metadata index batch failed (\(preparedIDs.count, privacy: .public) episodes): \(String(describing: error), privacy: .public)"
            )
            return 0
        }
    }

    // MARK: Helpers

    /// Build the synthetic chunk for an episode. Returns `nil` when there
    /// is no text worth embedding.
    private static func makeChunk(for episode: Episode) -> Chunk? {
        let titleText = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionPlain = EpisodeShowNotesFormatter.plainText(from: episode.description)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [titleText, descriptionPlain].filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        let text = parts.joined(separator: "\n\n")
        return Chunk(
            episodeID: episode.id,
            podcastID: episode.podcastID,
            text: text,
            startMS: 0,
            endMS: 0,
            speakerID: nil
        )
    }
}
