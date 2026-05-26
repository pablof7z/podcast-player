import XCTest
@testable import Podcastr

extension AppTests {

    // MARK: - Queue persistence

    func testQueueItemRoundTrips() throws {
        let episodeID = UUID()
        let item = QueueItem(
            episodeID: episodeID,
            startSeconds: 12.5,
            endSeconds: 300.0,
            label: "Intro"
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(QueueItem.self, from: data)

        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.episodeID, episodeID)
        XCTAssertEqual(decoded.startSeconds, 12.5)
        XCTAssertEqual(decoded.endSeconds, 300.0)
        XCTAssertEqual(decoded.label, "Intro")
    }

    func testQueueItemNilFieldsRoundTrip() throws {
        let item = QueueItem.episode(UUID())

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(QueueItem.self, from: data)

        XCTAssertEqual(decoded.id, item.id)
        XCTAssertNil(decoded.startSeconds)
        XCTAssertNil(decoded.endSeconds)
        XCTAssertNil(decoded.label)
    }

    func testAppStateDecodesLegacyJsonWithoutQueue() throws {
        // Simulate an on-disk AppState written before the queue field was added.
        let json = """
        {
          "podcasts": [],
          "episodes": [],
          "lastPlayedEpisodeID": null
        }
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(AppState.self, from: json)
        XCTAssertTrue(state.queue.isEmpty, "Missing 'queue' key should decode as empty array")
    }

    func testSetPersistedQueuePersistsItems() {
        XCTAssertTrue(store.state.queue.isEmpty)

        let ep1 = UUID()
        let ep2 = UUID()
        let items = [QueueItem.episode(ep1), QueueItem.episode(ep2)]

        store.setPersistedQueue(items)

        XCTAssertEqual(store.state.queue.map(\.episodeID), [ep1, ep2])
    }

    func testSetPersistedQueueSkipsWriteWhenUnchanged() {
        let items = [QueueItem.episode(UUID())]

        store.setPersistedQueue(items)
        let queueAfterFirst = store.state.queue

        // Calling with equal content must not alter the stored array.
        store.setPersistedQueue(items)

        XCTAssertEqual(store.state.queue, queueAfterFirst)
    }

    func testSetPersistedQueueUpdatesWhenContentChanges() {
        let ep1 = UUID()
        let ep2 = UUID()

        store.setPersistedQueue([QueueItem.episode(ep1)])
        XCTAssertEqual(store.state.queue.count, 1)

        store.setPersistedQueue([QueueItem.episode(ep1), QueueItem.episode(ep2)])
        XCTAssertEqual(store.state.queue.count, 2)
        XCTAssertEqual(store.state.queue.last?.episodeID, ep2)
    }

    func testQueueSurvivesAcrossStoreInstances() {
        let ep1 = UUID(), ep2 = UUID()
        let items = [QueueItem.episode(ep1), QueueItem.episode(ep2)]
        store.setPersistedQueue(items)

        // Open a second store at the same backing file (simulates app restart).
        let reopened = AppStateTestSupport.makeIsolatedStore(fileURL: storeFileURL, reset: false)
        XCTAssertEqual(
            reopened.store.state.queue.map(\.episodeID),
            [ep1, ep2],
            "queue must survive across store instances"
        )
    }
}
