import XCTest
@testable import Podcastr

/// Unit tests for `PlaybackState` seek-history ("browser back") feature.
///
/// `PlaybackState+SeekHistory.swift` pushes a history entry on every
/// navigational jump > 2 s, caps the stack at 20, and `jumpBack()` restores
/// the most recent saved (episode, position) pair.
@MainActor
final class PlaybackSeekHistoryTests: XCTestCase {

    // MARK: - Helpers

    private func makeEpisode(id: UUID = UUID()) -> Episode {
        Episode(
            id: id,
            podcastID: UUID(),
            guid: id.uuidString,
            title: "Episode \(id)",
            pubDate: Date(),
            duration: 600,
            enclosureURL: URL(string: "https://example.com/\(id.uuidString).mp3")!
        )
    }

    // MARK: - navigationalSeek pushes history

    func testNavigationalSeekPushesEntryWhenJumpExceedsThreshold() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)
        state.engine.seek(to: 100)

        state.navigationalSeek(to: 300)

        XCTAssertEqual(state.seekHistory.count, 1)
        XCTAssertEqual(state.seekHistory.last?.position ?? -1, 100, accuracy: 0.01,
            "History entry must capture the position BEFORE the jump")
    }

    func testNavigationalSeekDoesNotPushWhenJumpUnderThreshold() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)
        state.engine.seek(to: 100)

        state.navigationalSeek(to: 101.5)   // Δ = 1.5 s < 2 s

        XCTAssertTrue(state.seekHistory.isEmpty,
            "Jumps ≤ 2 s must not pollute the back stack")
    }

    func testNavigationalSeekPushesAtExactlyTwoSecondThreshold() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)
        state.engine.seek(to: 100)

        state.navigationalSeek(to: 102.01)  // Δ > 2 s

        XCTAssertEqual(state.seekHistory.count, 1,
            "Jumps strictly above 2 s must be recorded")
    }

    func testNavigationalSeekActuallySeeks() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)

        state.navigationalSeek(to: 250)

        XCTAssertEqual(state.engine.currentTime, 250, accuracy: 0.01)
    }

    // MARK: - History cap

    func testHistoryCappedAtTwentyEntries() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)

        // Generate 25 navigational jumps, each > 2 s apart.
        for i in 0..<25 {
            state.engine.seek(to: TimeInterval(i * 10))
            state.navigationalSeek(to: TimeInterval(i * 10 + 5))
        }

        XCTAssertEqual(state.seekHistory.count, 20,
            "History stack must be capped at 20 entries — oldest entries dropped first")
    }

    // MARK: - jumpBack

    func testJumpBackRestoresPreviousPosition() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)
        state.engine.seek(to: 100)
        state.navigationalSeek(to: 300)

        state.jumpBack()

        XCTAssertEqual(state.engine.currentTime, 100, accuracy: 0.01,
            "jumpBack must restore the position that was saved before the jump")
    }

    func testJumpBackPopsLastEntry() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)
        state.engine.seek(to: 50)
        state.navigationalSeek(to: 200)
        state.engine.seek(to: 200)
        state.navigationalSeek(to: 400)

        state.jumpBack()

        XCTAssertEqual(state.seekHistory.count, 1,
            "jumpBack must pop exactly one entry from the top of the stack")
    }

    func testJumpBackIsNoOpWhenHistoryIsEmpty() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)
        state.engine.seek(to: 100)

        state.jumpBack()  // no-op — nothing to pop

        XCTAssertEqual(state.engine.currentTime, 100, accuracy: 0.01,
            "jumpBack with an empty history must leave the playhead unchanged")
    }

    // MARK: - canJumpBack

    func testCanJumpBackFalseWhenHistoryEmpty() {
        let state = PlaybackState()
        XCTAssertFalse(state.canJumpBack)
    }

    func testCanJumpBackTrueAfterNavigationalSeek() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)
        state.engine.seek(to: 0)
        state.navigationalSeek(to: 100)
        XCTAssertTrue(state.canJumpBack)
    }

    func testCanJumpBackFalseAfterJumpBackDrainsHistory() {
        let state = PlaybackState()
        let episode = makeEpisode()
        state.setEpisode(episode)
        state.engine.seek(to: 0)
        state.navigationalSeek(to: 100)

        state.jumpBack()

        XCTAssertFalse(state.canJumpBack,
            "canJumpBack must be false once jumpBack exhausts the stack")
    }

    // MARK: - No-episode guard

    func testNavigationalSeekWithNoEpisodeStillSeeks() {
        let state = PlaybackState()
        // No episode loaded — navigationalSeek must fall through to seek(to:)
        // without crashing or pushing to history.

        state.navigationalSeek(to: 50)

        XCTAssertTrue(state.seekHistory.isEmpty,
            "navigationalSeek must not push history when no episode is loaded")
    }
}
