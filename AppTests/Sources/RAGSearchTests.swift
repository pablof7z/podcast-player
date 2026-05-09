import XCTest
@testable import Podcastr

final class RAGSearchTests: XCTestCase {

    func testSearchEmbedsQueryAndRanksMatchingChunks() async throws {
        let episodeID = UUID()
        let podcastID = UUID()
        let embedder = KeywordEmbeddingsClient()
        let store = InMemoryVectorStore(embedder: embedder)
        try await store.upsert(chunks: [
            Chunk(
                episodeID: episodeID,
                podcastID: podcastID,
                text: "Keto diet discussion about insulin sensitivity and appetite.",
                startMS: 10_000,
                endMS: 25_000
            ),
            Chunk(
                episodeID: UUID(),
                podcastID: podcastID,
                text: "A stamp collector talks about rare postal cancellations.",
                startMS: 0,
                endMS: 12_000
            ),
        ])

        let rag = RAGSearch(store: store, embedder: embedder, reranker: nil)
        let matches = try await rag.search(
            query: "keto insulin",
            scope: .podcast(podcastID),
            options: .init(k: 1, hybrid: true, rerank: false)
        )

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.chunk.episodeID, episodeID)
        XCTAssertTrue(matches.first?.textHighlights.isEmpty == false)
    }
}

private struct KeywordEmbeddingsClient: EmbeddingsClient {
    private let keywords = ["keto", "insulin", "stamp", "postal"]

    func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map { text in
            let lower = text.lowercased()
            return keywords.map { lower.contains($0) ? 1 : 0 }
        }
    }
}
