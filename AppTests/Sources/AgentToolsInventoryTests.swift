import XCTest
@testable import Podcastr

/// Coverage for the four inventory-listing podcast agent tools added to
/// `AgentTools.dispatchPodcast`:
///
///   - `list_subscriptions`
///   - `list_episodes`
///   - `list_in_progress`
///   - `list_recent_unplayed`
///
/// These let the agent answer plain-English library questions ("what am I
/// subscribed to?", "what was I listening to?") without spending a search
/// or RAG call. Tests verify dispatch routing, default + capped limits,
/// missing-arg validation, and JSON shape.
@MainActor
final class AgentToolsInventoryTests: XCTestCase {

    // MARK: - list_subscriptions

    func testListSubscriptionsDispatchesAndReturnsAllRows() async throws {
        let inventory = MockInventory()
        await inventory.setSubscriptions([
            sampleSubscription(id: "p1", title: "Acquired"),
            sampleSubscription(id: "p2", title: "The Daily"),
        ])

        let result = await dispatch(name: "list_subscriptions", args: [:], inventory: inventory)

        let json = try unwrapJSON(result)
        XCTAssertEqual(json["success"] as? Bool, true)
        let rows = json["subscriptions"] as? [[String: Any]] ?? []
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?["title"] as? String, "Acquired")
        XCTAssertEqual(rows.first?["total_episodes"] as? Int, 100)
        XCTAssertEqual(rows.first?["unplayed_episodes"] as? Int, 5)
    }

    func testListSubscriptionsRespectsLimitArg() async throws {
        let inventory = MockInventory()
        await inventory.setSubscriptions((0..<10).map { sampleSubscription(id: "p\($0)", title: "Show \($0)") })

        _ = await dispatch(name: "list_subscriptions", args: ["limit": 3], inventory: inventory)

        let lastLimit = await inventory.lastListSubscriptionsLimit
        XCTAssertEqual(lastLimit, 3)
    }

    func testListSubscriptionsClampsLimitToCap() async throws {
        let inventory = MockInventory()

        _ = await dispatch(name: "list_subscriptions", args: ["limit": 999], inventory: inventory)

        // Capped at 100 (see AgentTools+Podcast inventoryMaxLimit).
        let lastLimit = await inventory.lastListSubscriptionsLimit
        XCTAssertEqual(lastLimit, 100)
    }

    func testListSubscriptionsDefaultsLimitWhenAbsent() async throws {
        let inventory = MockInventory()

        _ = await dispatch(name: "list_subscriptions", args: [:], inventory: inventory)

        let lastLimit = await inventory.lastListSubscriptionsLimit
        XCTAssertEqual(lastLimit, 25)
    }

    // MARK: - list_episodes

    func testListEpisodesRequiresPodcastID() async throws {
        let result = await dispatch(name: "list_episodes", args: [:], inventory: MockInventory())
        let json = try unwrapJSON(result)
        XCTAssertNotNil(json["error"])
    }

    func testListEpisodesReturnsErrorForUnknownPodcast() async throws {
        let result = await dispatch(name: "list_episodes", args: ["podcast_id": "nope"], inventory: MockInventory())
        let json = try unwrapJSON(result)
        let err = json["error"] as? String ?? ""
        XCTAssertTrue(err.contains("Unknown podcast"))
    }

    func testListEpisodesReturnsEpisodeStateFields() async throws {
        let inventory = MockInventory()
        await inventory.setEpisodes([
            sampleEpisode(id: "e1", podcast: "p1", played: false, position: 0),
            sampleEpisode(id: "e2", podcast: "p1", played: true, position: 0),
            sampleEpisode(id: "e3", podcast: "p1", played: false, position: 1234),
        ], forPodcast: "p1")

        let result = await dispatch(name: "list_episodes", args: ["podcast_id": "p1"], inventory: inventory)

        let json = try unwrapJSON(result)
        XCTAssertEqual(json["success"] as? Bool, true)
        let rows = json["episodes"] as? [[String: Any]] ?? []
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0]["played"] as? Bool, false)
        XCTAssertEqual(rows[1]["played"] as? Bool, true)
        XCTAssertEqual(rows[2]["is_in_progress"] as? Bool, true)
        XCTAssertEqual(rows[2]["playback_position_seconds"] as? Double, 1234)
    }

    // MARK: - list_in_progress

    func testListInProgressDispatchesWithDefaultLimit() async throws {
        let inventory = MockInventory()
        await inventory.setInProgress([
            sampleEpisode(id: "e1", podcast: "p1", played: false, position: 600),
        ])

        let result = await dispatch(name: "list_in_progress", args: [:], inventory: inventory)

        let json = try unwrapJSON(result)
        XCTAssertEqual(json["success"] as? Bool, true)
        let rows = json["episodes"] as? [[String: Any]] ?? []
        XCTAssertEqual(rows.count, 1)
        let lastLimit = await inventory.lastInProgressLimit
        XCTAssertEqual(lastLimit, 25)
    }

    // MARK: - list_recent_unplayed

    func testListRecentUnplayedDispatches() async throws {
        let inventory = MockInventory()
        await inventory.setRecentUnplayed([
            sampleEpisode(id: "e1", podcast: "p1", played: false, position: 0),
            sampleEpisode(id: "e2", podcast: "p1", played: false, position: 0),
        ])

        let result = await dispatch(name: "list_recent_unplayed", args: ["limit": 5], inventory: inventory)

        let json = try unwrapJSON(result)
        XCTAssertEqual(json["success"] as? Bool, true)
        let rows = json["episodes"] as? [[String: Any]] ?? []
        XCTAssertEqual(rows.count, 2)
        let lastLimit = await inventory.lastRecentUnplayedLimit
        XCTAssertEqual(lastLimit, 5)
    }

    // MARK: - Schema includes the new tools

    func testSchemaExposesAllFourInventoryTools() {
        let names = AgentTools.podcastSchema
            .compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        XCTAssertTrue(names.contains("list_subscriptions"))
        XCTAssertTrue(names.contains("list_episodes"))
        XCTAssertTrue(names.contains("list_in_progress"))
        XCTAssertTrue(names.contains("list_recent_unplayed"))
    }

    func testPodcastNamesAllIncludesInventoryTools() {
        let all = AgentTools.PodcastNames.all
        XCTAssertTrue(all.contains("list_subscriptions"))
        XCTAssertTrue(all.contains("list_episodes"))
        XCTAssertTrue(all.contains("list_in_progress"))
        XCTAssertTrue(all.contains("list_recent_unplayed"))
    }

    // MARK: - Helpers

    private func dispatch(
        name: String,
        args: [String: Any],
        inventory: MockInventory
    ) async -> String {
        let deps = PodcastAgentToolDeps(
            rag: MockRAG(),
            wiki: MockWiki(),
            briefing: MockBriefing(),
            summarizer: MockSummarizer(),
            fetcher: MockFetcher(),
            playback: MockPlayback(),
            library: MockLibrary(),
            inventory: inventory,
            delegation: MockDelegation(),
            perplexity: MockPerplexity()
        )
        // Round-trip through the JSON-string dispatcher so we don't have to
        // hand a non-Sendable `[String: Any]` across isolation boundaries.
        let argsJSON: String
        if args.isEmpty {
            argsJSON = "{}"
        } else {
            let data = (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8)
            argsJSON = String(data: data, encoding: .utf8) ?? "{}"
        }
        return await AgentTools.dispatchPodcast(name: name, argsJSON: argsJSON, deps: deps)
    }

    private func unwrapJSON(_ result: String) throws -> [String: Any] {
        let data = try XCTUnwrap(result.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sampleSubscription(id: String, title: String) -> SubscriptionSummary {
        SubscriptionSummary(
            podcastID: id,
            title: title,
            author: "Test Author",
            totalEpisodes: 100,
            unplayedEpisodes: 5,
            lastPublishedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func sampleEpisode(
        id: String,
        podcast: String,
        played: Bool,
        position: Double
    ) -> EpisodeInventoryRow {
        EpisodeInventoryRow(
            episodeID: id,
            podcastID: podcast,
            title: "Episode \(id)",
            podcastTitle: "Show \(podcast)",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 1800,
            played: played,
            playbackPositionSeconds: position,
            isInProgress: !played && position > 0
        )
    }
}
