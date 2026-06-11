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

    // MARK: - Download-resolution predicate (AgentTTSComposer.waitForDownload)
    //
    // `AgentTTSComposer.resolveEpisodeAudio` replaced a 1s `Task.sleep` poll
    // loop (D8 violation) with an `awaitState` predicate keyed on the episode's
    // `downloadState`, mapping `.downloaded` → `.success(url)`, `.failed` →
    // `.failure`, and a deadline-exhausted `awaitState` → `nil` (timeout). These
    // tests pin that exact predicate shape against the public
    // `setEpisodeDownloadState` seam, so a regression in the awaiter that the
    // composer depends on is caught here without exercising ElevenLabs/stitching.

    /// `.downloaded` resolves the predicate to `.success` reactively, the moment
    /// the kernel projection flips `downloadState` — not on a timer.
    func testDownloadPredicateResolvesSuccessOnDownloaded() async {
        let target = insertEpisode(guid: "dl-ok")
        let localURL = URL(fileURLWithPath: "/tmp/dl-ok.mp3")

        let waiter = Task { @MainActor in
            await store.awaitState(timeout: .seconds(5)) { [weak store] () -> Result<URL, Error>? in
                guard let episode = store?.episode(id: target.id) else { return nil }
                switch episode.downloadState {
                case .downloaded(let url, _): return .success(url)
                case .failed(let message):
                    return .failure(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
                default: return nil
                }
            }
        }

        await Task.yield()
        store.setEpisodeDownloadState(target.id, state: .downloaded(localFileURL: localURL, byteCount: 1))

        let result = await waiter.value
        guard case .success(let url) = result else {
            return XCTFail("expected .success, got \(String(describing: result))")
        }
        XCTAssertEqual(url, localURL)
    }

    /// `.failed` resolves the predicate to `.failure` — the composer maps this to
    /// `AgentTTSError.snippetDownloadFailed`.
    func testDownloadPredicateResolvesFailureOnFailed() async {
        let target = insertEpisode(guid: "dl-fail")

        let waiter = Task { @MainActor in
            await store.awaitState(timeout: .seconds(5)) { [weak store] () -> Result<URL, Error>? in
                guard let episode = store?.episode(id: target.id) else { return nil }
                switch episode.downloadState {
                case .downloaded(let url, _): return .success(url)
                case .failed(let message):
                    return .failure(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
                default: return nil
                }
            }
        }

        await Task.yield()
        store.setEpisodeDownloadState(target.id, state: .failed(message: "boom"))

        let result = await waiter.value
        guard case .failure(let error) = result else {
            return XCTFail("expected .failure, got \(String(describing: result))")
        }
        XCTAssertEqual((error as NSError).localizedDescription, "boom")
    }

    /// A download that never settles returns `nil` at the deadline — the
    /// composer maps this to `AgentTTSError.snippetDownloadTimeout`.
    func testDownloadPredicateTimesOutWhenNeverSettles() async {
        let target = insertEpisode(guid: "dl-stall")
        // Leave it in the default (`.notDownloaded`) state — never resolves.

        let result: Result<URL, Error>? = await store.awaitState(timeout: .milliseconds(200)) {
            [weak store] () -> Result<URL, Error>? in
            guard let episode = store?.episode(id: target.id) else { return nil }
            if case .downloaded(let url, _) = episode.downloadState { return .success(url) }
            return nil
        }

        XCTAssertNil(result)
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
