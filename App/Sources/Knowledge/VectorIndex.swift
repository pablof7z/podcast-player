import Foundation

// TODO: Local vector index over transcript chunks and wiki pages. Embeddings
// produced via OpenRouter; storage will likely be SQLite + a binary blob per
// row, or a dedicated framework (e.g. SVDB) — to be decided in the spec.

/// On-device vector index used by the agent's RAG pipeline.
///
/// Intentionally empty at this stage — the synthesized product spec will define
/// the public surface (insert, query, persistence, embedding dimensionality).
final class VectorIndex {
    init() {}
}
