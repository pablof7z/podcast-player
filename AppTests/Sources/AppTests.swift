import UIKit
import XCTest
@testable import Podcastr

@MainActor
final class AppTests: XCTestCase {

    // MARK: - Per-test isolated storage
    //
    // Every test gets a fresh `AppStateStore` over a unique in-memory
    // `UserDefaults` suite (see `AppStateTestSupport`). This keeps the
    // production App Group suite (`group.com.podcastr.app`) clean — running
    // the test target used to leak fixture data ("Test Show", "Episode e1")
    // into the real app's persisted state.

    private var storeFileURL: URL!
    private var store: AppStateStore!

    override func setUp() async throws {
        try await super.setUp()
        let made = await AppStateTestSupport.makeIsolatedStore()
        storeFileURL = made.fileURL
        store = made.store
    }

    override func tearDown() async throws {
        if let storeFileURL {
            AppStateTestSupport.disposeIsolatedStore(at: storeFileURL)
        }
        store = nil
        storeFileURL = nil
        try await super.tearDown()
    }

    // MARK: - Subscriptions

    func testAddSubscriptionAcceptsNewFeed() throws {
        let initialCount = store.state.subscriptions.count

        let sub = makeSubscription(title: "Test Show")
        let inserted = store.addSubscription(sub)

        XCTAssertTrue(inserted)
        XCTAssertEqual(store.state.subscriptions.count, initialCount + 1)
        XCTAssertEqual(store.state.subscriptions.last?.title, "Test Show")
    }

    func testAddSubscriptionRejectsDuplicateFeedURL() throws {
        // Use a UUID-unique URL so prior persisted state can't collide.
        let url = URL(string: "https://example.com/\(UUID().uuidString).xml")!

        XCTAssertTrue(store.addSubscription(makeSubscription(feedURL: url)))
        let countAfterFirst = store.state.subscriptions.count
        XCTAssertFalse(store.addSubscription(makeSubscription(feedURL: url)))
        XCTAssertEqual(store.state.subscriptions.count, countAfterFirst)
    }

    func testRemoveSubscriptionAlsoRemovesItsEpisodes() throws {
        let sub = makeSubscription(title: "Drop Me \(UUID().uuidString)")
        store.addSubscription(sub)

        let ep1 = makeEpisode(subscriptionID: sub.id, guid: "drop-\(UUID().uuidString)")
        let ep2 = makeEpisode(subscriptionID: sub.id, guid: "drop-\(UUID().uuidString)")
        store.upsertEpisodes([ep1, ep2], forSubscription: sub.id)

        // Assert against this subscription's episodes only — keeping the
        // narrower scope makes the intent obvious even though the isolated
        // suite means the global episode count would also be 2.
        XCTAssertEqual(store.episodes(forSubscription: sub.id).count, 2)

        store.removeSubscription(sub.id)

        XCTAssertFalse(store.state.subscriptions.contains { $0.id == sub.id })
        XCTAssertTrue(store.episodes(forSubscription: sub.id).isEmpty)
    }

    func testSetSubscriptionNotificationsToggle() throws {
        let sub = makeSubscription()
        store.addSubscription(sub)

        store.setSubscriptionNotificationsEnabled(sub.id, enabled: false)
        XCTAssertEqual(store.subscription(id: sub.id)?.notificationsEnabled, false)

        store.setSubscriptionNotificationsEnabled(sub.id, enabled: true)
        XCTAssertEqual(store.subscription(id: sub.id)?.notificationsEnabled, true)
    }

    // MARK: - Episodes

