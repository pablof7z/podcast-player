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

    var storeFileURL: URL!
    var store: AppStateStore!

    override func setUp() async throws {
        try await super.setUp()
        let made = AppStateTestSupport.makeIsolatedStore()
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
        store.upsertPodcast(sub)
        let inserted = store.addSubscription(podcastID: sub.id)

        XCTAssertTrue(inserted)
        XCTAssertEqual(store.state.subscriptions.count, initialCount + 1)
        XCTAssertEqual(store.podcast(id: sub.id)?.title, "Test Show")
    }

    func testAddSubscriptionRejectsDuplicateFeedURL() throws {
        // Use a UUID-unique URL so prior persisted state can't collide.
        let url = URL(string: "https://example.com/\(UUID().uuidString).xml")!

        let firstPodcast = makeSubscription(feedURL: url)
        store.upsertPodcast(firstPodcast)
        XCTAssertTrue(store.addSubscription(podcastID: firstPodcast.id))
        let countAfterFirst = store.state.subscriptions.count
        // A second call for the same podcast must NOT add another follow row.
        XCTAssertFalse(store.addSubscription(podcastID: firstPodcast.id))
        XCTAssertEqual(store.state.subscriptions.count, countAfterFirst)
    }

    func testRemoveSubscriptionAlsoRemovesItsEpisodes() throws {
        let sub = makeSubscription(title: "Drop Me \(UUID().uuidString)")
        store.upsertPodcast(sub)
        store.addSubscription(podcastID: sub.id)

        let ep1 = makeEpisode(podcastID: sub.id, guid: "drop-\(UUID().uuidString)")
        let ep2 = makeEpisode(podcastID: sub.id, guid: "drop-\(UUID().uuidString)")
        store.upsertEpisodes([ep1, ep2], forPodcast: sub.id)

        XCTAssertEqual(store.episodes(forPodcast: sub.id).count, 2)

        store.deletePodcast(podcastID: sub.id)

        XCTAssertFalse(store.state.subscriptions.contains { $0.podcastID == sub.id })
        XCTAssertTrue(store.episodes(forPodcast: sub.id).isEmpty)
    }

    func testSetSubscriptionNotificationsToggle() throws {
        let sub = makeSubscription()
        store.upsertPodcast(sub)
        store.addSubscription(podcastID: sub.id)

        store.setSubscriptionNotificationsEnabled(sub.id, enabled: false)
        XCTAssertEqual(store.subscription(podcastID: sub.id)?.notificationsEnabled, false)

        store.setSubscriptionNotificationsEnabled(sub.id, enabled: true)
        XCTAssertEqual(store.subscription(podcastID: sub.id)?.notificationsEnabled, true)
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
        let p1 = makeSubscription(title: "The Tim Ferriss Show")
        let p2 = makeSubscription(title: "Acquired")
        state.podcasts.append(contentsOf: [p1, p2])
        state.subscriptions.append(contentsOf: [
            PodcastSubscription(podcastID: p1.id),
            PodcastSubscription(podcastID: p2.id),
        ])

        let prompt = AgentPrompt.build(for: state)

        XCTAssertTrue(prompt.contains("## Subscriptions (2)"))
        XCTAssertTrue(prompt.contains("The Tim Ferriss Show"))
        XCTAssertTrue(prompt.contains("Acquired"))
    }

    func testAgentPromptIncludesInProgressEpisodes() {
        var state = AppState()
        let sub = makeSubscription(title: "Lex Fridman")
        state.podcasts.append(sub)
        state.subscriptions.append(PodcastSubscription(podcastID: sub.id))
        var ep = makeEpisode(podcastID: sub.id, guid: "ip-1")
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
        state.podcasts.append(sub)
        state.subscriptions.append(PodcastSubscription(podcastID: sub.id))
        var fresh = makeEpisode(podcastID: sub.id, guid: "fresh-1")
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
        state.podcasts.append(sub)
        state.subscriptions.append(PodcastSubscription(podcastID: sub.id))
        var old = makeEpisode(podcastID: sub.id, guid: "old-1")
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
        store.upsertPodcast(sub)
        XCTAssertTrue(store.addSubscription(podcastID: sub.id))

        // The production file must be byte-identical to the snapshot.
        let after = try? Data(contentsOf: productionURL)
        XCTAssertEqual(before, after, "Test mutation leaked into the shared App Group state file.")
    }

    // MARK: - Fixtures

    func makeSubscription(
        feedURL: URL = URL(string: "https://example.com/\(UUID().uuidString).xml")!,
        title: String = "Test Show"
    ) -> Podcast {
        Podcast(feedURL: feedURL, title: title)
    }

    func makeEpisode(
        podcastID: UUID,
        guid: String
    ) -> Episode {
        Episode(
            podcastID: podcastID,
            guid: guid,
            title: "Episode \(guid)",
            pubDate: Date(),
            enclosureURL: URL(string: "https://example.com/\(guid).mp3")!
        )
    }
}
