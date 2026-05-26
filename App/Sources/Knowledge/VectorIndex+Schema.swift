import Foundation

extension VectorIndex {

    // MARK: - Schema

    func ensureSchema() async throws {
        if schemaReady { return }
        // chunks_meta: ordinary table — needed because vec0 / fts5 are
        // virtual tables and their rowids don't compose with WHERE on
        // arbitrary columns.
        _ = try await db.execute(
            """
            CREATE TABLE IF NOT EXISTS chunks_meta(
                chunk_id   TEXT PRIMARY KEY,
                episode_id TEXT NOT NULL,
                podcast_id TEXT NOT NULL,
                speaker_id TEXT,
                start_ms   INTEGER NOT NULL,
                end_ms     INTEGER NOT NULL,
                text       TEXT NOT NULL
            )
            """
        )
        _ = try await db.execute(
            "CREATE INDEX IF NOT EXISTS idx_chunks_meta_episode ON chunks_meta(episode_id)")
        _ = try await db.execute(
            "CREATE INDEX IF NOT EXISTS idx_chunks_meta_podcast ON chunks_meta(podcast_id)")
        _ = try await db.execute(
            "CREATE INDEX IF NOT EXISTS idx_chunks_meta_speaker ON chunks_meta(speaker_id)")

        _ = try await db.execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_vec USING vec0(
                chunk_id TEXT PRIMARY KEY,
                embedding FLOAT[\(dimensions)] distance_metric=cosine
            )
            """
        )
        _ = try await db.execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
                chunk_id UNINDEXED,
                text,
                tokenize='porter'
            )
            """
        )
        schemaReady = true
    }

    // MARK: - Metadata fetch + scope filter

    func fetchMetadata(
        forChunkIDs cids: [String],
        scope: ChunkScope?
    ) async throws -> [String: Chunk] {
        guard !cids.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: cids.count).joined(separator: ",")
        var params: [any Sendable] = cids
        var sql =
            "SELECT chunk_id, episode_id, podcast_id, speaker_id, start_ms, end_ms, text FROM chunks_meta WHERE chunk_id IN (\(placeholders))"
        if let scope {
            switch scope {
            case .all:
                break
            case let .podcast(pid):
                sql += " AND podcast_id = ?"
                params.append(pid.uuidString)
            case let .episodes(ids):
                guard !ids.isEmpty else { return [:] }
                let episodePlaceholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
                sql += " AND episode_id IN (\(episodePlaceholders))"
                params.append(contentsOf: ids.map(\.uuidString))
            case let .episode(eid):
                sql += " AND episode_id = ?"
                params.append(eid.uuidString)
            case let .speaker(sid):
                sql += " AND speaker_id = ?"
                params.append(sid.uuidString)
            }
        }
        let rows = try await db.query(sql, params: params)
        var out: [String: Chunk] = [:]
        for row in rows {
            guard let cid = row["chunk_id"] as? String,
                  let eid = (row["episode_id"] as? String).flatMap(UUID.init),
                  let pid = (row["podcast_id"] as? String).flatMap(UUID.init),
                  let startMS = row["start_ms"] as? Int,
                  let endMS = row["end_ms"] as? Int,
                  let text = row["text"] as? String,
                  let id = UUID(uuidString: cid) else { continue }
            let speaker = (row["speaker_id"] as? String).flatMap { $0.isEmpty ? nil : UUID(uuidString: $0) }
            out[cid] = Chunk(
                id: id,
                episodeID: eid,
                podcastID: pid,
                text: text,
                startMS: startMS,
                endMS: endMS,
                speakerID: speaker
            )
        }
        return out
    }

    // MARK: - RRF + highlight helpers (static, pure)

    static func rrf(vecRanks: [String], ftsRanks: [String], k: Double = 60) -> [(cid: String, score: Float)] {
        var scores: [String: Double] = [:]
        for (i, cid) in vecRanks.enumerated() {
            scores[cid, default: 0] += 1.0 / (k + Double(i + 1))
        }
        for (i, cid) in ftsRanks.enumerated() {
            scores[cid, default: 0] += 1.0 / (k + Double(i + 1))
        }
        return scores
            .sorted { $0.value > $1.value }
            .map { (cid: $0.key, score: Float($0.value)) }
    }

    /// Strip characters FTS5 treats as syntax so user text can be passed
    /// verbatim. Keeps alphanumerics + whitespace; everything else becomes
    /// a space. Empty-after-strip → no FTS query.
    static func sanitizeFTSQuery(_ raw: String) -> String {
        let cleaned = raw.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                return Character(scalar)
            }
            return " "
        }
        let s = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }
}
