import Foundation

// MARK: - Queue (Up Next)
//
// `PlaybackState.queue` is a READ-ONLY projection of the Rust kernel queue.
// The kernel is the single source of truth; Swift never writes to `queue`
// directly. Instead, all user actions here:
//   1. Compute an optimistic result from the current `queue` (which itself
//      may already be an optimistic value if another action is in-flight).
//   2. Store that result in `pendingQueueOverride` so the UI updates
//      immediately (no visible lag waiting for the kernel round-trip).
//   3. Dispatch the corresponding kernel action.
//
// `applyKernelQueue(_:)` — called only by `onQueueFromKernel` —
// writes `kernelQueue` and clears `pendingQueueOverride`, reconciling the
// optimistic state with the authoritative kernel truth.
//
// This follows the `pendingEnqueue` precedent from #542/#564 and extends it
// to cover remove / move / clear / prune operations.

extension PlaybackState {

    // MARK: - Kernel projection write (sole writer of kernelQueue)

    /// Called exclusively by the `onQueueFromKernel` callback. Replaces the
    /// authoritative kernel queue and clears any pending optimistic overlay so
    /// the kernel projection becomes the new rendered state.
    func applyKernelQueue(_ items: [QueueItem]) {
        kernelQueue = items
        pendingQueueOverride = nil
    }

    // MARK: - Enqueueing

    /// Append a full-episode item to the Up Next queue. No-op when the episode
    /// is already the currently-playing episode. Unlike the previous
    /// `[UUID]`-based queue, the same episode *can* appear multiple times as
    /// bounded segments — but whole-episode duplicates are still deduplicated
    /// so a library-row "Queue" button can't stack the same full episode twice.
    ///
    /// Instant feedback is achieved via `pendingEnqueue`: on a synchronous
    /// `.accepted` result, the id is added to `pendingEnqueue` so `isQueued`
    /// returns `true` immediately. The kernel's authoritative queue projection
    /// (delivered via `onQueueFromKernel` / `applyKernelQueue`) is the sole
    /// writer to `kernelQueue`; `pendingEnqueue` entries are cleared as each
    /// id is confirmed by the projection. Swift never writes to `queue` here.
    func enqueue(_ episodeID: UUID) {
        guard episodeID != episode?.id else { return }
        let alreadyWhole = queue.contains { $0.episodeID == episodeID && $0.startSeconds == nil }
        guard !alreadyWhole else { return }
        guard !pendingEnqueue.contains(episodeID) else { return }
        if case .accepted = store?.kernelEnqueueLast(episodeID: episodeID) {
            pendingEnqueue.insert(episodeID)
        }
    }

    /// Append a `QueueItem` (possibly bounded) to the end of the queue.
    /// No deduplication — the agent intentionally queues multiple segments of
    /// the same episode. Sets an optimistic overlay immediately; the kernel
    /// projection confirms and clears it on the next snapshot tick.
    func enqueueItem(_ item: QueueItem) {
        var optimistic = queue
        optimistic.append(item)
        pendingQueueOverride = optimistic
        if let end = item.endSeconds {
            store?.kernelEnqueueSegmentLast(
                episodeID: item.episodeID.uuidString,
                startSeconds: item.startSeconds,
                endSeconds: end
            )
        } else {
            store?.kernelEnqueueLast(episodeID: item.episodeID)
        }
    }

    /// Insert a `QueueItem` at the head of Up Next so it plays after the
    /// currently-playing segment/episode finishes. No deduplication. Used by
    /// the agent's `play_episode` tool with `queue_position: "next"`.
    func insertNext(_ item: QueueItem) {
        var optimistic = queue
        optimistic.insert(item, at: 0)
        pendingQueueOverride = optimistic
        if let end = item.endSeconds {
            store?.kernelEnqueueSegmentNext(
                episodeID: item.episodeID.uuidString,
                startSeconds: item.startSeconds,
                endSeconds: end
            )
        } else {
            store?.kernelEnqueueNext(episodeID: item.episodeID)
        }
    }

    // MARK: - Removal

    /// Remove all queue items whose `episodeID` matches. Idempotent.
    func removeFromQueue(_ episodeID: UUID) {
        pendingQueueOverride = queue.filter { $0.episodeID != episodeID }
        store?.kernelDequeueEpisode(episodeID: episodeID)
    }

    /// Remove a single queue item by its stable slot identity.
    func removeFromQueue(itemID: UUID) {
        pendingQueueOverride = queue.filter { $0.id != itemID }
        store?.kernelDequeueQueueItem(queueSlotID: itemID)
    }

    // MARK: - Reordering / pruning

    func moveQueue(from source: IndexSet, to destination: Int) {
        var optimistic = queue
        optimistic.move(fromOffsets: source, toOffset: destination)
        pendingQueueOverride = optimistic
        store?.kernelReorderQueue(queueSlotIDs: optimistic.map(\.id))
    }

    func moveQueue(from source: IndexSet, to destination: Int, resolve: (UUID) -> Episode?) {
        // Prune stale items from the optimistic queue first (matching prior
        // behaviour: the list's onMove delegate prunes before reordering so
        // indices from the displayed list remain valid).
        var optimistic = queue.filter { resolve($0.episodeID) != nil }
        optimistic.move(fromOffsets: source, toOffset: min(destination, optimistic.count))
        pendingQueueOverride = optimistic
        store?.kernelReorderQueue(queueSlotIDs: optimistic.map(\.id))
    }

    func clearQueue() {
        pendingQueueOverride = []
        store?.kernelClearQueue()
    }

    /// Prune items whose episode can no longer be resolved (e.g. the user
    /// unsubscribed mid-queue). Sets an optimistic overlay immediately so the
    /// UI updates without waiting for the kernel, and dispatches a kernel
    /// dequeue for each dropped slot so the removal persists across restarts
    /// and the overlay reconciles on the next projection tick.
    @discardableResult
    func pruneQueue(resolve: (UUID) -> Episode?) -> Int {
        let current = queue
        let pruned = current.filter { resolve($0.episodeID) != nil }
        let dropped = current.count - pruned.count
        if dropped > 0 {
            pendingQueueOverride = pruned
            // Dispatch kernel dequeue for every pruned slot so the removal
            // is durable (survives restart) and the authoritative queue
            // projection confirms + clears the overlay. Removing by slot ID
            // (not episode ID) is safe here: each item has a stable slot
            // UUID from the kernel; removing by episode ID would also strip
            // any bounded segment of the same episode that IS resolvable.
            for item in current where resolve(item.episodeID) == nil {
                store?.kernelDequeueQueueItem(queueSlotID: item.id)
            }
        }
        return dropped
    }

    // MARK: - Convenience

    /// Returns `true` when any queue item targets the given episode (by full-
    /// episode whole or bounded segment), OR when an enqueue dispatch for this
    /// episode is pending kernel confirmation. Used by UI affordances to show
    /// "Remove from queue" vs "Add to queue".
    func isQueued(_ episodeID: UUID) -> Bool {
        queue.contains { $0.episodeID == episodeID } || pendingEnqueue.contains(episodeID)
    }

}
