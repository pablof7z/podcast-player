import AudioToolbox
import Foundation

// MARK: - Queue (Up Next)

extension PlaybackState {

    // MARK: - Enqueueing

    /// Append a full-episode item to the Up Next queue. No-op when the episode
    /// is already the currently-playing episode. Unlike the previous
    /// `[UUID]`-based queue, the same episode *can* appear multiple times as
    /// bounded segments — but whole-episode duplicates are still deduplicated
    /// so a library-row "Queue" button can't stack the same full episode twice.
    func enqueue(_ episodeID: UUID) {
        guard episodeID != episode?.id else { return }
        let alreadyWhole = queue.contains { $0.episodeID == episodeID && $0.startSeconds == nil }
        guard !alreadyWhole else { return }
        queue.append(.episode(episodeID))
        store?.kernelEnqueueLast(episodeID: episodeID)
    }

    /// Append a `QueueItem` (possibly bounded) to the end of the queue.
    /// No deduplication — the agent intentionally queues multiple segments of
    /// the same episode.
    func enqueueItem(_ item: QueueItem) {
        queue.append(item)
    }

    /// Insert a `QueueItem` at the head of Up Next so it plays after the
    /// currently-playing segment/episode finishes. No deduplication. Used by
    /// the agent's `play_episode` tool with `queue_position: "next"`.
    func insertNext(_ item: QueueItem) {
        queue.insert(item, at: 0)
        if item.startSeconds == nil {
            store?.kernelEnqueueNext(episodeID: item.episodeID)
        }
    }

    /// Replace the current queue with an ordered list of `QueueItem`s and,
    /// if `playNow` is true, immediately dequeue and play the first one.
    /// The `playNow` path is the engine primitive behind the agent's
    /// `play_episode` tool with `queue_position: "now"` (single item) and
    /// behind callers that want to start a chain of segments.
    func enqueueSegments(_ items: [QueueItem], playNow: Bool, resolve: (UUID) -> Episode?) {
        guard !items.isEmpty else { return }
        if playNow {
            let first = items[0]
            guard let episode = resolve(first.episodeID) else {
                queue.append(contentsOf: items)
                return
            }
            enqueueSegments(items, playNow: true, head: episode)
        } else {
            queue.append(contentsOf: items)
        }
    }

    /// `enqueueSegments` variant that takes an already-resolved head `Episode`
    /// for the first item, bypassing the `store.episode(id:)` lookup for that
    /// item only. Used by external-play, where the episode lives in the Rust
    /// kernel (dispatched via `kernelAddEpisode`) and rides the next projection
    /// push — so it is not yet readable from `store.episodes` when playback must
    /// start synchronously. Tail items still resolve from the store as usual.
    func enqueueSegments(_ items: [QueueItem], playNow: Bool, head: Episode) {
        guard !items.isEmpty else { return }
        guard playNow else {
            queue.append(contentsOf: items)
            return
        }
        let first = items[0]
        // Set the segment boundary AFTER `setEpisode`: loading a different
        // episode clears `currentSegmentEndTime`, so setting it first would
        // be wiped and the clip would play through the whole episode.
        setEpisode(head)
        currentSegmentEndTime = first.endSeconds
        if let start = first.startSeconds {
            engine.seek(to: start)
        }
        play()
        queue.insert(contentsOf: items.dropFirst(), at: 0)
    }

    // MARK: - Removal

    /// Remove all queue items whose `episodeID` matches. Idempotent.
    func removeFromQueue(_ episodeID: UUID) {
        queue.removeAll { $0.episodeID == episodeID }
        store?.kernelDequeueEpisode(episodeID: episodeID)
    }

    /// Remove a single queue item by its stable slot identity.
    func removeFromQueue(itemID: UUID) {
        queue.removeAll { $0.id == itemID }
    }

    // MARK: - Reordering / pruning

    func moveQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
    }

    func moveQueue(from source: IndexSet, to destination: Int, resolve: (UUID) -> Episode?) {
        pruneQueue(resolve: resolve)
        queue.move(fromOffsets: source, toOffset: min(destination, queue.count))
    }

    func clearQueue() {
        queue.removeAll()
        currentSegmentEndTime = nil
        store?.kernelClearQueue()
    }

    @discardableResult
    func pruneQueue(resolve: (UUID) -> Episode?) -> Int {
        let oldCount = queue.count
        queue.removeAll { resolve($0.episodeID) == nil }
        return oldCount - queue.count
    }

    // MARK: - Convenience

    /// Returns `true` when any queue item targets the given episode (by full-
    /// episode whole or bounded segment). Used by UI affordances to show
    /// "Remove from queue" vs "Add to queue".
    func isQueued(_ episodeID: UUID) -> Bool {
        queue.contains { $0.episodeID == episodeID }
    }

    // MARK: - Advance

    /// Pop the head of the queue and start playing it. Plays a subtle audio +
    /// haptic transition cue so the user knows the queue advanced. Returns
    /// `true` when an episode was actually started, `false` when the queue is
    /// empty or every pending episode has been deleted from the store.
    @discardableResult
    func playNext(resolve: (UUID) -> Episode?) -> Bool {
        while !queue.isEmpty {
            let item = queue.removeFirst()
            guard let next = resolve(item.episodeID) else { continue }
            // Boundary set AFTER `setEpisode` (which clears it on episode change),
            // otherwise the segment end is wiped and the clip plays through.
            setEpisode(next)
            currentSegmentEndTime = item.endSeconds
            if let start = item.startSeconds {
                engine.seek(to: start)
            }
            play()
            playQueueTransitionCue()
            return true
        }
        return false
    }

    // MARK: - Transition cue

    /// Brief multi-sensory cue that fires on every queue advance so the user
    /// knows the player moved to the next item. Uses a system UI sound (Tink,
    /// id 1007) which plays through the active audio route even while
    /// `.podcastPlayback` is active, paired with a selection haptic for
    /// headphone-only listeners who may not hear the sound.
    private func playQueueTransitionCue() {
        Haptics.selection()
        AudioServicesPlaySystemSound(1007)
    }
}
