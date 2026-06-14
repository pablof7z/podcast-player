import Foundation
import os.log

// MARK: - EpisodeMetadataIndexer
//
// Thin executor for the kernel-driven metadata-index backfill (D7).
//
// The kernel owns POLICY:
//   - Which episodes are candidates (`PodcastUpdate.pendingMetadataIndexIds`)
//   - Batch size (kernel constant, surfaced via the push frame as the size of
//     `pendingMetadataIndexIds`)
//   - Inter-batch pacing VALUE (`PodcastUpdate.metadataIndexInterBatchDelayMs`)
//   - Halt-on-failure: a zero-success batch stops the driver
//
// The shell owns EXECUTION SERIALIZATION (the correct side of the
// "embedding stays in the shell" boundary):
//   1. Run a SINGLE long-lived serialized driver — never two at once.
//   2. Drain the current kernel batch, embed, dispatch `MarkEpisodesMetadataIndexed`.
//   3. Sleep `delay_ms` BEFORE claiming the next batch (the kernel-owned cooldown
//      actually gates successive embed calls — see `startDraining`).
//
// Why a serialized driver instead of one Task per push frame: the pacing delay
// must gate the NEXT claim. A fire-and-forget-per-frame design put the sleep at
// the tail of a detached task where it gated nothing, and an unrelated Library
// bump (star toggle, download tick, feed refresh) would fire a zero-delay batch.
// The driver reads its candidate source fresh each iteration, so a frame that
// arrives mid-drain just refreshes what the next loop reads — it never spawns a
// parallel driver.
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

    // MARK: Serialized driver

    /// The single live backfill driver, or `nil` when idle. Guarantees exactly
    /// one driver runs at a time: `startDraining` only spawns a new driver when
    /// this is `nil`. Because `EpisodeMetadataIndexer` is `@MainActor`, the
    /// `nil`-check + assignment in `startDraining` is atomic (no `await` between
    /// them), so two concurrent triggers cannot both pass the guard.
    private var driverTask: Task<Void, Never>?

    // MARK: Init

    init(store: VectorStore = RAGService.shared.index) {
        self.store = store
    }

    // MARK: Public API — serialized driver

    /// Start the serialized backfill driver if it is not already running.
    ///
    /// Called from the kernel-projection observer on every Library push frame
    /// (after `applyKernelState`). The contract — all reasoning rests on
    /// `@MainActor` serialization: a run of synchronous code with no `await`
    /// inside it cannot interleave with another main-actor task.
    ///
    /// - **Single driver:** the `driverTask == nil` guard and the
    ///   `driverTask = Task {…}` assignment run back-to-back with no `await`
    ///   between them, so two concurrent triggers can never both pass the guard.
    ///   A second trigger while a driver is live is a no-op; the live driver
    ///   re-reads `nextBatch()` next iteration, so mid-drain frames are absorbed
    ///   without spawning a parallel driver.
    /// - **No lost wakeup on the empty-exit path:** the driver's
    ///   `nextBatch()` read, the `guard !batch.isEmpty else { return }`, and the
    ///   `defer { driverTask = nil }` that fires on that return all execute in a
    ///   SINGLE main-actor-synchronous run (no `await` between the empty read and
    ///   the clear). A frame's `startDraining` therefore cannot observe the
    ///   intermediate state "batch is empty but `driverTask` still non-nil" — it
    ///   either runs entirely before this block (and the live driver picks up its
    ///   candidates) or entirely after (and sees `driverTask == nil`, starting a
    ///   fresh driver). Newly-arrived candidates are never dropped.
    /// - **Inter-batch pacing:** the driver sleeps `delayMs()` BEFORE claiming
    ///   the next batch (only after a successful, non-empty batch), so the
    ///   kernel-owned cooldown actually gates successive embed calls. A frame
    ///   arriving during `indexEpisodes`/`Task.sleep` does not spawn a parallel
    ///   driver (guard fails) and is absorbed by the next loop read.
    /// - **Halt-on-failure (intentional):** a zero-success batch stops the
    ///   driver and clears `driverTask`. A frame that arrived during the failing
    ///   embed already saw a live driver and bailed, so it does NOT trigger an
    ///   immediate retry — by design. The candidates remain pending (failure does
    ///   not mark them), so the NEXT Library bump restarts the idle driver, which
    ///   re-reads them and retries without a fixed timer. This matches the old
    ///   `runBackfill` "stop the backfill, resume on next launch" behavior.
    ///
    /// `nextBatch` and `delayMs` are `@MainActor` closures read fresh each
    /// iteration so the driver always sees the latest projected candidates and
    /// pacing value.
    func startDraining(
        appStore: AppStateStore,
        nextBatch: @escaping @MainActor () -> [UUID],
        delayMs: @escaping @MainActor () -> Int
    ) {
        // Single-driver guard: atomic on the main actor (no await before assign).
        guard driverTask == nil else { return }
        driverTask = Task { @MainActor [weak self, weak appStore] in
            defer { self?.driverTask = nil }
            while !Task.isCancelled {
                guard let self, let appStore else { return }
                let batch = nextBatch()
                // Empty batch → exit. The `defer` clears `driverTask`
                // synchronously (no await between this read and the return),
                // so the next frame's `startDraining` starts a fresh driver.
                guard !batch.isEmpty else { return }

                let count = await self.indexEpisodes(ids: batch, appStore: appStore)
                if count == 0 {
                    // Halt-on-failure: stop the driver. A later Library bump
                    // restarts it (the candidates are still pending), which
                    // retries without a fixed timer.
                    Self.logger.notice(
                        "metadata-index batch failed for \(batch.count, privacy: .public) episodes — halting until next Library frame"
                    )
                    return
                }

                // Pace the embeddings provider BEFORE claiming the next batch.
                let delay = delayMs()
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                }
            }
        }
    }

    /// Cancel the live driver (test teardown / app shutdown). Idempotent.
    func cancelDraining() {
        driverTask?.cancel()
        driverTask = nil
    }

    /// Execute a single batch of episode IDs directly (test seam).
    ///
    /// Returns the count of episodes successfully indexed; `0` on embed failure
    /// or an all-already-indexed batch. The serialized driver calls
    /// `indexEpisodes` directly; this wrapper exists so unit tests can exercise
    /// one batch without standing up the driver loop.
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
