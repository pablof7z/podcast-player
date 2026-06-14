import Foundation
import os.log

// MARK: - Kernel-driven metadata-index backfill (D7)
//
// The kernel surfaces `PodcastUpdate.pendingMetadataIndexIds` on every
// Library-domain push frame after a `MarkEpisodesMetadataIndexed` action
// bumps `Domain::Library`. This extension wires the projection to the
// thin `EpisodeMetadataIndexer` executor.
//
// Halt-on-failure parity: if `indexKernelBatch` returns 0 (embed failure)
// the task exits. The kernel will re-surface the same candidates on the
// next frame (whenever `Domain::Library` is bumped by any other mutation),
// so a transient provider error auto-retries without a fixed timer.

extension AppStateStore {

    nonisolated private static let logger = Logger.app("MetadataIndexProjection")

    /// Trigger one embed batch from a kernel snapshot frame.
    ///
    /// Called from the kernel observation loop whenever `snapshot.pendingMetadataIndexIds`
    /// is non-empty. Fires-and-forgets a Task so the observation loop is not blocked
    /// while the network-bound embed call runs.
    ///
    /// The inter-batch delay (`snapshot.metadataIndexInterBatchDelayMs`) is applied
    /// INSIDE the spawned Task, after a successful batch, to throttle the embeddings
    /// provider. The kernel re-surfaces the next batch automatically (via the
    /// `MarkEpisodesMetadataIndexed` → `bump_domain(Library)` → push-frame cycle),
    /// so the delay is a pacing mechanism rather than a retry interval.
    @MainActor
    func applyMetadataIndexBatch(from snapshot: PodcastUpdate) {
        let pendingIds = snapshot.pendingMetadataIndexIds
        guard !pendingIds.isEmpty else { return }
        let interBatchDelayMs = snapshot.metadataIndexInterBatchDelayMs
        let uuids = pendingIds.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let count = await EpisodeMetadataIndexer.shared.indexKernelBatch(
                ids: uuids,
                appStore: self
            )
            if count > 0, interBatchDelayMs > 0 {
                // Pace the embeddings provider between batches.
                let delayNs = UInt64(interBatchDelayMs) * 1_000_000
                try? await Task.sleep(nanoseconds: delayNs)
            }
            if count == 0 {
                Self.logger.notice(
                    "metadata-index batch failed for \(uuids.count, privacy: .public) episodes — halting until next Library frame"
                )
            }
        }
    }
}
