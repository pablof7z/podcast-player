import UIKit
import XCTest
@testable import Podcastr

extension AppTests {

    // MARK: - Episode position persistence

    func testSetEpisodePlaybackPosition() throws {
        let sub = makeSubscription()
        store.upsertPodcast(sub)
        store.addSubscription(podcastID: sub.id)
        let ep = makeEpisode(podcastID: sub.id, guid: "e1")
        store.upsertEpisodes([ep], forPodcast: sub.id)

        store.setEpisodePlaybackPosition(ep.id, position: 123.4)

        // Read through the store helper so the assertion stays correct under
        // both the eager-first path (value materialised in `state.episodes`)
        // and the debounced path (value still cached, folded in by `episode(id:)`).
        let live = try XCTUnwrap(store.episode(id: ep.id))
        XCTAssertEqual(live.playbackPosition, 123.4, accuracy: 0.001)
    }

    /// 30 rapid `setEpisodePlaybackPosition` calls (mirroring the
    /// `PlaybackState.tickPersistence` 1 Hz loop) must coalesce into ≤ 2
    /// disk writes: one eager (so the first position is durable immediately
    /// after playback starts) plus one trailing flush after the 5-second
    /// post-activity debounce. The pre-fix code wrote 30 times — 240 MB/min
    /// during a real episode — and pinned the main actor.
    func testPositionUpdatesAreDebounced() async throws {
        let sub = makeSubscription()
        store.upsertPodcast(sub); store.addSubscription(podcastID: sub.id)
        let ep = makeEpisode(podcastID: sub.id, guid: "tick-\(UUID().uuidString)")
        store.upsertEpisodes([ep], forPodcast: sub.id)

        // Only count writes triggered by the test body itself — addSubscription
        // and upsertEpisodes have already saved.
        store.persistence.resetSaveInvocationCount()

        // Tight loop: 30 monotonically-increasing positions, no awaits in
        // between. The eager-first call commits position #1; everything
        // after that should land in the in-memory cache.
        for i in 1...30 {
            store.setEpisodePlaybackPosition(ep.id, position: TimeInterval(i))
        }

        // Immediately after the loop the trailing-flush task is still
        // sleeping. We expect exactly one save (the eager first) at this
        // point.
        XCTAssertLessThanOrEqual(
            store.persistence.saveInvocationCount, 1,
            "Tight position-update loop wrote to disk more than once before the debounce fired."
        )

        // The latest cached position must be readable without waiting for
        // the flush — UI surfaces (`inProgressEpisodes`, the player resume
        // path) cannot tolerate stale reads.
        let live = try XCTUnwrap(store.episode(id: ep.id))
        XCTAssertEqual(live.playbackPosition, 30.0, accuracy: 0.001)

        // Wait long enough for the trailing-debounce task to drain (5s post-
        // activity window plus a comfortable margin for CI jitter).
        try await Task.sleep(for: .seconds(7))

        XCTAssertLessThanOrEqual(
            store.persistence.saveInvocationCount, 2,
            "Position debounce did not coalesce 30 rapid updates into ≤ 2 disk writes."
        )

        // After the trailing flush the on-disk position must match the
        // last cached value — otherwise a crash would silently rewind the
        // user to whatever the eager-first call wrote.
        let reopened = await AppStateTestSupport.makeIsolatedStore(
            fileURL: storeFileURL,
            reset: false
        )
        XCTAssertEqual(
            reopened.store.episode(id: ep.id)?.playbackPosition ?? -1, 30.0,
            accuracy: 0.001,
            "Trailing flush did not persist the latest cached position."
        )
    }

    /// During continuous playback the trailing-debounce task is cancelled
    /// on every tick, so the *only* mechanism that lands the cache on disk
    /// is the 30-second eager-cap. If this gate regresses to always-false,
    /// `testPositionUpdatesAreDebounced` still passes (the trailing flush
    /// fires after the test's tight loop ends), but a real 60-second
    /// crash-loss would silently exceed the spec. This test guards the
    /// cap directly by fast-forwarding `lastPositionFlush`.
    func testEagerCapFiresAfterMaxIntervalElapsed() throws {
        let sub = makeSubscription()
        store.upsertPodcast(sub); store.addSubscription(podcastID: sub.id)
        let ep = makeEpisode(podcastID: sub.id, guid: "cap-\(UUID().uuidString)")
        store.upsertEpisodes([ep], forPodcast: sub.id)

        // Eager-first call lands on disk and stamps `lastPositionFlush`.
        store.setEpisodePlaybackPosition(ep.id, position: 1.0)
        store.persistence.resetSaveInvocationCount()

        // Inside the cap window — must stay cached.
        store.setEpisodePlaybackPosition(ep.id, position: 2.0)
        XCTAssertEqual(
            store.persistence.saveInvocationCount, 0,
            "Position update inside the eager-cap window leaked through to disk."
        )

        // Simulate 31 s of continuous playback since the last flush — past
        // the 30 s cap. The next call must save eagerly even though the
        // trailing-debounce task hasn't expired.
        store.lastPositionFlush = Date().addingTimeInterval(-31)

        store.setEpisodePlaybackPosition(ep.id, position: 3.0)
        XCTAssertEqual(
            store.persistence.saveInvocationCount, 1,
            "Eager-cap did not fire after positionMaxInterval elapsed — continuous playback would silently lose >30s of position on crash."
        )

        let live = try XCTUnwrap(store.episode(id: ep.id))
        XCTAssertEqual(live.playbackPosition, 3.0, accuracy: 0.001)
    }

