import XCTest
@testable import Podcastr

/// Coverage for `AppStateStore.awaitState(timeout:body:)`, the reactive awaiter
/// that replaced the `Task.sleep(300ms)` polling loops in the kernel-action
/// helpers (`kernelSubscribe`, `kernelSummarizeEpisode`, `kernelEnsurePodcast`).
///
/// The discriminating test is `testTimeoutReturnsNilWhenStateNeverChanges`: the
/// awaiter must return `nil` near the deadline when the awaited state never
/// arrives. An earlier implementation suspended on `withObservationTracking`
/// alone — with no timeout racer it hung forever in exactly that case (the
/// `onChange` never fires when nothing mutates, so the deadline was never
/// re-evaluated). A compile check cannot catch that; only this test can.
@MainActor
final class ObservationAwaitTests: XCTestCase {

    private var fileURL: URL!
    private var store: AppStateStore!

    override func setUp() async throws {
        try await super.setUp()
        let made = AppStateTestSupport.makeIsolatedStore()
        fileURL = made.fileURL
        store = made.store
    }

    override func tearDown() async throws {
        AppStateTestSupport.disposeIsolatedStore(at: fileURL)
        store = nil
        fileURL = nil
        try await super.tearDown()
    }

    /// The hang regression: a predicate that never satisfies must still return
    /// `nil`, bounded by the timeout, rather than suspending forever.
    func testTimeoutReturnsNilWhenStateNeverChanges() async {
        let start = ContinuousClock.now
        let result: Int? = await store.awaitState(timeout: .milliseconds(200)) { nil }
        let elapsed = ContinuousClock.now - start

        XCTAssertNil(result)
        // Returned because the timeout fired — not instantly, not never.
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(150))
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    /// Fast path: an already-satisfied predicate returns immediately without
    /// suspending for any observed change.
    func testReturnsImmediatelyWhenAlreadySatisfied() async {
        let start = ContinuousClock.now
        let result: Int? = await store.awaitState(timeout: .seconds(5)) { 42 }
        let elapsed = ContinuousClock.now - start

        XCTAssertEqual(result, 42)
        XCTAssertLessThan(elapsed, .milliseconds(100))
    }

    /// Reactive path: a predicate reading an `@Observable` store property
    /// resolves the instant that property mutates — well before the (generous)
    /// timeout — proving the awaiter is driven by observation, not a timer.
    func testResolvesReactivelyWhenObservedPropertyChanges() async {
        let target = insertEpisode(guid: "await-ep")

        // Predicate reads `store.episodes`; satisfied once the episode is marked
        // played. Starts unsatisfied so the awaiter must suspend on observation.
        let waiter = Task { @MainActor in
            await store.awaitState(timeout: .seconds(5)) { [weak store] () -> Bool? in
                guard store?.episode(id: target.id)?.played == true else { return nil }
                return true
            }
        }

        // Yield so the awaiter arms its observation before we mutate, exercising
        // the suspend-then-onChange path rather than the fast path. `markEpisode
        // Played` writes the `@Observable` `episodes` property the predicate reads.
        await Task.yield()
        store.markEpisodePlayed(target.id)

        let result = await waiter.value
        XCTAssertEqual(result, true)
    }

    // MARK: - Fixtures

    @discardableResult
    private func insertEpisode(guid: String) -> Episode {
        let podcast = Podcast(
            feedURL: URL(string: "https://example.com/\(guid).xml")!,
            title: "Await Test Show"
        )
        store.upsertPodcast(podcast)
        let episode = Episode(
            podcastID: podcast.id,
            guid: guid,
            title: "Episode \(guid)",
            pubDate: Date(),
            enclosureURL: URL(string: "https://example.com/\(guid).mp3")!
        )
        store.upsertEpisodes([episode], forPodcast: podcast.id)
        return store.episodes(forPodcast: podcast.id).first { $0.guid == guid }!
    }
}
