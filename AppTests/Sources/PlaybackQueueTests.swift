import XCTest
@testable import Podcastr

/// Exercises the Up Next queue API on `PlaybackState`.
///
/// Scope is intentionally tight: we verify the array operations
/// (`enqueue`, `removeFromQueue`, `moveQueue`, `clearQueue`, `pruneQueue`).
/// `playNext(resolve:)` was removed in the autosnip migration — auto-advance
/// is now Rust-kernel-owned (exercised by `cargo test -p nmp-app-podcast audio`).
/// Those three test cases are deleted; the rest remain.
@MainActor
final class PlaybackQueueTests: XCTestCase {

    // MARK: - enqueue
    //
    // `enqueue` ordering and whole-episode de-duplication are now owned by the
    // Rust kernel queue (`PlaybackQueue::add_to_end`, covered by
    // `cargo test -p nmp-app-podcast queue`). On the Swift side `enqueue` only
    // dispatches to the kernel and marks a transient `pendingEnqueue` until the
    // authoritative projection arrives via `onQueueFromKernel` — it no longer
    // writes `PlaybackState.queue` directly, so a kernel-less unit test can't
    // assert ordering here. The end-to-end enqueue→"Queued" flow is covered by
    // the `testP0_QueueAddMultiple` UI test. The current-episode guard below is
    // pure Swift policy and stays unit-tested.

    func testEnqueueIgnoresCurrentEpisode() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.episode = episode

        state.enqueue(episode.id)

        XCTAssertTrue(state.queue.isEmpty)
    }

    // MARK: - removeFromQueue

    func testRemoveFromQueueDropsEntry() {
        let state = PlaybackState()
        let a = UUID(), b = UUID()
        // Seed via applyKernelQueue — the only authoritative writer of the queue.
        state.applyKernelQueue([a, b].map { .episode($0) })

        state.removeFromQueue(a)

        XCTAssertEqual(state.queue.map(\.episodeID), [b])
    }

    func testRemoveFromQueueIsIdempotent() {
        let state = PlaybackState()
        let a = UUID()

        state.removeFromQueue(a)  // no-op on empty queue
        state.applyKernelQueue([.episode(a)])
        state.removeFromQueue(a)
        state.removeFromQueue(a)  // no-op the second time

        XCTAssertTrue(state.queue.isEmpty)
    }

    // MARK: - moveQueue

    func testMoveQueueReordersEntries() {
        let state = PlaybackState()
        let a = UUID(), b = UUID(), c = UUID()
        state.applyKernelQueue([a, b, c].map { .episode($0) })

        // Move first item to the end. SwiftUI .onMove convention: destination
        // index is in the post-removal array, so end-of-list is `count`.
        state.moveQueue(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(state.queue.map(\.episodeID), [b, c, a])
    }

    // MARK: - clearQueue

    func testClearQueueEmptiesEverything() {
        let state = PlaybackState()
        state.applyKernelQueue([UUID(), UUID(), UUID()].map { .episode($0) })

        state.clearQueue()

        XCTAssertTrue(state.queue.isEmpty)
    }

    // MARK: - moveQueue with pruning

    func testMoveQueueCanPruneStaleEntriesBeforeReordering() {
        let state = PlaybackState()
        let stale = UUID()
        let a = UUID(), b = UUID(), c = UUID()
        state.applyKernelQueue([stale, a, b, c].map { .episode($0) })

        state.moveQueue(from: IndexSet(integer: 0), to: 3) { id in
            id == stale ? nil : makeEpisode(id: id)
        }

        XCTAssertEqual(state.queue.map(\.episodeID), [b, c, a])
    }

    func testPruneQueueDropsAllStaleEntries() {
        let state = PlaybackState()
        state.applyKernelQueue([UUID(), UUID(), UUID()].map { .episode($0) })

        let pruned = state.pruneQueue { _ in nil }

        XCTAssertEqual(pruned, 3)
        XCTAssertTrue(state.queue.isEmpty)
    }

    // MARK: - No-op reconciliation (Bug 1)

    /// Documents the contract that `applyKernelQueue` clears `pendingQueueOverride`
    /// even when the kernel's queue is IDENTICAL to the optimistic overlay — the
    /// "no-op" case where the dispatch was a logical no-op (removing a non-existent
    /// item, reordering to the same order, etc.). The Swift fix ensures the kernel
    /// calls `applyKernelQueue` after every round-trip via `queueProjectionGeneration`,
    /// but the reconciliation mechanism itself lives entirely in `PlaybackState` and
    /// can be exercised at the unit-test level.
    func testNoOpRemoveOverlayIsReconcileableByKernelResponse() {
        let state = PlaybackState()
        let a = UUID(), b = UUID()
        state.applyKernelQueue([a, b].map { .episode($0) })

        // Remove an episode that is NOT in the queue — sets overlay with same
        // content as kernelQueue (a no-op at the kernel level).
        state.removeFromQueue(UUID())
        XCTAssertEqual(state.queue.map(\.episodeID), [a, b],
                       "overlay content should match kernel (no-op removes nothing)")

        // Kernel responds with the unchanged queue (the no-op case). This mirrors
        // what applyKernelQueue does when KernelModel.queueProjectionGeneration fires
        // the observation even though snapshotContentHash did not change.
        state.applyKernelQueue([a, b].map { .episode($0) })

        // Overlay must be nil now — verify by issuing a new kernel update and
        // confirming it shows through without any stale override blocking it.
        state.applyKernelQueue([b].map { .episode($0) })
        XCTAssertEqual(state.queue.map(\.episodeID), [b],
                       "pendingQueueOverride must have been cleared by the no-op kernel response")
    }

    // MARK: - pruneQueue dispatches kernel dequeue (Bug 2)

    /// Verifies that `pruneQueue` sets an optimistic overlay for the surviving
    /// items and that the overlay reconciles correctly when the kernel confirms
    /// the removal. (The kernel dispatch itself cannot be verified at the unit-test
    /// level since `store` is nil; end-to-end persistence is covered by UI tests.)
    func testPruneQueueOverlayReconcilesByKernelResponse() {
        let state = PlaybackState()
        let a = UUID(), b = UUID(), stale = UUID()
        state.applyKernelQueue([a, stale, b].map { .episode($0) })

        let dropped = state.pruneQueue { id in
            id == stale ? nil : makeEpisode(id: id)
        }

        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(state.queue.map(\.episodeID), [a, b],
                       "overlay must exclude the stale item immediately")

        // Kernel confirms removal: applyKernelQueue should clear the overlay.
        state.applyKernelQueue([a, b].map { .episode($0) })

        // Overlay cleared — a subsequent kernel update shows through.
        state.applyKernelQueue([a].map { .episode($0) })
        XCTAssertEqual(state.queue.map(\.episodeID), [a],
                       "pendingQueueOverride must have been cleared after kernel confirmation")
    }

    // MARK: - Fixtures

    private func makeEpisode(id: UUID = UUID(), guid: String = UUID().uuidString) -> Episode {
        Episode(
            id: id,
            podcastID: UUID(),
            guid: guid,
            title: "Episode \(guid)",
            pubDate: Date(),
            enclosureURL: URL(string: "https://example.com/\(guid).mp3")!
        )
    }
}
