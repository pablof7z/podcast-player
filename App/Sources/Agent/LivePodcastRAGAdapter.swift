import Foundation

// MARK: - LivePodcastRAGAdapter
//
// Bridges `RAGService.shared.search` (which returns `[ChunkMatch]`) to the
// agent-tool's `[EpisodeHit]` / `[TranscriptHit]` value types. Episode-level
// rollup groups chunk hits by `episodeID`, keeps the best score per episode,
// then joins against `AppStateStore` to hydrate titles and durations.
//
// `findSimilarEpisodes` reuses the seed episode's title + truncated description
// as the retrieval query, then drops the seed itself from the result so the
// agent never recommends the episode the user is already on.

struct LivePodcastRAGAdapter: PodcastAgentRAGSearchProtocol {

    /// Weak handle on the live store so `EpisodeHit` rows can be filled in
    /// with real podcast titles / durations / publish dates.
    weak var store: AppStateStore?

    init(store: AppStateStore) {
        self.store = store
    }

    func searchEpisodes(query: String, scope: PodcastID?, limit: Int) async throws -> [EpisodeHit] {
        let chunkScope = Self.chunkScope(podcastID: scope)
        // Over-fetch so the per-episode rollup still returns `limit` distinct
        // episodes when several chunks come from the same show.
        let opts = RAGSearch.Options(k: max(1, limit) * 4, hybrid: true, rerank: true)
        let matches = try await RAGService.shared.search.search(
            query: query,
            scope: chunkScope,
            options: opts
        )
        return await rollUpToEpisodes(matches: matches, limit: limit)
    }

    func queryTranscripts(query: String, scope: String?, limit: Int) async throws -> [TranscriptHit] {
        let chunkScope = Self.chunkScope(transcriptScope: scope)
        let opts = RAGSearch.Options(k: max(1, limit), hybrid: true, rerank: true)
        let matches = try await RAGService.shared.search.search(
            query: query,
            scope: chunkScope,
            options: opts
        )
        return matches.map(Self.makeTranscriptHit)
    }

    func findSimilarEpisodes(seedEpisodeID: EpisodeID, k: Int) async throws -> [EpisodeHit] {
        guard let seedUUID = UUID(uuidString: seedEpisodeID),
              let seed = await store?.episode(id: seedUUID) else {
            return []
        }
        let queryParts = [seed.title, String(seed.description.prefix(400))]
            .filter { !$0.isEmpty }
        let query = queryParts.joined(separator: " ")
        let opts = RAGSearch.Options(k: max(1, k) * 4, hybrid: true, rerank: true)
        let matches = try await RAGService.shared.search.search(
            query: query,
            scope: nil,
            options: opts
        )
        let hits = await rollUpToEpisodes(matches: matches, limit: k + 1)
        return Array(hits.filter { $0.episodeID != seedEpisodeID }.prefix(k))
    }

    // MARK: Private rollup

    @MainActor
    private func rollUpToEpisodes(matches: [ChunkMatch], limit: Int) -> [EpisodeHit] {
        guard let store else { return [] }
        var bestPerEpisode: [UUID: (score: Float, snippet: String)] = [:]
        var orderedEpisodeIDs: [UUID] = []
        for match in matches {
            let id = match.chunk.episodeID
            let entry = bestPerEpisode[id]
            if entry == nil {
                orderedEpisodeIDs.append(id)
                bestPerEpisode[id] = (match.score, match.chunk.text)
            } else if let prior = entry, match.score > prior.score {
                bestPerEpisode[id] = (match.score, match.chunk.text)
            }
            if orderedEpisodeIDs.count >= limit { break }
        }
        return orderedEpisodeIDs.compactMap { episodeID -> EpisodeHit? in
            guard let entry = bestPerEpisode[episodeID],
                  let episode = store.episode(id: episodeID) else { return nil }
            let subscription = store.state.subscriptions.first { $0.id == episode.subscriptionID }
            return EpisodeHit(
                episodeID: episodeID.uuidString,
                podcastID: episode.subscriptionID.uuidString,
                title: episode.title,
                podcastTitle: subscription?.title ?? "",
                publishedAt: episode.pubDate,
                durationSeconds: episode.duration.map { Int($0) },
                snippet: String(entry.snippet.prefix(280)),
                score: Double(entry.score)
            )
        }
    }

    // MARK: Helpers

    /// `searchEpisodes` only narrows by podcast — translate the optional
    /// podcast-id string into a `ChunkScope` (or `nil` for "everything").
    static func chunkScope(podcastID: PodcastID?) -> ChunkScope? {
        guard let raw = podcastID, let uuid = UUID(uuidString: raw) else { return nil }
        return .podcast(uuid)
    }

    /// `queryTranscripts` accepts either an episode UUID or a podcast UUID in
    /// the `scope` field. Episode wins when both parse (the agent shouldn't
    /// be ambiguous, but defensive ordering means an episode-id never widens
    /// to its whole show by accident).
    static func chunkScope(transcriptScope: String?) -> ChunkScope? {
        guard let raw = transcriptScope, let uuid = UUID(uuidString: raw) else { return nil }
        return .episode(uuid)
    }

    static func makeTranscriptHit(_ match: ChunkMatch) -> TranscriptHit {
        TranscriptHit(
            episodeID: match.chunk.episodeID.uuidString,
            startSeconds: TimeInterval(match.chunk.startMS) / 1000.0,
            endSeconds: TimeInterval(match.chunk.endMS) / 1000.0,
            speaker: nil,
            text: match.chunk.text,
            score: Double(match.score)
        )
    }
}
