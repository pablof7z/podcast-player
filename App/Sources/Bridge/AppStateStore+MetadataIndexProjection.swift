import Foundation

// MARK: - Kernel-driven metadata-index backfill (D7)
//
// The kernel surfaces `PodcastUpdate.pendingMetadataIndexIds` (kernel-selected,
// already capped at the kernel batch size) + `metadataIndexInterBatchDelayMs`
// on every Library-domain push frame. This extension wires those into the
// SINGLE serialized driver owned by `EpisodeMetadataIndexer`.
//
// Concurrency contract (see `EpisodeMetadataIndexer.startDraining`):
//   - One driver at a time. A Library frame that arrives while the driver is
//     running does NOT spawn a parallel driver; it just refreshes the candidate
//     source the driver re-reads on its next iteration (no lost wakeup).
//   - The kernel-owned pacing delay gates the NEXT batch claim, not a detached
//     tail sleep — so an unrelated Library bump can no longer fire a zero-delay
//     batch.
//   - Halt-on-failure: a zero-success batch stops the driver; a later Library
//     bump restarts the idle driver, which re-reads the still-pending candidates.

extension AppStateStore {

    /// Ensure the serialized metadata-index driver is running for the current
    /// kernel snapshot. Called from the kernel observation loop after each
    /// `applyKernelState`. No-op when the snapshot has no pending candidates and
    /// no driver is running.
    @MainActor
    func applyMetadataIndexBatch(from snapshot: PodcastUpdate) {
        // Cheap early-out: nothing to do when this frame carries no candidates.
        // (If a driver is already running on an earlier frame's candidates,
        // `startDraining` is a no-op anyway and the running driver re-reads the
        // live source itself.)
        guard !snapshot.pendingMetadataIndexIds.isEmpty else { return }

        EpisodeMetadataIndexer.shared.startDraining(
            appStore: self,
            nextBatch: { [weak self] in self?.currentMetadataIndexBatch() ?? [] },
            delayMs: { [weak self] in
                self?.kernel?.podcastSnapshot?.metadataIndexInterBatchDelayMs ?? 0
            }
        )
    }

    /// The current kernel-selected batch of pending episode IDs, read LIVE from
    /// the latest projected snapshot and filtered against episodes already
    /// flagged `metadataIndexed` in local state.
    ///
    /// The local filter handles the window between a successful
    /// `MarkEpisodesMetadataIndexed` dispatch (which flips the local flag via
    /// `setEpisodesMetadataIndexed`) and the kernel's async reprojection landing
    /// a refreshed `pendingMetadataIndexIds`. Without it the driver could re-read
    /// the same IDs and tight-loop on a stale snapshot; with it the driver sees
    /// an empty batch and idles until the kernel surfaces the next real batch.
    @MainActor
    func currentMetadataIndexBatch() -> [UUID] {
        let pending = kernel?.podcastSnapshot?.pendingMetadataIndexIds ?? []
        guard !pending.isEmpty else { return [] }
        return pending.compactMap { idStr -> UUID? in
            guard let id = UUID(uuidString: idStr) else { return nil }
            // Skip episodes already indexed locally (snapshot may lag a mark).
            if episode(id: id)?.metadataIndexed == true { return nil }
            return id
        }
    }
}
