import XCTest
@testable import Podcastr

/// Lane-10 tests. Drive `AgentTools.dispatchPodcast` against mock deps and
/// verify (a) schema validation rejects bad arguments cleanly and (b) the
/// dispatch path forwards to the right protocol method with the right values.
@MainActor
final class AgentToolsPodcastTests: XCTestCase {

    // MARK: - Schema sanity

    func testPodcastSchemaListsEveryNonSkillToolName() {
        let names = Set(AgentTools.podcastSchema.compactMap { tool -> String? in
            (tool["function"] as? [String: Any])?["name"] as? String
        })
        // Skill-gated tool names live in `PodcastNames.all` (so `dispatch` can
        // route them) but their schemas are owned by the skill, not by
        // `podcastSchema`. Subtract them before comparing.
        let expected = Set(AgentTools.PodcastNames.all)
            .subtracting(AgentSkillRegistry.allToolNames)
        XCTAssertEqual(names, expected, "podcastSchema must cover every non-skill-gated podcast tool")
    }

    func testPodcastSchemaEntriesHaveRequiredOpenAIShape() {
        for entry in AgentTools.podcastSchema {
            XCTAssertEqual(entry["type"] as? String, "function")
            let function = entry["function"] as? [String: Any]
            XCTAssertNotNil(function?["name"] as? String)
            XCTAssertNotNil(function?["description"] as? String)
            let params = function?["parameters"] as? [String: Any]
            XCTAssertEqual(params?["type"] as? String, "object")
            XCTAssertNotNil(params?["properties"] as? [String: Any])
            XCTAssertNotNil(params?["required"] as? [String])
        }
    }

    // MARK: - play_episode_at

