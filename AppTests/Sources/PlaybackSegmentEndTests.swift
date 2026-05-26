import XCTest
@testable import Podcastr

/// Unit tests for bounded-segment end detection in `PlaybackState.tickPersistence()`.
///
/// The contract: when `currentSegmentEndTime` is set and `engine.currentTime ≥ segEnd`,
/// `tickPersistence` must clear the boundary (preventing re-fire on the next tick)
/// and call `onSegmentFinished` exactly once. Natural-episode-end detection must
/// NOT fire in the same tick — the segment path returns early.
@MainActor
final class PlaybackSegmentEndTests: XCTestCase {

    // MARK: - Helpers

    private func makeEpisode(duration: TimeInterval = 600) -> Episode {
        Episode(
            podcastID: UUID(),
            guid: UUID().uuidString,
            title: "Test Episode",
            pubDate: Date(),
            duration: duration,
            enclosureURL: URL(string: "https://example.com/ep.mp3")!
        )
    }

    // MARK: - Segment end detection fires

    func testOnSegmentFinishedCalledWhenPlayheadCrossesBoundary() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.episode = episode
        state.currentSegmentEndTime = 100
        state.engine.seek(to: 110)

        var segmentFinishedCount = 0
        state.onSegmentFinished = { segmentFinishedCount += 1 }

        state.tickPersistence()

        XCTAssertEqual(segmentFinishedCount, 1,
            "onSegmentFinished must be called exactly once when playhead exceeds segmentEndTime")
    }

    func testCurrentSegmentEndTimeClearedBeforeCallbackFires() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.episode = episode
        state.currentSegmentEndTime = 100
        state.engine.seek(to: 110)

        var endTimeAtFireTime: Double? = -1
        state.onSegmentFinished = {
            endTimeAtFireTime = state.currentSegmentEndTime
        }

        state.tickPersistence()

        XCTAssertNil(endTimeAtFireTime,
            "currentSegmentEndTime must be cleared BEFORE onSegmentFinished fires to prevent re-fire on the next tick")
    }

    func testSegmentEndDoesNotFireWhenPlayheadBeforeBoundary() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.episode = episode
        state.currentSegmentEndTime = 100
        state.engine.seek(to: 50)

        var segmentFinishedCount = 0
        state.onSegmentFinished = { segmentFinishedCount += 1 }

        state.tickPersistence()

        XCTAssertEqual(segmentFinishedCount, 0,
            "onSegmentFinished must NOT fire when playhead is before the segment end boundary")
    }

    func testSegmentEndFiresWhenPlayheadExactlyAtBoundary() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.episode = episode
        state.currentSegmentEndTime = 100
        state.engine.seek(to: 100)

        var segmentFinishedCount = 0
        state.onSegmentFinished = { segmentFinishedCount += 1 }

        state.tickPersistence()

        XCTAssertEqual(segmentFinishedCount, 1,
            "onSegmentFinished must fire when playhead is exactly at the segment end boundary (≥ semantics)")
    }

    // MARK: - Segment path vs. natural-end path mutual exclusion

    func testNaturalEndDoesNotFireInSameTickAsSegmentEnd() {
        let state = PlaybackState()
        let episode = makeEpisode(duration: 100)
        state.episode = episode
        state.currentSegmentEndTime = 100
        state.engine.seek(to: 100)
        state.engine.didReachNaturalEnd = true

        var episodeFinishedCount = 0
        var segmentFinishedCount = 0
        state.onEpisodeFinished = { _ in episodeFinishedCount += 1 }
        state.onSegmentFinished = { segmentFinishedCount += 1 }
        state.autoMarkPlayedOnFinish = true

        state.tickPersistence()

        XCTAssertEqual(segmentFinishedCount, 1, "segment end must fire")
        XCTAssertEqual(episodeFinishedCount, 0,
            "onEpisodeFinished must NOT fire in the same tick as onSegmentFinished — the segment path returns early")
    }

    // MARK: - No segment boundary (full-episode path)

    func testNaturalEndFiresWhenNoSegmentBoundarySet() {
        let state = PlaybackState()
        let episode = makeEpisode(duration: 100)
        state.episode = episode
        state.currentSegmentEndTime = nil
        state.engine.seek(to: 90)
        state.engine.didReachNaturalEnd = true

        var episodeFinishedCount = 0
        state.onEpisodeFinished = { _ in episodeFinishedCount += 1 }
        state.autoMarkPlayedOnFinish = true

        state.tickPersistence()

        XCTAssertEqual(episodeFinishedCount, 1,
            "onEpisodeFinished must fire at natural end when no segment boundary is set")
    }

    // MARK: - Re-fire guard

    func testSegmentFinishedDoesNotFireTwiceOnConsecutiveTicks() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.episode = episode
        state.currentSegmentEndTime = 100
        state.engine.seek(to: 110)

        var segmentFinishedCount = 0
        state.onSegmentFinished = { segmentFinishedCount += 1 }

        state.tickPersistence()
        // Simulate: the segment-finished callback was slow (no advance yet), tick fires again.
        state.tickPersistence()

        XCTAssertEqual(segmentFinishedCount, 1,
            "Clearing currentSegmentEndTime on the first tick prevents onSegmentFinished re-firing on subsequent ticks")
    }

    // MARK: - clearQueue clears boundary

    func testClearQueueAlsoClearsSegmentEndTime() {
        let state = PlaybackState()
        state.currentSegmentEndTime = 100
        state.enqueue(UUID())

        state.clearQueue()

        XCTAssertNil(state.currentSegmentEndTime,
            "clearQueue must clear currentSegmentEndTime so a subsequent full-episode play is not accidentally bounded")
    }
}
