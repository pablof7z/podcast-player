import Foundation

// MARK: - Queue (Up Next)

extension PlaybackState {

    /// Append an episode to the end of the Up Next queue. No-op if the
    /// episode is already queued or is the currently-playing episode — the
    /// queue is intentionally a set-by-identity to avoid the user accidentally
    /// stacking the same episode three times.
    func enqueue(_ episodeID: UUID) {
        guard episodeID != episode?.id else { return }
        guard !queue.contains(episodeID) else { return }
        queue.append(episodeID)
    }

    /// Remove an episode from the Up Next queue. Idempotent.
    func removeFromQueue(_ episodeID: UUID) {
        queue.removeAll { $0 == episodeID }
    }

    /// Move queue entries (List `.onMove` compatible). `source` indices are in
    /// the pre-move array; `destination` is the insertion point in the
    /// post-removal array — matches `Array.move(fromOffsets:toOffset:)`.
    func moveQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
    }

    /// Move queue entries after first dropping stale IDs that no longer resolve
    /// to live episodes. SwiftUI hands `source`/`destination` in visible-row
    /// coordinates; after pruning, `queue` matches that visible list.
    func moveQueue(from source: IndexSet, to destination: Int, resolve: (UUID) -> Episode?) {
        pruneQueue(resolve: resolve)
        queue.move(fromOffsets: source, toOffset: min(destination, queue.count))
    }

    /// Clear the entire Up Next queue. Used by the queue sheet's destructive
    /// "Clear queue" footer action.
    func clearQueue() {
        queue.removeAll()
    }

    @discardableResult
    func pruneQueue(resolve: (UUID) -> Episode?) -> Int {
        let oldCount = queue.count
        queue.removeAll { resolve($0) == nil }
        return oldCount - queue.count
    }

    /// Pop the head of the queue and start playing it. Returns `true` when an
    /// episode was actually played, `false` when the queue is empty or the
    /// resolver couldn't materialise the head episode (e.g. it was deleted
    /// from the store between enqueue and dequeue).
    ///
    /// Takes a `resolve` closure rather than holding an `AppStateStore`
    /// reference directly so `PlaybackState` stays unit-testable. Callers in
    /// the UI pass `{ store.episode(id: $0) }`.
    @discardableResult
    func playNext(resolve: (UUID) -> Episode?) -> Bool {
        while !queue.isEmpty {
            let nextID = queue.removeFirst()
            guard let next = resolve(nextID) else { continue }
            setEpisode(next)
            play()
            return true
        }
        return false
    }
}
