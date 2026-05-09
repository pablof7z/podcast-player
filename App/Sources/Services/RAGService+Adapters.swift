import Foundation
import os.log

// MARK: - WikiRAGSearchAdapter
//
// Bridges `RAGSearch` (which returns `[ChunkMatch]`) to `WikiRAGSearchProtocol`
// (which the wiki generator + verifier consume as `[RAGChunk]`).
//
// Two responsibilities:
//   1. Score-and-shape conversion (`ChunkMatch.chunk + score → RAGChunk`).
//   2. `WikiScope` ↔ `ChunkScope` translation. The wiki layer knows about
//      `global` and `podcast(UUID)`; the vector store also has `episode` and
//      `speaker`, but the wiki side never asks for those.

struct WikiRAGSearchAdapter: WikiRAGSearchProtocol {

    let search: RAGSearch
    let index: VectorIndex

    func search(
        query: String,
        scope: WikiScope?,
        limit: Int
    ) async throws -> [RAGChunk] {
        let chunkScope = Self.chunkScope(for: scope)
        let options = RAGSearch.Options(k: max(1, limit))
        let matches = try await search.search(
            query: query,
            scope: chunkScope,
            options: options
        )
        return matches.map(Self.makeRAGChunk)
    }

    func chunk(
        episodeID: UUID,
        startMS: Int,
        endMS: Int
    ) async throws -> RAGChunk? {
        // Verifier path: locate a chunk that overlaps the cited span. We
        // don't have a direct "fetch by range" API on `VectorIndex`, so we
        // ask `topK` over the episode scope using a synthetic zero-vector
        // query — `VectorIndex.topK` rejects mismatched dimensions, so
        // instead we route through `hybridTopK` with an empty query +
        // dummy vector via the embeddings client. That's expensive.
        //
        // Cheaper alternative: scope the search to the episode + the
        // citation's quote text. The verifier already calls this with
        // (episodeID, span); we can use a narrow text query around the
        // span by re-running search with the chunk text as the query. But
        // we don't have the text yet — that's exactly what we're trying
        // to retrieve.
        //
        // Pragmatic fix: ask the search pipeline for everything in this
        // episode using a generic query string ("."), then linearly scan
        // for an overlapping span. This is O(k) per verification (k is
        // small) and avoids leaking sqlite specifics into the adapter.
        let scope = ChunkScope.episode(episodeID)
        let opts = RAGSearch.Options(k: 64, overfetchMultiplier: 1, hybrid: false, rerank: false)
        let matches = (try? await search.search(query: ".", scope: scope, options: opts)) ?? []
        for m in matches {
            if startMS < m.chunk.endMS && endMS > m.chunk.startMS {
                return Self.makeRAGChunk(from: m)
            }
        }
        return nil
    }

    // MARK: - Helpers

    static func chunkScope(for wiki: WikiScope?) -> ChunkScope? {
        guard let wiki else { return nil }
        switch wiki {
        case .global:               return .all
        case .podcast(let id):      return .podcast(id)
        }
    }

    static func makeRAGChunk(from match: ChunkMatch) -> RAGChunk {
        RAGChunk(
            id: match.chunk.id,
            episodeID: match.chunk.episodeID,
            podcastID: match.chunk.podcastID,
            startMS: match.chunk.startMS,
            endMS: match.chunk.endMS,
            text: match.chunk.text,
            speaker: nil,
            score: Double(match.score)
        )
    }
}

// MARK: - BriefingRAGSearchAdapter
//
// Bridges `RAGSearch` to `BriefingRAGSearchProtocol`. Unlike the wiki adapter,
// this one needs episode + subscription metadata (`enclosureURL`, show name)
// to populate `RAGCandidate.sourceLabel` and `RAGCandidate.enclosureURL`.
// The lookup is satisfied lazily through `RAGService.appStore`.

struct BriefingRAGSearchAdapter: BriefingRAGSearchProtocol {

    let service: RAGService

    func search(
        query: String,
        scope: BriefingScope,
        limit: Int
    ) async throws -> [RAGCandidate] {
        let chunkScope = await Self.chunkScope(for: scope, service: service)
        let options = RAGSearch.Options(k: max(1, limit))
        let matches = try await service.search.search(
            query: query,
            scope: chunkScope,
            options: options
        )
        return await Self.shape(matches: matches, service: service)
    }

    // MARK: - Helpers

    /// Translate the briefing-domain scope to the vector-store-domain scope.
    /// `mySubscriptions` and `thisWeek` map to `nil` (everything in the
    /// store). `thisShow` and `thisTopic` would carry an id from the UI; the
    /// current request shape doesn't expose one, so they also widen to
    /// "everything" for now.
    @MainActor
    static func chunkScope(for briefing: BriefingScope, service _: RAGService) -> ChunkScope? {
        switch briefing {
        case .mySubscriptions, .thisWeek, .thisTopic, .thisShow:
            return nil
        }
    }

    /// Map vector-store matches into briefing candidates, hydrating
    /// metadata from the `AppStateStore` when available.
    @MainActor
    static func shape(matches: [ChunkMatch], service: RAGService) -> [RAGCandidate] {
        let store = service.appStore
        return matches.map { m -> RAGCandidate in
            let episode = store?.episode(id: m.chunk.episodeID)
            let subscription = episode.flatMap { ep in
                store?.state.subscriptions.first { $0.id == ep.subscriptionID }
            }
            let label: String = {
                let timeMS = m.chunk.startMS
                let formatted = formatTime(seconds: Double(timeMS) / 1000.0)
                if let title = subscription?.title, !title.isEmpty {
                    return "\(title) · \(formatted)"
                }
                if let title = episode?.title, !title.isEmpty {
                    return "\(title) · \(formatted)"
                }
                return "Podcast · \(formatted)"
            }()
            return RAGCandidate(
                id: m.chunk.id,
                sourceKind: .episode,
                episodeID: m.chunk.episodeID,
                enclosureURL: episode?.enclosureURL,
                wikiPageID: nil,
                sourceLabel: label,
                text: m.chunk.text,
                startSeconds: TimeInterval(m.chunk.startMS) / 1000.0,
                endSeconds: TimeInterval(m.chunk.endMS) / 1000.0,
                score: Double(m.score)
            )
        }
    }

    private static func formatTime(seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let mm = total / 60
        let ss = total % 60
        return String(format: "%d:%02d", mm, ss)
    }
}
