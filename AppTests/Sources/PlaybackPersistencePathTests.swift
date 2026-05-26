import XCTest
@testable import Podcastr

/// Unit tests for the natural-end branch paths in `PlaybackState.tickPersistence()`.
///
/// These complement `PlaybackSegmentEndTests` (which tests bounded-segment end)
/// by covering the full-episode natural-end paths: `autoMarkPlayedOnFinish = false`
/// calls `onFlushPositions` instead of `onEpisodeFinished`, and the
/// `didFireFinishedFor` guard prevents the callback from firing more than once
/// per playthrough regardless of how many ticks follow.
@MainActor
final class PlaybackPersistencePathTests: XCTestCase {

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

    // MARK: - autoMarkPlayedOnFinish = false

    func testAutoMarkOffFlushesPositionButDoesNotCallOnEpisodeFinished() {
        let state = PlaybackState()
        let episode = makeEpisode(duration: 600)
        state.episode = episode
        state.autoMarkPlayedOnFinish = false
        state.engine.seek(to: 90)
        state.engine.didReachNaturalEnd = true

        var episodeFinishedCount = 0
        var flushed = false
        state.onEpisodeFinished = { _ in episodeFinishedCount += 1 }
        state.onFlushPositions = { flushed = true }

        state.tickPersistence()

        XCTAssertEqual(episodeFinishedCount, 0,
            "onEpisodeFinished must NOT fire when autoMarkPlayedOnFinish is false")
        XCTAssertTrue(flushed,
            "onFlushPositions must fire at natural end even when autoMarkPlayedOnFinish is false")
    }

    func testAutoMarkOnCallsOnEpisodeFinishedNotFlush() {
        let state = PlaybackState()
        let episode = makeEpisode(duration: 600)
        state.episode = episode
        state.autoMarkPlayedOnFinish = true
        state.engine.seek(to: 90)
        state.engine.didReachNaturalEnd = true

        var episodeFinishedCount = 0
        var flushed = false
        state.onEpisodeFinished = { _ in episodeFinishedCount += 1 }
        state.onFlushPositions = { flushed = true }

        state.tickPersistence()

        XCTAssertEqual(episodeFinishedCount, 1,
            "onEpisodeFinished must fire exactly once when autoMarkPlayedOnFinish is true")
        XCTAssertFalse(flushed,
            "onFlushPositions must NOT also fire in the auto-mark-on path")
    }

    // MARK: - didFireFinishedFor re-fire guard

    func testEpisodeFinishedDoesNotFireTwiceOnConsecutiveTicks() {
        let state = PlaybackState()
        let episode = makeEpisode(duration: 600)
        state.episode = episode
        state.autoMarkPlayedOnFinish = true
        state.engine.seek(to: 90)
        state.engine.didReachNaturalEnd = true

        var episodeFinishedCount = 0
        state.onEpisodeFinished = { _ in episodeFinishedCount += 1 }

        state.tickPersistence()
        state.tickPersistence()

        XCTAssertEqual(episodeFinishedCount, 1,
            "didFireFinishedFor guard must prevent onEpisodeFinished from firing more than once per playthrough")
    }

    func testAutoMarkOffFlushDoesNotFireTwiceOnConsecutiveTicks() {
        let state = PlaybackState()
        let episode = makeEpisode(duration: 600)
        state.episode = episode
        state.autoMarkPlayedOnFinish = false
        state.engine.seek(to: 90)
        state.engine.didReachNaturalEnd = true

        var flushedCount = 0
        state.onFlushPositions = { flushedCount += 1 }

        state.tickPersistence()
        state.tickPersistence()

        XCTAssertEqual(flushedCount, 1,
            "didFireFinishedFor guard applies to the flush path too — must fire at most once")
    }

    func testReplayAfterFinishedResetsDidFireGuard() {
        let state = PlaybackState()
        let episode = makeEpisode(duration: 600)
        state.episode = episode
        state.autoMarkPlayedOnFinish = true
        state.engine.seek(to: 90)
        state.engine.didReachNaturalEnd = true

        var episodeFinishedCount = 0
        state.onEpisodeFinished = { _ in episodeFinishedCount += 1 }

        state.tickPersistence()
        XCTAssertEqual(episodeFinishedCount, 1)

        // Simulate user replaying the same episode — setEpisode clears the guard.
        state.setEpisode(episode)
        state.engine.didReachNaturalEnd = true

        state.tickPersistence()
        XCTAssertEqual(episodeFinishedCount, 2,
            "setEpisode must reset the didFireFinishedFor guard so a replay produces a second finished event")
    }

    // MARK: - Position persistence on tick

    func testTickPersistenceWritesCurrentPositionWhenPlayheadNonZero() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.episode = episode
        state.engine.seek(to: 250)

        var persisted: [(UUID, TimeInterval)] = []
        state.onPersistPosition = { id, pos in persisted.append((id, pos)) }

        state.tickPersistence()

        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.0, episode.id)
        XCTAssertEqual(persisted.first?.1 ?? 0, 250, accuracy: 0.01,
            "tickPersistence must forward currentTime to onPersistPosition")
    }

    func testTickPersistenceDoesNotPersistWhenAtPositionZero() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.episode = episode
        // Engine starts at 0 — no position write expected.

        var persisted: [(UUID, TimeInterval)] = []
        state.onPersistPosition = { id, pos in persisted.append((id, pos)) }

        state.tickPersistence()

        XCTAssertTrue(persisted.isEmpty,
            "tickPersistence must not write position when currentTime is 0")
    }

    func testTickPersistenceIsNoOpWhenNoEpisodeLoaded() {
        let state = PlaybackState()

        var persisted: [(UUID, TimeInterval)] = []
        var episodeFinishedCount = 0
        state.onPersistPosition = { id, pos in persisted.append((id, pos)) }
        state.onEpisodeFinished = { _ in episodeFinishedCount += 1 }

        state.tickPersistence()

        XCTAssertTrue(persisted.isEmpty)
        XCTAssertEqual(episodeFinishedCount, 0,
            "tickPersistence must be a complete no-op when no episode is loaded")
    }
}
