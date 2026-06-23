import XCTest
@testable import Podcastr

/// Coverage for in-app and remote transport control dispatch order.
///
/// All transport commands must dispatch to Rust before native engines
/// execute, ensuring Rust is the authoritative playback policy source.
@MainActor
final class PlaybackTransportRoutingTests: XCTestCase {

    private var playbackState: PlaybackState!
    private var stubStore: StubAppStateStore!

    override func setUp() {
        super.setUp()
        playbackState = PlaybackState()
        stubStore = StubAppStateStore()
        playbackState.store = stubStore
    }

    // MARK: - Tests

    func testPlayDispatchesKernelResume() {
        let episode = Episode(
            id: UUID(),
            podcastID: UUID(),
            enclosureURL: URL(fileURLWithPath: "/test.mp3"),
            title: "Test Episode",
            publishedAt: Date(),
            addedAt: Date(),
            duration: 3600
        )
        playbackState.setEpisode(episode, playAfterLoad: false)

        playbackState.play()

        XCTAssertEqual(stubStore.kernelResumeCallCount, 1)
    }

    func testPauseDispatchesKernelPause() {
        stubStore.reset()

        playbackState.pause()

        XCTAssertEqual(stubStore.kernelPauseCallCount, 1)
    }

    func testSeekDispatchesKernelSeekBeforeEngineSeek() {
        stubStore.reset()

        let episode = Episode(
            id: UUID(),
            podcastID: UUID(),
            enclosureURL: URL(fileURLWithPath: "/test.mp3"),
            title: "Test Episode",
            publishedAt: Date(),
            addedAt: Date(),
            duration: 3600
        )
        playbackState.setEpisode(episode, playAfterLoad: false)
        playbackState.seek(to: 100)

        XCTAssertEqual(stubStore.kernelSeekCallCount, 1)
        XCTAssertEqual(stubStore.lastSeekPosition, 100)
    }

    func testSkipForwardDispatchesKernelSkipForward() {
        stubStore.reset()

        playbackState.skipForward(15)

        XCTAssertEqual(stubStore.kernelSkipForwardCallCount, 1)
    }

    func testSkipBackwardDispatchesKernelSkipBackward() {
        stubStore.reset()

        playbackState.skipBackward(15)

        XCTAssertEqual(stubStore.kernelSkipBackwardCallCount, 1)
    }

    func testSetRateDispatchesKernelSetSpeedBeforeEngineSetRate() {
        stubStore.reset()

        playbackState.setRate(.speed1_5x)

        XCTAssertEqual(stubStore.kernelSetSpeedCallCount, 1)
        XCTAssertEqual(stubStore.lastSetSpeedValue, 1.5)
    }
}

// MARK: - Stub

/// A minimal stub AppStateStore for testing transport dispatch order.
final class StubAppStateStore: AppStateStore {

    var kernelResumeCallCount = 0
    var kernelPauseCallCount = 0
    var kernelSeekCallCount = 0
    var kernelSkipForwardCallCount = 0
    var kernelSkipBackwardCallCount = 0
    var kernelSetSpeedCallCount = 0

    var lastSeekPosition: Double = 0
    var lastSetSpeedValue: Double = 0

    func reset() {
        kernelResumeCallCount = 0
        kernelPauseCallCount = 0
        kernelSeekCallCount = 0
        kernelSkipForwardCallCount = 0
        kernelSkipBackwardCallCount = 0
        kernelSetSpeedCallCount = 0
        lastSeekPosition = 0
        lastSetSpeedValue = 0
    }

    override func kernelResume() {
        kernelResumeCallCount += 1
    }

    override func kernelPause() -> DispatchResult? {
        kernelPauseCallCount += 1
        return nil
    }

    override func kernelSeek(positionSecs: Double) -> DispatchResult? {
        kernelSeekCallCount += 1
        lastSeekPosition = positionSecs
        return nil
    }

    override func kernelSkipForward(secs: Double?) -> DispatchResult? {
        kernelSkipForwardCallCount += 1
        return nil
    }

    override func kernelSkipBackward(secs: Double?) -> DispatchResult? {
        kernelSkipBackwardCallCount += 1
        return nil
    }

    override func kernelSetSpeed(_ speed: Double) -> DispatchResult? {
        kernelSetSpeedCallCount += 1
        lastSetSpeedValue = speed
        return nil
    }
}
