import Foundation
@testable import AppTemplate

// MARK: - Lane-10 test mocks
//
// Pulled out of `AgentToolsPodcastTests.swift` so that file stays under the
// 500-line hard limit. Every mock is `actor` so it satisfies the `Sendable`
// protocol surface in `PodcastAgentToolDeps`.

actor MockRAG: PodcastAgentRAGSearchProtocol {
    private let searchResult: [EpisodeHit]
    private let transcriptsResult: [TranscriptHit]
    private let similarResult: [EpisodeHit]
    private(set) var lastSearchLimit: Int = -1
    private(set) var lastSimilarK: Int = -1

    init(
        searchEpisodesResult: [EpisodeHit] = [],
        transcriptsResult: [TranscriptHit] = [],
        similarResult: [EpisodeHit] = []
    ) {
        self.searchResult = searchEpisodesResult
        self.transcriptsResult = transcriptsResult
        self.similarResult = similarResult
    }

    func searchEpisodes(query: String, scope: PodcastID?, limit: Int) async throws -> [EpisodeHit] {
        lastSearchLimit = limit
        return searchResult
    }

    func queryTranscripts(query: String, scope: String?, limit: Int) async throws -> [TranscriptHit] {
        return transcriptsResult
    }

    func findSimilarEpisodes(seedEpisodeID: EpisodeID, k: Int) async throws -> [EpisodeHit] {
        lastSimilarK = k
        return similarResult
    }
}

actor MockWiki: WikiStorageProtocol {
    private let result: [WikiHit]
    init(result: [WikiHit] = []) { self.result = result }

    func queryWiki(topic: String, scope: PodcastID?, limit: Int) async throws -> [WikiHit] {
        return result
    }
}

actor MockBriefing: BriefingComposerProtocol {
    private let result: BriefingResult?
    private let error: Error?
    private(set) var lastLength: Int = -1

    init(result: BriefingResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func composeBriefing(scope: String, lengthMinutes: Int, style: String?) async throws -> BriefingResult {
        lastLength = lengthMinutes
        if let error = error { throw error }
        return result ?? BriefingResult(
            briefingID: "default", title: "Default", estimatedSeconds: 0, episodeIDs: []
        )
    }
}

actor MockSummarizer: EpisodeSummarizerProtocol {
    private let result: EpisodeSummary?
    init(result: EpisodeSummary? = nil) { self.result = result }

    func summarizeEpisode(episodeID: EpisodeID, length: String?) async throws -> EpisodeSummary {
        return result ?? EpisodeSummary(episodeID: episodeID, summary: "")
    }
}

actor MockFetcher: EpisodeFetcherProtocol {
    private let known: Set<EpisodeID>
    init(known: [EpisodeID] = []) { self.known = Set(known) }

    func episodeExists(episodeID: EpisodeID) async -> Bool {
        return known.contains(episodeID)
    }

    func episodeMetadata(episodeID: EpisodeID) async -> (podcastTitle: String, episodeTitle: String, durationSeconds: Int?)? {
        guard known.contains(episodeID) else { return nil }
        return ("Mock Show", "Episode \(episodeID)", 1800)
    }
}

actor MockPlayback: PlaybackHostProtocol {
    private(set) var recordedPlays: [(EpisodeID, Double)] = []
    private(set) var recordedNowPlaying: [(EpisodeID, Double?)] = []
    private(set) var recordedRoutes: [String] = []

    func playEpisodeAt(episodeID: EpisodeID, timestampSeconds: Double) async {
        recordedPlays.append((episodeID, timestampSeconds))
    }

    func setNowPlaying(episodeID: EpisodeID, timestampSeconds: Double?) async {
        recordedNowPlaying.append((episodeID, timestampSeconds))
    }

    func openScreen(route: String) async {
        recordedRoutes.append(route)
    }
}

actor MockPerplexity: PerplexityClientProtocol {
    private let result: PerplexityResult?
    private let error: Error?

    init(result: PerplexityResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func search(query: String) async throws -> PerplexityResult {
        if let error = error { throw error }
        return result ?? PerplexityResult(answer: "", sources: [])
    }
}