    func testPlayEpisodeAtSuccess() async throws {
        let deps = makeDeps(fetcher: MockFetcher(known: ["ep1"]))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.playEpisodeAt,
            args: ["episode_id": "ep1", "timestamp": 47.5],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertEqual(decoded["success"] as? Bool, true)
        XCTAssertEqual(decoded["episode_id"] as? String, "ep1")
        XCTAssertEqual(decoded["timestamp"] as? Double, 47.5)
        let calls = await deps.playback.recordedPlays
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, "ep1")
        XCTAssertEqual(calls.first?.1, 47.5)
    }

    func testPlayEpisodeAtRejectsMissingEpisodeID() async throws {
        let deps = makeDeps()
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.playEpisodeAt,
            args: ["timestamp": 0],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertNotNil(decoded["error"])
    }

    func testPlayEpisodeAtRejectsUnknownEpisode() async throws {
        let deps = makeDeps(fetcher: MockFetcher(known: []))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.playEpisodeAt,
            args: ["episode_id": "does-not-exist", "timestamp": 0],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertNotNil(decoded["error"])
    }

    func testPlayEpisodeAtRejectsNegativeTimestamp() async throws {
        let deps = makeDeps(fetcher: MockFetcher(known: ["ep1"]))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.playEpisodeAt,
            args: ["episode_id": "ep1", "timestamp": -3],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertNotNil(decoded["error"])
    }

    // MARK: - search_episodes

    func testSearchEpisodesReturnsRows() async throws {
        let hits = [
            EpisodeHit(episodeID: "ep1", podcastID: "pod1", title: "Zone 2 Conversation", podcastTitle: "Tim Ferriss", score: 0.91),
            EpisodeHit(episodeID: "ep2", podcastID: "pod2", title: "VO2 Max", podcastTitle: "Huberman", score: 0.78),
        ]
        let deps = makeDeps(rag: MockRAG(searchEpisodesResult: hits))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.searchEpisodes,
            args: ["query": "zone 2", "limit": 5],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertEqual(decoded["success"] as? Bool, true)
        XCTAssertEqual(decoded["total_found"] as? Int, 2)
        let rows = decoded["results"] as? [[String: Any]]
        XCTAssertEqual(rows?.count, 2)
        XCTAssertEqual(rows?.first?["episode_id"] as? String, "ep1")
        XCTAssertEqual(rows?.first?["score"] as? Double, 0.91)
    }

    func testSearchEpisodesClampsLimitAboveMax() async throws {
        let mockRAG = MockRAG()
        let deps = makeDeps(rag: mockRAG)
        _ = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.searchEpisodes,
            args: ["query": "anything", "limit": 9_999],
            deps: deps.bundle
        )
        let lastLimit = await mockRAG.lastSearchLimit
        XCTAssertEqual(lastLimit, AgentTools.podcastSearchMaxLimit)
    }

    func testSearchEpisodesRequiresQuery() async throws {
        let deps = makeDeps()
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.searchEpisodes,
            args: ["query": "  "],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertNotNil(decoded["error"])
    }

    // MARK: - query_wiki

    func testQueryWikiReturnsExcerpts() async throws {
        let deps = makeDeps(wiki: MockWiki(result: [
            WikiHit(pageID: "zone-2", title: "Zone 2 Training", excerpt: "Sustained effort below..."),
        ]))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.queryWiki,
            args: ["topic": "Zone 2"],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertEqual(decoded["success"] as? Bool, true)
        XCTAssertEqual(decoded["total_found"] as? Int, 1)
        let rows = decoded["results"] as? [[String: Any]]
        XCTAssertEqual(rows?.first?["page_id"] as? String, "zone-2")
    }

    func testLiveWikiStorageAdapterSearchesClaimBodies() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-agent-search-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let storage = WikiStorage(root: tmp)
        let page = WikiPage(
            slug: "metabolic-health",
            title: "Metabolic Health",
            kind: .topic,
            scope: .global,
            summary: "A broad page about nutrition.",
            sections: [
                WikiSection(
                    heading: "Claims",
                    kind: .definition,
                    ordinal: 0,
                    claims: [
                        WikiClaim(text: "Keto diet discussion focused on appetite and insulin sensitivity.")
                    ]
                )
            ]
        )
        try storage.write(page)

        let hits = try await LiveWikiStorageAdapter(storage: storage)
            .queryWiki(topic: "keto diet", scope: nil, limit: 5)

        XCTAssertEqual(hits.first?.title, "Metabolic Health")
        XCTAssertTrue(hits.first?.excerpt.lowercased().contains("keto diet") == true)
        XCTAssertGreaterThan(hits.first?.score ?? 0, 0)
    }

    // MARK: - query_transcripts

    func testQueryTranscriptsReturnsChunksWithTimestamps() async throws {
        let deps = makeDeps(rag: MockRAG(transcriptsResult: [
            TranscriptHit(episodeID: "ep1", startSeconds: 47.0, endSeconds: 60.0, speaker: "Tim", text: "Zone 2 is sustained..."),
        ]))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.queryTranscripts,
            args: ["query": "zone 2", "scope": "ep1"],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        let rows = decoded["results"] as? [[String: Any]]
        XCTAssertEqual(rows?.count, 1)
        XCTAssertEqual(rows?.first?["speaker"] as? String, "Tim")
        XCTAssertEqual(rows?.first?["start_seconds"] as? Double, 47.0)
    }

    // MARK: - generate_briefing

    func testGenerateBriefingClampsLengthRange() async throws {
        let mockBriefing = MockBriefing(result: BriefingResult(
            briefingID: "b1", title: "This Week", estimatedSeconds: 720, episodeIDs: ["ep1"]
        ))
        let deps = makeDeps(briefing: mockBriefing)
        _ = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.generateBriefing,
            args: ["scope": "this_week", "length": 9999],
            deps: deps.bundle
        )
        let lastLength = await mockBriefing.lastLength
        XCTAssertEqual(lastLength, AgentTools.briefingMaxLengthMinutes)
    }

    func testGenerateBriefingReturnsHandle() async throws {
        let deps = makeDeps(briefing: MockBriefing(result: BriefingResult(
            briefingID: "b1", title: "This Week", estimatedSeconds: 720, episodeIDs: ["ep1", "ep2"]
        )))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.generateBriefing,
            args: ["scope": "this_week", "length": 12, "style": "news"],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertEqual(decoded["briefing_id"] as? String, "b1")
        XCTAssertEqual(decoded["estimated_seconds"] as? Int, 720)
        XCTAssertEqual(decoded["style"] as? String, "news")
    }

    func testGenerateBriefingRequiresScope() async throws {
        let deps = makeDeps()
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.generateBriefing,
            args: ["length": 10],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertNotNil(decoded["error"])
    }

    // MARK: - perplexity_search

    func testPerplexitySearchPropagatesAnswerAndSources() async throws {
        let deps = makeDeps(perplexity: MockPerplexity(result: PerplexityResult(
            answer: "It rained.",
            sources: [.init(title: "weather.com", url: "https://weather.com/x")]
        )))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.perplexitySearch,
            args: ["query": "did it rain in Tokyo yesterday?"],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertEqual(decoded["answer"] as? String, "It rained.")
        let sources = decoded["sources"] as? [[String: Any]]
        XCTAssertEqual(sources?.first?["url"] as? String, "https://weather.com/x")
    }

    func testPerplexitySearchSurfacesError() async throws {
        let deps = makeDeps(perplexity: MockPerplexity(error: PerplexityClientError.missingAPIKey))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.perplexitySearch,
            args: ["query": "anything"],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertNotNil(decoded["error"])
    }

    // MARK: - summarize_episode

    func testSummarizeEpisodeSuccess() async throws {
        let deps = makeDeps(
            summarizer: MockSummarizer(result: EpisodeSummary(
                episodeID: "ep1", summary: "Quick TLDR.", bulletPoints: ["A", "B"]
            )),
            fetcher: MockFetcher(known: ["ep1"])
        )
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.summarizeEpisode,
            args: ["episode_id": "ep1", "length": "short"],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertEqual(decoded["summary"] as? String, "Quick TLDR.")
        XCTAssertEqual(decoded["length"] as? String, "short")
        XCTAssertEqual((decoded["bullets"] as? [String])?.count, 2)
    }

    // MARK: - find_similar_episodes

    func testFindSimilarEpisodesUsesK() async throws {
        let mockRAG = MockRAG(similarResult: [
            EpisodeHit(episodeID: "ep2", podcastID: "pod1", title: "Sequel", podcastTitle: "Tim Ferriss"),
        ])
        let deps = makeDeps(rag: mockRAG, fetcher: MockFetcher(known: ["seed"]))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.findSimilarEpisodes,
            args: ["seed_episode_id": "seed", "k": 7],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertEqual(decoded["k"] as? Int, 7)
        let kSeen = await mockRAG.lastSimilarK
        XCTAssertEqual(kSeen, 7)
    }

    func testFindSimilarEpisodesRejectsUnknownSeed() async throws {
        let deps = makeDeps(fetcher: MockFetcher(known: []))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.findSimilarEpisodes,
            args: ["seed_episode_id": "ghost"],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertNotNil(decoded["error"])
    }

    // MARK: - open_screen

    func testOpenScreenForwardsRoute() async throws {
        let deps = makeDeps()
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.openScreen,
            args: ["route": "library"],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertEqual(decoded["route"] as? String, "library")
        let routes = await deps.playback.recordedRoutes
        XCTAssertEqual(routes, ["library"])
    }

    func testOpenScreenRejectsEmptyRoute() async throws {
        let deps = makeDeps()
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.openScreen,
            args: ["route": ""],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertNotNil(decoded["error"])
    }

    // MARK: - set_now_playing

    func testSetNowPlayingForwardsTimestamp() async throws {
        let deps = makeDeps(fetcher: MockFetcher(known: ["ep1"]))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.setNowPlaying,
            args: ["episode_id": "ep1", "timestamp": 12.0],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertEqual(decoded["episode_id"] as? String, "ep1")
        let calls = await deps.playback.recordedNowPlaying
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, "ep1")
        XCTAssertEqual(calls.first?.1, 12.0)
    }

    func testSetNowPlayingPermitsNilTimestamp() async throws {
        let deps = makeDeps(fetcher: MockFetcher(known: ["ep1"]))
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.setNowPlaying,
            args: ["episode_id": "ep1"],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertEqual(decoded["success"] as? Bool, true)
    }

    // MARK: - Unknown tool

    func testUnknownPodcastToolReturnsError() async throws {
        let deps = makeDeps()
        let json = await AgentTools.dispatchPodcast(
            name: "not_a_real_tool",
            args: [:],
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertNotNil(decoded["error"])
    }

    // MARK: - JSON-from-string entry point

    func testDispatchFromArgsJSONStringParsesObject() async throws {
        let deps = makeDeps()
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.openScreen,
            argsJSON: #"{"route":"briefings"}"#,
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertEqual(decoded["route"] as? String, "briefings")
    }

    func testDispatchFromArgsJSONStringRejectsMalformed() async throws {
        let deps = makeDeps()
        let json = await AgentTools.dispatchPodcast(
            name: AgentTools.PodcastNames.openScreen,
            argsJSON: "not json",
            deps: deps.bundle
        )
        let decoded = try decode(json)
        XCTAssertNotNil(decoded["error"])
    }

    // MARK: - PerplexityClient response parsing

    func testPerplexityClientParsesCitationsArray() throws {
        let body = """
        {"choices":[{"message":{"content":"hello"}}],"citations":["https://a","https://b"]}
        """
        let result = try PerplexityClient.parseResponse(Data(body.utf8))
        XCTAssertEqual(result.answer, "hello")
        XCTAssertEqual(result.sources.map(\.url), ["https://a", "https://b"])
    }

    func testPerplexityClientParsesSearchResultsArray() throws {
        let body = """
        {"choices":[{"message":{"content":"x"}}],"search_results":[{"title":"Wiki","url":"https://wiki"}]}
        """
        let result = try PerplexityClient.parseResponse(Data(body.utf8))
        XCTAssertEqual(result.sources.first?.title, "Wiki")
        XCTAssertEqual(result.sources.first?.url, "https://wiki")
    }

    func testPerplexityClientHandlesMissingChoices() throws {
        let body = "{}"
        let result = try PerplexityClient.parseResponse(Data(body.utf8))
        XCTAssertEqual(result.answer, "")
        XCTAssertTrue(result.sources.isEmpty)
    }

    // MARK: - Helpers

    private func decode(_ json: String) throws -> [String: Any] {
        let raw = try JSONSerialization.jsonObject(with: Data(json.utf8))
        guard let obj = raw as? [String: Any] else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "non-object JSON"])
        }
        return obj
    }

    private struct DepsBundle {
        let bundle: PodcastAgentToolDeps
        let playback: MockPlayback
    }

    private func makeDeps(
        rag: PodcastAgentRAGSearchProtocol = MockRAG(),
        wiki: WikiStorageProtocol = MockWiki(),
        briefing: BriefingComposerProtocol = MockBriefing(),
        summarizer: EpisodeSummarizerProtocol = MockSummarizer(),
        fetcher: EpisodeFetcherProtocol = MockFetcher(),
        playback: MockPlayback = MockPlayback(),
        library: PodcastLibraryProtocol = MockLibrary(),
        inventory: PodcastInventoryProtocol = MockInventory(),
        categories: PodcastCategoryProtocol = MockInventory(),
        delegation: PodcastDelegationProtocol = MockDelegation(),
        perplexity: PerplexityClientProtocol = MockPerplexity(),
        ttsPublisher: TTSPublisherProtocol = MockTTSPublisher()
    ) -> DepsBundle {
        DepsBundle(
            bundle: PodcastAgentToolDeps(
                rag: rag,
                wiki: wiki,
                briefing: briefing,
                summarizer: summarizer,
                fetcher: fetcher,
                playback: playback,
                library: library,
                inventory: inventory,
                categories: categories,
                delegation: delegation,
                perplexity: perplexity,
                ttsPublisher: ttsPublisher,
                directory: MockDirectory(),
                subscribe: MockSubscribe()
            ),
            playback: playback
        )
    }
}

// Mocks live in `AgentToolsPodcastMocks.swift` (split out to keep this file
// under the 500-line hard cap).
