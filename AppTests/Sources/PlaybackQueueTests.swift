import XCTest
@testable import Podcastr

/// Exercises the Up Next queue API on `PlaybackState`.
///
/// Scope is intentionally tight: we verify the array operations
/// (`enqueue`, `removeFromQueue`, `moveQueue`, `clearQueue`) and the
/// resolver-based head-pop behaviour of `playNext(resolve:)`. We don't
/// touch `setEpisode`/`play()` semantics — those are covered (or will be)
/// by audio-engine integration tests; mixing the two would force these
/// tests to depend on AVFoundation side effects.
@MainActor
final class PlaybackQueueTests: XCTestCase {

    // MARK: - enqueue

    func testEnqueueAppendsInOrder() {
        let state = PlaybackState()
        let a = UUID(), b = UUID(), c = UUID()

        state.enqueue(a)
        state.enqueue(b)
        state.enqueue(c)

        XCTAssertEqual(state.queue.map(\.episodeID), [a, b, c])
    }

    func testEnqueueIgnoresDuplicate() {
        let state = PlaybackState()
        let a = UUID()

        state.enqueue(a)
        state.enqueue(a)

        XCTAssertEqual(state.queue.map(\.episodeID), [a])
    }

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
        state.enqueue(a)
        state.enqueue(b)

        state.removeFromQueue(a)

