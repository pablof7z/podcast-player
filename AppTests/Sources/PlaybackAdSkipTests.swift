import XCTest
@testable import Podcastr

/// Unit tests for `PlaybackState.applyAutoSkipAdsIfNeeded(at:)`.
///
/// `AudioEngine.seek(to:)` synchronously updates `currentTime` before
/// dispatching to `AVPlayer`, so all assertions are synchronous — no async
/// coordination needed.
@MainActor
final class PlaybackAdSkipTests: XCTestCase {

    // MARK: - Helpers

    private func makeEpisode() -> Episode {
        Episode(
            podcastID: UUID(),
            guid: UUID().uuidString,
            title: "Test Episode",
            pubDate: Date(),
            enclosureURL: URL(string: "https://example.com/ep.mp3")!
        )
    }

    private func makeAdSegment(start: TimeInterval, end: TimeInterval, kind: Episode.AdKind = .midroll) -> Episode.AdSegment {
        Episode.AdSegment(start: start, end: end, kind: kind)
    }

    // MARK: - Basic skip behaviour

    func testSkipsAdWhenPlayheadInsideAndEnabled() {
        let state = PlaybackState()
        let ad = makeAdSegment(start: 100, end: 200)
        state.autoSkipAdsEnabled = true
        state.adSegments = [ad]

        state.applyAutoSkipAdsIfNeeded(at: 150)

        XCTAssertEqual(state.engine.currentTime, 200, accuracy: 0.001,
            "Engine must be seeked to the ad's end time")
    }

    func testDoesNothingWhenAutoSkipDisabled() {
        let state = PlaybackState()
        let ad = makeAdSegment(start: 100, end: 200)
        state.autoSkipAdsEnabled = false
        state.adSegments = [ad]

        state.applyAutoSkipAdsIfNeeded(at: 150)

        XCTAssertEqual(state.engine.currentTime, 0, accuracy: 0.001,
            "Engine must not seek when auto-skip is disabled")
    }

    func testDoesNothingWhenAdSegmentsEmpty() {
        let state = PlaybackState()
        state.autoSkipAdsEnabled = true
        state.adSegments = []

        state.applyAutoSkipAdsIfNeeded(at: 150)

        XCTAssertEqual(state.engine.currentTime, 0, accuracy: 0.001,
            "Engine must not seek when there are no ad segments")
    }

    func testDoesNothingWhenPlayheadOutsideAllAds() {
        let state = PlaybackState()
        state.autoSkipAdsEnabled = true
        state.adSegments = [makeAdSegment(start: 100, end: 200)]

        state.applyAutoSkipAdsIfNeeded(at: 50)

        XCTAssertEqual(state.engine.currentTime, 0, accuracy: 0.001,
            "Engine must not seek when playhead is outside all ads")
    }

    // MARK: - Per-session throttle

    func testDoesNotSkipSameAdTwiceInOneSession() {
        let state = PlaybackState()
        let ad = makeAdSegment(start: 100, end: 200)
        state.autoSkipAdsEnabled = true
        state.adSegments = [ad]

        state.applyAutoSkipAdsIfNeeded(at: 150)
        // Manually rewind the engine to simulate scrubbing back into the ad.
        state.engine.seek(to: 120)
        state.applyAutoSkipAdsIfNeeded(at: 120)

        XCTAssertEqual(state.engine.currentTime, 120, accuracy: 0.001,
            "A previously-skipped ad must not be auto-skipped again in the same session")
    }

    func testSkipsEachAdAtMostOnce() {
        let state = PlaybackState()
        let ad1 = makeAdSegment(start: 100, end: 200)
        let ad2 = makeAdSegment(start: 400, end: 500)
        state.autoSkipAdsEnabled = true
        state.adSegments = [ad1, ad2]

        state.applyAutoSkipAdsIfNeeded(at: 150)
        XCTAssertEqual(state.engine.currentTime, 200, accuracy: 0.001)

        state.applyAutoSkipAdsIfNeeded(at: 450)
        XCTAssertEqual(state.engine.currentTime, 500, accuracy: 0.001)

        // Both segments are now in the skipped set.
        XCTAssertEqual(state.skippedAdSegmentIDs.count, 2)
    }

    // MARK: - Interval boundary semantics

    func testSkipsWhenPlayheadIsExactlyAtStart() {
        let state = PlaybackState()
        let ad = makeAdSegment(start: 100, end: 200)
        state.autoSkipAdsEnabled = true
        state.adSegments = [ad]

        state.applyAutoSkipAdsIfNeeded(at: 100)

        XCTAssertEqual(state.engine.currentTime, 200, accuracy: 0.001,
            "Interval is [start, end) so exactly-at-start must trigger skip")
    }

    func testDoesNotSkipWhenPlayheadIsExactlyAtEnd() {
        let state = PlaybackState()
        let ad = makeAdSegment(start: 100, end: 200)
        state.autoSkipAdsEnabled = true
        state.adSegments = [ad]

        state.applyAutoSkipAdsIfNeeded(at: 200)

        XCTAssertEqual(state.engine.currentTime, 0, accuracy: 0.001,
            "Interval is [start, end) so exactly-at-end must NOT trigger skip")
    }

    // MARK: - skippedAdSegmentIDs cleared on episode change

    func testSkippedSetClearsOnNewEpisode() {
        let state = PlaybackState()
        let ad = makeAdSegment(start: 100, end: 200)
        state.autoSkipAdsEnabled = true
        state.adSegments = [ad]
        state.applyAutoSkipAdsIfNeeded(at: 150)
        XCTAssertFalse(state.skippedAdSegmentIDs.isEmpty)

        // Loading a new episode must reset the skipped-set.
        let newEpisode = makeEpisode()
        state.setEpisode(newEpisode)

        XCTAssertTrue(state.skippedAdSegmentIDs.isEmpty,
            "skippedAdSegmentIDs must be cleared when a new episode loads")
    }
}
