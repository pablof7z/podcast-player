import Foundation

// MARK: - Public protocol

/// On-device store for embedded chunks of transcripts and wiki pages.
///
/// Implementations must be safe to call from any task. The SQLiteVec impl
/// runs on a serialized actor; the in-memory fallback is also actor-isolated.
/// All methods are async to leave room for future remote stores without
/// changing the call sites in `RAGSearch`, Lane 7 (wiki indexer), and
/// Lane 10 (`query_transcripts` / `query_wiki` agent tools).
///
/// **Embedding production is owned by the store**, not the caller. The
/// `Chunk` struct intentionally has no embedding field — callers (Lane 7
/// wiki indexer, Lane 10 agent tools) only ever read text + metadata.
/// At upsert time the store embeds chunk text via an injected
/// `EmbeddingsClient`. At query time callers pre-embed the *query* string
/// (typically via `RAGSearch`, which lives one layer above).
protocol VectorStore: Sendable {
    /// Insert or replace chunks. The store itself embeds each `chunk.text`
    /// before writing into the vector index.
    func upsert(chunks: [Chunk]) async throws

    /// Drop every chunk for the given episode. Idempotent.
    func deleteAll(forEpisodeID: UUID) async throws

    /// Pure cosine top-K over the vector index.
    /// Score is `1 - distance`, so higher is better.
    func topK(
        _ k: Int,
        for queryVector: [Float],
        scope: ChunkScope?
    ) async throws -> [ChunkMatch]

    /// Hybrid: cosine top-K from `vec0` MERGED with BM25 top-K from `fts5`
    /// via Reciprocal Rank Fusion. Returns up to `k` results with FTS-derived
    /// highlight ranges populated.
    func hybridTopK(
        _ k: Int,
        query: String,
        queryVector: [Float],
        scope: ChunkScope?
    ) async throws -> [ChunkMatch]
}

// MARK: - Errors

enum VectorStoreError: LocalizedError {
    case dimensionMismatch(expected: Int, got: Int)
    case storeNotInitialized
    case backingStorageFailure(String)

    var errorDescription: String? {
        switch self {
        case let .dimensionMismatch(expected, got):
            return "Embedding dimension mismatch: expected \(expected), got \(got)."
        case .storeNotInitialized:
            return "Vector store has not been initialized."
        case let .backingStorageFailure(detail):
            return "Vector store storage failure: \(detail)"
        }
    }
}