        XCTAssertEqual(state.queue.map(\.episodeID), [b])
    }

    func testRemoveFromQueueIsIdempotent() {
        let state = PlaybackState()
        let a = UUID()

        state.removeFromQueue(a)  // no-op on empty queue
        state.enqueue(a)
        state.removeFromQueue(a)
        state.removeFromQueue(a)  // no-op the second time

        XCTAssertTrue(state.queue.isEmpty)
    }

    // MARK: - moveQueue

    func testMoveQueueReordersEntries() {
        let state = PlaybackState()
        let a = UUID(), b = UUID(), c = UUID()
        state.enqueue(a)
        state.enqueue(b)
        state.enqueue(c)

        // Move first item to the end. SwiftUI .onMove convention: destination
        // index is in the post-removal array, so end-of-list is `count`.
        state.moveQueue(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(state.queue.map(\.episodeID), [b, c, a])
    }

    // MARK: - clearQueue

    func testClearQueueEmptiesEverything() {
        let state = PlaybackState()
        state.enqueue(UUID())
        state.enqueue(UUID())
        state.enqueue(UUID())

        state.clearQueue()

        XCTAssertTrue(state.queue.isEmpty)
    }

    // MARK: - playNext

    func testPlayNextReturnsFalseWhenQueueIsEmpty() {
        let state = PlaybackState()
        let played = state.playNext { _ in nil }
        XCTAssertFalse(played)
    }

    func testPlayNextPopsHeadAndCallsResolver() {
        let state = PlaybackState()
        let head = makeEpisode(guid: "head")
        let tail = makeEpisode(guid: "tail")
        state.enqueue(head.id)
        state.enqueue(tail.id)

        var resolverCalls: [UUID] = []
        let played = state.playNext { id in
            resolverCalls.append(id)
            return id == head.id ? head : nil
        }

        XCTAssertTrue(played)
        XCTAssertEqual(resolverCalls, [head.id])
        XCTAssertEqual(state.queue.map(\.episodeID), [tail.id])
        XCTAssertEqual(state.episode?.id, head.id)
    }

    func testPlayNextReturnsFalseWhenNoQueuedEpisodeResolves() {
        let state = PlaybackState()
        let stale = UUID()
        state.enqueue(stale)

        let played = state.playNext { _ in nil }

        XCTAssertFalse(played)
        XCTAssertTrue(state.queue.isEmpty)
    }

    func testMoveQueueCanPruneStaleEntriesBeforeReordering() {
        let state = PlaybackState()
        let stale = UUID()
        let a = UUID(), b = UUID(), c = UUID()
        state.queue = [stale, a, b, c].map { .episode($0) }

        state.moveQueue(from: IndexSet(integer: 0), to: 3) { id in
            id == stale ? nil : makeEpisode(id: id)
        }

        XCTAssertEqual(state.queue.map(\.episodeID), [b, c, a])
    }

    func testPruneQueueDropsAllStaleEntries() {
        let state = PlaybackState()
        state.queue = [UUID(), UUID(), UUID()].map { .episode($0) }

        let pruned = state.pruneQueue { _ in nil }

        XCTAssertEqual(pruned, 3)
        XCTAssertTrue(state.queue.isEmpty)
    }

    // MARK: - isQueued

    func testIsQueuedReturnsTrueWhenEpisodeIsInQueue() {
        let state = PlaybackState()
        let id = UUID()
        XCTAssertFalse(state.isQueued(id))
        state.enqueue(id)
        XCTAssertTrue(state.isQueued(id))
        state.removeFromQueue(id)
        XCTAssertFalse(state.isQueued(id))
    }

    // MARK: - removeFromQueue(itemID:)

    func testRemoveFromQueueByItemIDDropsMatchingSlot() {
        let state = PlaybackState()
        let a = UUID(), b = UUID()
        state.enqueue(a)
        state.enqueue(b)
        let itemID = state.queue[0].id

        state.removeFromQueue(itemID: itemID)

        XCTAssertEqual(state.queue.map(\.episodeID), [b])
    }

    // MARK: - enqueueItem / insertNext

    func testEnqueueItemAppendsAndFiresCallback() {
        let state = PlaybackState()
        var callbackCount = 0
        state.onQueueChanged = { _ in callbackCount += 1 }
        let item = QueueItem(episodeID: UUID(), startSeconds: 10, endSeconds: 60, label: "Intro")

        state.enqueueItem(item)

        XCTAssertEqual(state.queue.count, 1)
        XCTAssertEqual(state.queue[0].startSeconds, 10)
        XCTAssertEqual(callbackCount, 1)
    }

    func testInsertNextPushesToFrontAndFiresCallback() {
        let state = PlaybackState()
        var received: [[QueueItem]] = []
        state.onQueueChanged = { received.append($0) }
        let a = UUID(), b = UUID()
        state.enqueue(a)

        state.insertNext(.episode(b))

        XCTAssertEqual(state.queue.map(\.episodeID), [b, a], "insertNext must place b before a")
        XCTAssertEqual(received.count, 2, "each mutation fires onQueueChanged once")
    }

    // MARK: - enqueueSegments

    func testEnqueueSegmentsQueueOnlyAppendsAll() {
        let state = PlaybackState()
        let ep1 = makeEpisode(), ep2 = makeEpisode()
        let items: [QueueItem] = [.episode(ep1.id), .episode(ep2.id)]

        state.enqueueSegments(items, playNow: false) { id in
            id == ep1.id ? ep1 : ep2
        }

        XCTAssertEqual(state.queue.map(\.episodeID), [ep1.id, ep2.id])
        XCTAssertNil(state.episode, "playNow: false must not change the current episode")
    }

    func testEnqueueSegmentsCallsCallbackWhenFirstEpisodeIsUnavailable() {
        let state = PlaybackState()
        var callbackCount = 0
        state.onQueueChanged = { _ in callbackCount += 1 }

        let item = QueueItem.episode(UUID())
        state.enqueueSegments([item], playNow: true) { _ in nil }

        XCTAssertEqual(callbackCount, 1, "onQueueChanged must fire even when the first episode can't be resolved")
        XCTAssertEqual(state.queue.count, 1, "items must be added to the queue when episode is unavailable")
    }

    // MARK: - onQueueChanged callback

    func testOnQueueChangedFiresOnEnqueue() {
        let state = PlaybackState()
        var received: [[QueueItem]] = []
        state.onQueueChanged = { received.append($0) }

        state.enqueue(UUID())

        XCTAssertEqual(received.count, 1)
    }

    func testOnQueueChangedNotFiredWhenRemoveIsNoOp() {
        let state = PlaybackState()
        var callbackCount = 0
        state.onQueueChanged = { _ in callbackCount += 1 }

        state.removeFromQueue(UUID())  // queue is empty — nothing to remove

        XCTAssertEqual(callbackCount, 0, "removeFromQueue on empty queue must not fire onQueueChanged")
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
