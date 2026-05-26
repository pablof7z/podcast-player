import Foundation
import os.log
import SQLiteVec

// Lane 6 — RAG: on-device vector + hybrid lexical store.
//
// One SQLite file at:
//   $applicationSupport/podcastr/vectors.sqlite
//
// Schema:
//   - chunks_meta : TEXT-keyed metadata table (chunk_id PK, episode/podcast/
//                   speaker FKs, start/end ms, text). Sourced for FTS
//                   bodies and `Chunk` reconstruction.
//   - chunks_vec  : vec0 virtual table over a 1024-d cosine embedding,
//                   keyed by `chunk_id` TEXT. The cosine metric matches
//                   `text-embedding-3-large` at 1024 dimensions.
//   - chunks_fts  : fts5 virtual table over `text`, keyed externally by
//                   `chunk_id` UNINDEXED. Drives BM25 lexical search and
//                   the highlight ranges returned by `hybridTopK`.
//
// All three are kept in lockstep via one transaction per `upsert(...)`.

// MARK: - SQLiteVec implementation

/// Production `VectorStore` backed by `sqlite-vec` + `fts5`.
///
/// `actor` isolation: SQLiteVec's `Database` is itself an actor, but we wrap
/// it so we can serialize multi-statement transactions (upsert touches three
/// tables per chunk) and so the public surface composes cleanly with Swift 6
/// strict concurrency.
actor VectorIndex: VectorStore {
    static let embeddingDimensions = 1024

    private static let logger = Logger.app("VectorIndex")
    // Internal so extension files (VectorIndex+Schema.swift) can access them.
    let db: Database
    let dimensions: Int
    let embedder: EmbeddingsClient
    var schemaReady: Bool = false

    /// Open (or create) the on-disk store. Defaults to
    /// `$applicationSupport/podcastr/vectors.sqlite`. The `embedder` is
    /// invoked on every `upsert(chunks:)` to produce vectors from text.
    ///
    /// Pass `fileURL = nil` for the default on-disk path. Pass
    /// `inMemory: true` for an ephemeral DB. When `inMemory` is true,
    /// `fileURL` is ignored. We don't accept `Database.Location` directly
    /// because it isn't `Sendable` in SQLiteVec 0.0.14, which trips strict
    /// concurrency at the actor boundary.
    init(
        embedder: EmbeddingsClient,
        fileURL: URL? = nil,
        inMemory: Bool = false,
        dimensions: Int = VectorIndex.embeddingDimensions
    ) throws {
        try SQLiteVec.initialize()
        self.dimensions = dimensions
        self.embedder = embedder

        if inMemory {
            self.db = try Database(.inMemory)
        } else {
            let url = try fileURL ?? Self.defaultStoreURL()
            self.db = try Database(.uri(url.path))
        }
    }

    /// Resolve (and create) the persistent on-disk path for the store.
    /// `applicationSupportDirectory` is **not** auto-created on iOS, so we
    /// have to ensure the `podcastr/` subdirectory exists before SQLite tries
    /// to open the file.
    static func defaultStoreURL() throws -> URL {
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("podcastr", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("vectors.sqlite")
    }

    // MARK: - VectorStore

    func upsert(chunks: [Chunk]) async throws {
        try await ensureSchema()
        guard !chunks.isEmpty else { return }

        // Embed all chunk texts up front (the embedder batches internally).
        let texts = chunks.map(\.text)
        let vectors = try await embedder.embed(texts)
        guard vectors.count == chunks.count else {
            throw VectorStoreError.backingStorageFailure(
                "Embedder returned \(vectors.count) vectors for \(chunks.count) chunks")
        }
        for vec in vectors where vec.count != dimensions {
            throw VectorStoreError.dimensionMismatch(expected: dimensions, got: vec.count)
        }

        // We can't use `db.transaction { ... }` here: its closure parameter
        // isn't `@Sendable`, so under Swift 6 strict concurrency the actor
        // boundary on `Database` rejects our captures. Manual BEGIN/COMMIT
        // gives the same atomicity without crossing a non-Sendable closure.
        _ = try await db.execute("BEGIN TRANSACTION")
        do {
            for (chunk, vec) in zip(chunks, vectors) {
                try await upsertOne(chunk: chunk, vector: vec)
            }
            _ = try await db.execute("COMMIT TRANSACTION")
        } catch {
            _ = try? await db.execute("ROLLBACK TRANSACTION")
            throw error
        }
    }

    private func upsertOne(chunk: Chunk, vector: [Float]) async throws {
        let cid = chunk.id.uuidString
        _ = try await db.execute(
            "DELETE FROM chunks_meta WHERE chunk_id = ?", params: [cid])
        _ = try await db.execute(
            "DELETE FROM chunks_vec WHERE chunk_id = ?", params: [cid])
        _ = try await db.execute(
            "DELETE FROM chunks_fts WHERE chunk_id = ?", params: [cid])
        _ = try await db.execute(
            """
            INSERT INTO chunks_meta(
                chunk_id, episode_id, podcast_id, speaker_id,
                start_ms, end_ms, text
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            params: [
                cid,
                chunk.episodeID.uuidString,
                chunk.podcastID.uuidString,
                chunk.speakerID?.uuidString ?? "",
                chunk.startMS,
                chunk.endMS,
                chunk.text,
            ]
        )
        _ = try await db.execute(
            "INSERT INTO chunks_vec(chunk_id, embedding) VALUES (?, ?)",
            params: [cid, vector]
        )
        _ = try await db.execute(
            "INSERT INTO chunks_fts(chunk_id, text) VALUES (?, ?)",
            params: [cid, chunk.text]
        )
    }

    func deleteAll(forEpisodeID episodeID: UUID) async throws {
        try await ensureSchema()
        let eid = episodeID.uuidString
        _ = try await db.execute("BEGIN TRANSACTION")
        do {
            let rows = try await db.query(
                "SELECT chunk_id FROM chunks_meta WHERE episode_id = ?", params: [eid])
            let cids = rows.compactMap { $0["chunk_id"] as? String }
            for cid in cids {
                _ = try await db.execute(
                    "DELETE FROM chunks_vec WHERE chunk_id = ?", params: [cid])
                _ = try await db.execute(
                    "DELETE FROM chunks_fts WHERE chunk_id = ?", params: [cid])
            }
            _ = try await db.execute(
                "DELETE FROM chunks_meta WHERE episode_id = ?", params: [eid])
            _ = try await db.execute("COMMIT TRANSACTION")
        } catch {
            _ = try? await db.execute("ROLLBACK TRANSACTION")
            throw error
        }
    }

    func chunk(episodeID: UUID, overlappingStartMS startMS: Int, endMS: Int) async throws -> Chunk? {
        try await ensureSchema()
        let rows = try await db.query(
            """
            SELECT chunk_id, episode_id, podcast_id, speaker_id, start_ms, end_ms, text
            FROM chunks_meta
            WHERE episode_id = ? AND start_ms < ? AND end_ms > ?
            ORDER BY ABS(start_ms - ?), start_ms
            LIMIT 1
            """,
            params: [episodeID.uuidString, endMS, startMS, startMS]
        )
        guard let row = rows.first,
              let cid = row["chunk_id"] as? String,
              let eid = (row["episode_id"] as? String).flatMap(UUID.init),
              let pid = (row["podcast_id"] as? String).flatMap(UUID.init),
              let rowStart = row["start_ms"] as? Int,
              let rowEnd = row["end_ms"] as? Int,
              let text = row["text"] as? String,
              let id = UUID(uuidString: cid) else { return nil }
        let speaker = (row["speaker_id"] as? String).flatMap { $0.isEmpty ? nil : UUID(uuidString: $0) }
        return Chunk(id: id, episodeID: eid, podcastID: pid, text: text, startMS: rowStart, endMS: rowEnd, speakerID: speaker)
    }

    func topK(
        _ k: Int,
        for queryVector: [Float],
        scope: ChunkScope?
    ) async throws -> [ChunkMatch] {
        try await ensureSchema()
        guard queryVector.count == dimensions else {
            throw VectorStoreError.dimensionMismatch(expected: dimensions, got: queryVector.count)
        }
        // Ask vec0 for an over-fetch and filter post hoc by scope. vec0
        // doesn't support `WHERE` predicates against unindexed metadata, so
        // we widen the candidate window and intersect with chunks_meta.
        let overfetch = max(k * 4, k + 16)
        let vecRows = try await db.query(
            """
            SELECT chunk_id, distance
            FROM chunks_vec
            WHERE embedding MATCH ?
            ORDER BY distance
            LIMIT ?
            """,
            params: [queryVector, overfetch]
        )
        let candidates: [(cid: String, distance: Double)] = vecRows.compactMap { row in
            guard let cid = row["chunk_id"] as? String else { return nil }
            let distance = (row["distance"] as? Double) ?? Double((row["distance"] as? Float) ?? 0)
            return (cid, distance)
        }
        guard !candidates.isEmpty else { return [] }

        let cids = candidates.map(\.cid)
        let metas = try await fetchMetadata(forChunkIDs: cids, scope: scope)
        var matches: [ChunkMatch] = []
        for (cid, distance) in candidates {
            guard let chunk = metas[cid] else { continue }
            let score = Float(max(0.0, 1.0 - distance))
            matches.append(ChunkMatch(chunk: chunk, score: score))
            if matches.count >= k { break }
        }
        return matches
    }

    func hybridTopK(
        _ k: Int,
        query: String,
        queryVector: [Float],
        scope: ChunkScope?
    ) async throws -> [ChunkMatch] {
        try await ensureSchema()
        guard queryVector.count == dimensions else {
            throw VectorStoreError.dimensionMismatch(expected: dimensions, got: queryVector.count)
        }

        let overfetch = max(k * 4, k + 16)

        // Vector candidates.
        let vecRows = try await db.query(
            """
            SELECT chunk_id, distance
            FROM chunks_vec
            WHERE embedding MATCH ?
            ORDER BY distance
            LIMIT ?
            """,
            params: [queryVector, overfetch]
        )
        let vecOrder: [String] = vecRows.compactMap { $0["chunk_id"] as? String }

        // FTS candidates.
        let ftsQuery = Self.sanitizeFTSQuery(query)
        var ftsOrder: [String] = []
        if !ftsQuery.isEmpty {
            let ftsRows = try await db.query(
                """
                SELECT chunk_id, bm25(chunks_fts) AS score
                FROM chunks_fts
                WHERE chunks_fts MATCH ?
                ORDER BY score
                LIMIT ?
                """,
                params: [ftsQuery, overfetch]
            )
            ftsOrder = ftsRows.compactMap { $0["chunk_id"] as? String }
        }

        // Reciprocal Rank Fusion (k = 60 per Garcia / standard).
        let fused = Self.rrf(vecRanks: vecOrder, ftsRanks: ftsOrder)
        guard !fused.isEmpty else { return [] }

        let cids = fused.map(\.cid)
        let metas = try await fetchMetadata(forChunkIDs: cids, scope: scope)
        var matches: [ChunkMatch] = []
        for (cid, score) in fused {
            guard let chunk = metas[cid] else { continue }
            let highlights = ChunkHighlights.compute(in: chunk.text, query: query)
            matches.append(ChunkMatch(chunk: chunk, score: score, textHighlights: highlights))
            if matches.count >= k { break }
        }
        return matches
    }
}
