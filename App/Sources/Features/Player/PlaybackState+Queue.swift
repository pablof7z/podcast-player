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

    /// Clear the entire Up Next queue. Used by the queue sheet's destructive
    /// "Clear queue" footer action.
    func clearQueue() {
        queue.removeAll()
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
        guard !queue.isEmpty else { return false }
        let nextID = queue.removeFirst()
        guard let next = resolve(nextID) else { return false }
        setEpisode(next)
        play()
        return true
    }
}