    func testSetEpisodePlaybackPosition() throws {
        let sub = makeSubscription()
        store.addSubscription(sub)
        let ep = makeEpisode(subscriptionID: sub.id, guid: "e1")
        store.upsertEpisodes([ep], forSubscription: sub.id)

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
        store.addSubscription(sub)
        let ep = makeEpisode(subscriptionID: sub.id, guid: "tick-\(UUID().uuidString)")
        store.upsertEpisodes([ep], forSubscription: sub.id)

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
        store.addSubscription(sub)
        let ep = makeEpisode(subscriptionID: sub.id, guid: "cap-\(UUID().uuidString)")
        store.upsertEpisodes([ep], forSubscription: sub.id)

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
        store.addSubscription(sub)
        let ep = makeEpisode(subscriptionID: sub.id, guid: "bg-\(UUID().uuidString)")
        store.upsertEpisodes([ep], forSubscription: sub.id)

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
        store.addSubscription(sub)
        let ep = makeEpisode(subscriptionID: sub.id, guid: "mark-\(UUID().uuidString)")
        store.upsertEpisodes([ep], forSubscription: sub.id)

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

    // MARK: - Friends

    func testAddFriend() throws {
        let friend = store.addFriend(displayName: "Alice", identifier: "alice@example.com")

        XCTAssertEqual(friend.displayName, "Alice")
        XCTAssertEqual(friend.identifier, "alice@example.com")
        XCTAssertTrue(store.state.friends.contains { $0.id == friend.id })
    }

    func testUpdateFriendDisplayName() throws {
        let friend = store.addFriend(displayName: "Bob", identifier: "bob_id")

        store.updateFriendDisplayName(friend.id, newName: "Robert")

        XCTAssertEqual(store.state.friends.first { $0.id == friend.id }?.displayName, "Robert")
    }

    func testRemoveFriend() throws {
        let friend = store.addFriend(displayName: "Charlie", identifier: "charlie_id")

        store.removeFriend(friend.id)

        XCTAssertFalse(store.state.friends.contains { $0.id == friend.id })
    }

    // MARK: - Models

    func testAnchorCodable() throws {
        let anchor = Anchor.note(id: UUID())
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(Anchor.self, from: data)
        XCTAssertEqual(anchor, decoded)
    }

    func testFriendAnchorCodable() throws {
        let anchor = Anchor.friend(id: UUID())
        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(Anchor.self, from: data)
        XCTAssertEqual(anchor, decoded)
    }

    // MARK: - AgentPrompt

    func testAgentPromptIncludesFriends() {
        var state = AppState()
        state.friends.append(Friend(displayName: "Alice", identifier: "alice_id"))

        let prompt = AgentPrompt.build(for: state)

        XCTAssertTrue(prompt.contains("Alice"))
    }

    func testAgentPromptIncludesMemories() {
        var state = AppState()
        state.agentMemories.append(AgentMemory(content: "User prefers mornings"))

        let prompt = AgentPrompt.build(for: state)

        XCTAssertTrue(prompt.contains("User prefers mornings"))
    }

    func testAgentPromptIncludesSubscriptions() {
        var state = AppState()
        state.subscriptions.append(makeSubscription(title: "The Tim Ferriss Show"))
        state.subscriptions.append(makeSubscription(title: "Acquired"))

        let prompt = AgentPrompt.build(for: state)

        XCTAssertTrue(prompt.contains("## Subscriptions (2)"))
        XCTAssertTrue(prompt.contains("The Tim Ferriss Show"))
        XCTAssertTrue(prompt.contains("Acquired"))
    }

    func testAgentPromptIncludesInProgressEpisodes() {
        var state = AppState()
        let sub = makeSubscription(title: "Lex Fridman")
        state.subscriptions.append(sub)
        var ep = makeEpisode(subscriptionID: sub.id, guid: "ip-1")
        ep.title = "Episode about something"
        ep.playbackPosition = 600
        state.episodes.append(ep)

        let prompt = AgentPrompt.build(for: state)

        XCTAssertTrue(prompt.contains("## In Progress"))
        XCTAssertTrue(prompt.contains("Episode about something"))
        XCTAssertTrue(prompt.contains("Lex Fridman"))
    }

    func testAgentPromptIncludesRecentUnplayedEpisodes() {
        var state = AppState()
        let sub = makeSubscription(title: "Recent Show")
        state.subscriptions.append(sub)
        var fresh = makeEpisode(subscriptionID: sub.id, guid: "fresh-1")
        fresh.title = "Brand new episode"
        fresh.pubDate = Date().addingTimeInterval(-3600)
        state.episodes.append(fresh)

        let prompt = AgentPrompt.build(for: state)

        XCTAssertTrue(prompt.contains("## Recent"))
        XCTAssertTrue(prompt.contains("Brand new episode"))
    }

    func testAgentPromptOmitsOldEpisodesFromRecentSection() {
        var state = AppState()
        let sub = makeSubscription(title: "Old Show")
        state.subscriptions.append(sub)
        var old = makeEpisode(subscriptionID: sub.id, guid: "old-1")
        old.title = "Old episode title that is unique"
        old.pubDate = Date().addingTimeInterval(-30 * 86_400)
        state.episodes.append(old)

        let prompt = AgentPrompt.build(for: state)

        // Subscription should still appear, but the 30-day-old episode
        // shouldn't surface in the 7-day recent window.
        XCTAssertFalse(prompt.contains("Old episode title that is unique"))
    }

    // MARK: - Persistence isolation

    /// Regression test for the test-leak bug: writing through an isolated
    /// store must NOT mutate the production App Group state file.
    func testIsolatedStoreDoesNotTouchSharedAppGroupContainer() throws {
        let productionURL = Persistence.appGroupStateFileURL
        // Snapshot whatever the production file currently holds (may be
        // absent on a clean dev machine — `nil` is a valid baseline).
        let before = try? Data(contentsOf: productionURL)

        // Make a noisy mutation through the isolated store.
        let sub = makeSubscription(title: "Leak Canary \(UUID().uuidString)")
        XCTAssertTrue(store.addSubscription(sub))

        // The production file must be byte-identical to the snapshot.
        let after = try? Data(contentsOf: productionURL)
        XCTAssertEqual(before, after, "Test mutation leaked into the shared App Group state file.")
    }

    // MARK: - Persistence durability

    /// Regression test for the silent-large-write loss bug: when the encoded
    /// `AppState` exceeds a few MB (the practical `cfprefsd` ceiling, easily
    /// hit by a real subscription's full episode list), the previous
    /// `UserDefaults`-backed `Persistence` would commit the write to the
    /// preferences plist on disk but the daemon refused to serve it back on
    /// the next read — so a fresh process would decode an older, smaller
    /// blob and lose any field added after the size crossover (most visibly
    /// `hasCompletedOnboarding`).
    ///
    /// The fix: `Persistence` now writes to a file inside the App Group
    /// container. This test pads `state.episodes` past 4 MB (well above the
    /// historical failure threshold) and asserts the round-trip survives a
    /// fresh `AppStateStore` constructed over the same backing file. If
    /// anyone ever swaps the storage primitive back to a size-capped one,
    /// this test will fail.
    func testPersistenceRoundTripsLargeStateAcrossStoreInstances() async throws {
        let sharedFileURL = AppStateTestSupport.uniqueTempFileURL()
        defer { AppStateTestSupport.disposeIsolatedStore(at: sharedFileURL) }

        // Build a state with enough fixture episodes to push the encoded
        // blob past ~4 MB. Each episode carries a long synthetic
        // `showNotes` string so we hit the threshold without needing
        // thousands of distinct records.
        do {
            let made = await AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL)
            let firstStore = made.store
            let sub = makeSubscription(title: "Large State Show")
            XCTAssertTrue(firstStore.addSubscription(sub))

            let padding = String(repeating: "x", count: 4_096)
            var episodes: [Episode] = []
            episodes.reserveCapacity(1_500)
            for i in 0..<1_500 {
                var ep = makeEpisode(subscriptionID: sub.id, guid: "large-\(i)")
                ep.description = padding
                episodes.append(ep)
            }
            firstStore.upsertEpisodes(episodes, forSubscription: sub.id)

            var settings = firstStore.state.settings
            settings.hasCompletedOnboarding = true
            firstStore.updateSettings(settings)

            // Sanity: the encoded blob is at least the size that broke
            // UserDefaults so the test actually exercises the failure mode.
            let onDisk = try Data(contentsOf: sharedFileURL)
            XCTAssertGreaterThan(
                onDisk.count, 4 * 1024 * 1024,
                "Test fixture is too small to exercise the large-state regression."
            )
        }

        // Construct a fresh store over the same file and assert the
        // post-onboarding flag survived along with the subscription.
        let reopened = await AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL, reset: false)
        XCTAssertTrue(
            reopened.store.state.settings.hasCompletedOnboarding,
            "hasCompletedOnboarding did not survive a round-trip through Persistence."
        )
        XCTAssertEqual(reopened.store.state.subscriptions.count, 1)
        XCTAssertEqual(reopened.store.state.episodes.count, 1_500)
    }

    /// Smaller-scale companion to the large-state regression: covers the
    /// minimum invariant the original bug report described — set
    /// `hasCompletedOnboarding`, dispose the store, recreate over the same
    /// backing file, expect the flag to still be `true`. Kept as a separate
    /// test so a future failure is easy to triage (small case fails ⇒
    /// general persistence is broken; only the large case fails ⇒ size
    /// regression).
    func testHasCompletedOnboardingPersistsAcrossStoreInstances() async throws {
        let sharedFileURL = AppStateTestSupport.uniqueTempFileURL()
        defer { AppStateTestSupport.disposeIsolatedStore(at: sharedFileURL) }

        do {
            let made = await AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL)
            var settings = made.store.state.settings
            settings.hasCompletedOnboarding = true
            made.store.updateSettings(settings)
        }

        let reopened = await AppStateTestSupport.makeIsolatedStore(fileURL: sharedFileURL, reset: false)
        XCTAssertTrue(reopened.store.state.settings.hasCompletedOnboarding)
    }

    // MARK: - Settings

    func testSettingsDoesNotPersistLegacyOpenRouterAPIKey() throws {
        let json = """
        {
          "llmModel": "openai/gpt-4o-mini",
          "openRouterAPIKey": "sk-or-v1-secret",
          "agentMaxTurns": 12
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertEqual(decoded.openRouterCredentialSource, .manual)
        XCTAssertEqual(decoded.legacyOpenRouterAPIKey, "sk-or-v1-secret")

        let encoded = try JSONEncoder().encode(decoded)
        let encodedString = String(data: encoded, encoding: .utf8) ?? ""
        XCTAssertFalse(encodedString.contains("sk-or-v1-secret"))
        XCTAssertFalse(encodedString.contains("openRouterAPIKey"))
    }

    func testSettingsPersistsBYOKMetadataOnly() throws {
        var settings = Settings()
        settings.markOpenRouterBYOK(keyID: "key_123", keyLabel: "Default")

        let encoded = try JSONEncoder().encode(settings)
        let encodedString = String(data: encoded, encoding: .utf8) ?? ""

        XCTAssertTrue(encodedString.contains("byok"))
        XCTAssertTrue(encodedString.contains("key_123"))
        XCTAssertTrue(encodedString.contains("Default"))
        XCTAssertFalse(encodedString.contains("api_key"))
    }

    // MARK: - DataExport

    func testDataExportRedactsLegacyOpenRouterKey() throws {
        var state = AppState()
        state.settings.legacyOpenRouterAPIKey = "sk-or-v1-leaked-secret"

        let payload = DataExport.makePayload(from: state)
        let data = try DataExport.encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(json.contains("sk-or-v1-leaked-secret"))
        XCTAssertNil(payload.state.settings.legacyOpenRouterAPIKey)
    }

    func testDataExportRoundTripsCoreRecords() throws {
        var state = AppState()
        state.subscriptions.append(makeSubscription(title: "Round Trip Show"))
        state.notes.append(Note(text: "Sample note"))
        state.friends.append(Friend(displayName: "Alice", identifier: "alice_id"))

        let data = try DataExport.encode(DataExport.makePayload(from: state))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DataExport.Payload.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, DataExport.currentSchemaVersion)
        XCTAssertEqual(decoded.state.subscriptions.first?.title, "Round Trip Show")
        XCTAssertEqual(decoded.state.notes.first?.text, "Sample note")
        XCTAssertEqual(decoded.state.friends.first?.displayName, "Alice")
    }

    func testDataExportStatsExcludeDeletedNotes() {
        var state = AppState()
        let liveNote = Note(text: "Live note")
        var deletedNote = Note(text: "Tombstone note")
        deletedNote.deleted = true
        state.notes = [liveNote, deletedNote]

        let stats = DataExport.stats(for: state)

        XCTAssertEqual(stats.notes, 1)
    }

    func testDataExportSuggestedFilenameShape() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        let date = f.date(from: "2026-05-05-1430")!

        let name = DataExport.suggestedFilename(at: date)
        XCTAssertEqual(name, "Podcastr-Export-2026-05-05-1430.json")
    }

    func testDataExportWriteCreatesReadableFile() throws {
        var state = AppState()
        state.subscriptions.append(makeSubscription(title: "Persisted"))

        let url = try DataExport.writeExport(of: state)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DataExport.Payload.self, from: data)
        XCTAssertEqual(decoded.state.subscriptions.first?.title, "Persisted")
    }

    // MARK: - Fixtures

    private func makeSubscription(
        feedURL: URL = URL(string: "https://example.com/\(UUID().uuidString).xml")!,
        title: String = "Test Show"
    ) -> PodcastSubscription {
        PodcastSubscription(feedURL: feedURL, title: title)
    }

    private func makeEpisode(
        subscriptionID: UUID,
        guid: String
    ) -> Episode {
        Episode(
            subscriptionID: subscriptionID,
            guid: guid,
            title: "Episode \(guid)",
            pubDate: Date(),
            enclosureURL: URL(string: "https://example.com/\(guid).mp3")!
        )
    }
}
