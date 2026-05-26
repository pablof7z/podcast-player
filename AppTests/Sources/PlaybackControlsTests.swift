import XCTest
@testable import Podcastr

/// Unit tests for `PlaybackState+Controls.swift` — `applyPreferences(from:)` and
/// related settings-propagation paths.
///
/// `applyPreferences` is called by `RootView` on every `Settings` change, so
/// correctness here means user-visible settings (skip intervals, rate, ad-skip,
/// headphone gestures) take effect immediately without a relaunch.
@MainActor
final class PlaybackControlsTests: XCTestCase {

    private func makeEpisode() -> Episode {
        Episode(
            podcastID: UUID(),
            guid: UUID().uuidString,
            title: "Test Episode",
            pubDate: Date(),
            enclosureURL: URL(string: "https://example.com/ep.mp3")!
        )
    }

    // MARK: - applyPreferences — skip intervals

    func testApplyPreferencesPushesSkipIntervalsToEngine() {
        let state = PlaybackState()
        var settings = Settings()
        settings.skipForwardSeconds = 45
        settings.skipBackwardSeconds = 10

        state.applyPreferences(from: settings)

        XCTAssertEqual(state.engine.skipForwardSeconds, 45, accuracy: 0.01,
            "skipForwardSeconds must be forwarded to the engine")
        XCTAssertEqual(state.engine.skipBackwardSeconds, 10, accuracy: 0.01,
            "skipBackwardSeconds must be forwarded to the engine")
    }

    func testApplyPreferencesSkipIntervalClampedToMinimumOne() {
        let state = PlaybackState()
        var settings = Settings()
        settings.skipForwardSeconds = 0
        settings.skipBackwardSeconds = 0

        state.applyPreferences(from: settings)

        XCTAssertEqual(state.engine.skipForwardSeconds, 1, accuracy: 0.01,
            "Zero skip interval must be clamped to 1 second")
        XCTAssertEqual(state.engine.skipBackwardSeconds, 1, accuracy: 0.01,
            "Zero skip backward interval must be clamped to 1 second")
    }

    // MARK: - applyPreferences — default rate

    func testApplyPreferencesSetsDefaultRateWhenNoEpisodeLoaded() {
        let state = PlaybackState()
        var settings = Settings()
        settings.defaultPlaybackRate = 1.5

        state.applyPreferences(from: settings)

        XCTAssertEqual(state.engine.rate, 1.5, accuracy: 0.001,
            "Default rate must be applied to the engine when no episode is loaded")
    }

    func testApplyPreferencesDoesNotClobberRateWhenEpisodeIsLoaded() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)
        state.engine.setRate(1.75)

        var settings = Settings()
        settings.defaultPlaybackRate = 1.0

        state.applyPreferences(from: settings)

        XCTAssertEqual(state.engine.rate, 1.75, accuracy: 0.001,
            "applyPreferences must not reset the rate when an episode is already loaded")
    }

    // MARK: - applyPreferences — ad skip

    func testApplyPreferencesSetsAutoSkipAdsEnabled() {
        let state = PlaybackState()
        var settings = Settings()
        settings.autoSkipAds = true

        state.applyPreferences(from: settings)

        XCTAssertTrue(state.autoSkipAdsEnabled,
            "autoSkipAdsEnabled must reflect Settings.autoSkipAds")
    }

    func testApplyPreferencesSetsAutoSkipAdsDisabled() {
        let state = PlaybackState()
        state.autoSkipAdsEnabled = true
        var settings = Settings()
        settings.autoSkipAds = false

        state.applyPreferences(from: settings)

        XCTAssertFalse(state.autoSkipAdsEnabled,
            "autoSkipAdsEnabled must be cleared when Settings.autoSkipAds is false")
    }

    // MARK: - applyPreferences — headphone gesture actions

    func testApplyPreferencesSetsHeadphoneDoubleTapAction() {
        let state = PlaybackState()
        var settings = Settings()
        settings.headphoneDoubleTapAction = .skipBackward

        state.applyPreferences(from: settings)

        XCTAssertEqual(state.headphoneDoubleTapAction, .skipBackward,
            "headphoneDoubleTapAction must mirror Settings.headphoneDoubleTapAction")
    }

    func testApplyPreferencesSetsHeadphoneTripleTapAction() {
        let state = PlaybackState()
        var settings = Settings()
        settings.headphoneTripleTapAction = .nextChapter

        state.applyPreferences(from: settings)

        XCTAssertEqual(state.headphoneTripleTapAction, .nextChapter,
            "headphoneTripleTapAction must mirror Settings.headphoneTripleTapAction")
    }

    // MARK: - skipForwardSeconds / skipBackwardSeconds surface

    func testSkipSecondsSurfaceReadsFromEngine() {
        let state = PlaybackState()
        state.engine.skipForwardSeconds = 60
        state.engine.skipBackwardSeconds = 5

        XCTAssertEqual(state.skipForwardSeconds, 60,
            "state.skipForwardSeconds must reflect engine.skipForwardSeconds")
        XCTAssertEqual(state.skipBackwardSeconds, 5,
            "state.skipBackwardSeconds must reflect engine.skipBackwardSeconds")
    }

    // MARK: - persistAndFlushAfterUserSeek — time=0 guard

    func testPersistAndFlushDoesNotPersistWhenAtPositionZero() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)

        var persistedPositions: [(UUID, TimeInterval)] = []
        state.onPersistPosition = { id, pos in persistedPositions.append((id, pos)) }

        // Engine starts at 0 by default.
        state.persistAndFlushAfterUserSeek()

        XCTAssertTrue(persistedPositions.isEmpty,
            "persistAndFlushAfterUserSeek must not persist position when currentTime is 0")
    }

    func testPersistAndFlushPersistsAndFlushesWhenPositionIsNonZero() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)
        state.engine.seek(to: 120)

        var persistedPositions: [(UUID, TimeInterval)] = []
        var flushed = false
        state.onPersistPosition = { id, pos in persistedPositions.append((id, pos)) }
        state.onFlushPositions = { flushed = true }

        state.persistAndFlushAfterUserSeek()

        XCTAssertEqual(persistedPositions.count, 1)
        XCTAssertEqual(persistedPositions.first?.1 ?? 0, 120, accuracy: 0.01,
            "Must persist current time after user seek")
        XCTAssertTrue(flushed, "Must flush positions after user seek")
    }
}