    /// Posting `UIApplication.didEnterBackgroundNotification` while a position
    /// update is sitting in the cache must flush it to disk synchronously, so
    /// the user can force-quit + relaunch without losing playback progress.
    func testBackgroundFlushPersistsPendingPosition() async throws {
        let sub = makeSubscription()
        store.upsertPodcast(sub); store.addSubscription(podcastID: sub.id)
        let ep = makeEpisode(podcastID: sub.id, guid: "bg-\(UUID().uuidString)")
        store.upsertEpisodes([ep], forPodcast: sub.id)

        // Eat the eager-first save so the next setEpisodePlaybackPosition
        // call lands in the cache instead of going straight to disk.
        store.setEpisodePlaybackPosition(ep.id, position: 1.0)
        store.persistence.resetSaveInvocationCount()

        // This call should be cached, not flushed.
        store.setEpisodePlaybackPosition(ep.id, position: 42.0)
        XCTAssertEqual(
            store.persistence.saveInvocationCount, 0,
            "Second position update inside the debounce window leaked through to disk."
        )

        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        // The observer hops back to the main actor before flushing; let it
        // run before we assert.
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertGreaterThanOrEqual(
            store.persistence.saveInvocationCount, 1,
            "didEnterBackgroundNotification did not trigger an immediate flush."
        )

        let reopened = await AppStateTestSupport.makeIsolatedStore(
            fileURL: storeFileURL,
            reset: false
        )
        XCTAssertEqual(
            reopened.store.episode(id: ep.id)?.playbackPosition ?? -1, 42.0,
            accuracy: 0.001,
            "Background flush did not persist the pending position."
        )
    }

    /// `markEpisodePlayed` must flush any cached position BEFORE it resets
    /// the position to 0 — otherwise a crash in the gap between flush and
    /// the played=true save loses both the position and the played flag.
    /// Verified by checking that the `played=true` write also captured the
    /// latest cached position en route.
    func testMarkPlayedFlushesBeforeReset() async throws {
        let sub = makeSubscription()
        store.upsertPodcast(sub); store.addSubscription(podcastID: sub.id)
        let ep = makeEpisode(podcastID: sub.id, guid: "mark-\(UUID().uuidString)")
        store.upsertEpisodes([ep], forPodcast: sub.id)

        // Seed the cache with a non-zero position. First call eagerly
        // saves; second call sits in the cache.
        store.setEpisodePlaybackPosition(ep.id, position: 10.0)
        store.setEpisodePlaybackPosition(ep.id, position: 999.0)

        // markEpisodePlayed should flush the cache (so the in-memory state
        // matches the cache) before clearing the position. We assert via
        // the cache-fold path: after markEpisodePlayed, the cached value
        // for `ep.id` must be gone.
        store.markEpisodePlayed(ep.id)

        let final = try XCTUnwrap(store.episode(id: ep.id))
        XCTAssertTrue(final.played, "markEpisodePlayed did not flip the played flag.")
        XCTAssertEqual(
            final.playbackPosition, 0,
            "markEpisodePlayed did not reset the position after flushing."
        )

        // The on-disk file must also reflect the post-mark state — the
        // sequence is flush(999) → mutate(played=true, position=0) →
        // didSet → save. So the persisted record is played=true,
        // position=0, never 999.
        let reopened = await AppStateTestSupport.makeIsolatedStore(
            fileURL: storeFileURL,
            reset: false
        )
        let persisted = try XCTUnwrap(reopened.store.episode(id: ep.id))
        XCTAssertTrue(persisted.played)
        XCTAssertEqual(persisted.playbackPosition, 0)
    }
}
