import XCTest
@testable import Podcastr

/// Coverage for `PlaybackState.playNext(resolve:)` — the queue dequeue +
/// load + play sequence that drives auto-play-next when an episode
/// finishes. Wired from `RootView.onEpisodeFinished` so a non-empty Up
/// Next queue continues into the next episode automatically (default-on,
/// settings-gated).
@MainActor
final class PlaybackAutoPlayNextTests: XCTestCase {

    // MARK: - Helpers

    private func makeEpisode() -> Episode {
        Episode(
            subscriptionID: UUID(),
            guid: "test-\(UUID().uuidString)",
            title: "Test Episode",
            description: "",
            pubDate: Date(),
            duration: 1800,
            enclosureURL: URL(string: "https://example.com/ep.mp3")!
        )
    }

    // MARK: - playNext

    func testPlayNextReturnsFalseWhenQueueEmpty() {
        let state = PlaybackState()
        XCTAssertEqual(state.queue, [])
        let played = state.playNext { _ in nil }
        XCTAssertFalse(played)
    }

    func testPlayNextDequeuesHead() {
        let state = PlaybackState()
        let a = makeEpisode(), b = makeEpisode(), c = makeEpisode()
        state.enqueue(a.id)
        state.enqueue(b.id)
        state.enqueue(c.id)

        let resolver: (UUID) -> Episode? = { id in
            [a, b, c].first(where: { $0.id == id })
        }
        let played = state.playNext(resolve: resolver)

        XCTAssertTrue(played)
        XCTAssertEqual(state.queue, [b.id, c.id])
        XCTAssertEqual(state.episode?.id, a.id)
    }

    func testPlayNextSkipsHeadWhenResolverReturnsNil() {
        // If the queue head's episode no longer exists in the store
        // (e.g. user unsubscribed mid-listening), `playNext` should NOT
        // succeed — the caller will retry on the next episode-finish.
        // We dequeue the head regardless to avoid an infinite loop on
        // a permanently-unresolvable id.
        let state = PlaybackState()
        let stale = UUID()
        state.enqueue(stale)
        let played = state.playNext { _ in nil }
        XCTAssertFalse(played)
        XCTAssertEqual(state.queue, [], "Stale id should be dequeued so the loop progresses")
    }

    func testPlayNextRespectsQueueOrder() {
        // The queue is FIFO — calling `playNext` repeatedly walks the
        // list in insertion order.
        let state = PlaybackState()
        let a = makeEpisode(), b = makeEpisode()
        state.enqueue(a.id)
        state.enqueue(b.id)
        let resolver: (UUID) -> Episode? = { id in [a, b].first(where: { $0.id == id }) }

        _ = state.playNext(resolve: resolver)
        XCTAssertEqual(state.episode?.id, a.id)
        _ = state.playNext(resolve: resolver)
        XCTAssertEqual(state.episode?.id, b.id)
        XCTAssertTrue(state.queue.isEmpty)
    }
}
