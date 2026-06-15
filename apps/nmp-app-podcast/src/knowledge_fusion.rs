//! Reciprocal Rank Fusion (RRF) for hybrid BM25 + vector search.
//!
//! Pure free-function module — no I/O, no locks, no runtime calls.
//! Callable in unit tests without constructing any app state.
//!
//! ## Algorithm
//!
//! RRF with `k = 60` (matching `VectorIndex.swift` on iOS):
//!
//! ```text
//! score[ep] += 1.0 / (60.0 + rank + 1.0)
//! ```
//!
//! where `rank` is 0-based position in either the BM25 list or the
//! vector-hits list. Both lists are passed pre-truncated to
//! `KNOWLEDGE_SEARCH_TOP_K * 4` candidates; this function fuses and
//! returns at most `KNOWLEDGE_SEARCH_TOP_K` results.
//!
//! ## Dedup rule
//!
//! An episode may appear in both lists. On first encounter the
//! `KnowledgeSearchResult` metadata is taken from whichever list provides
//! it (BM25 first, then vector). Per the spec, the vector-hit chunk
//! wins `start_secs` and `snippet` if it also appears in the vector list
//! (higher-fidelity signal). Best-chunk-per-episode wins the slot; the
//! caller (the `KnowledgeState::search` spawn) passes the full
//! `top_k_search` result (already sorted by cosine score, best chunk first)
//! so the first occurrence of each episode_id is the best chunk.

use std::collections::HashMap;

use podcast_knowledge::SearchResult;

use crate::ffi::projections::KnowledgeSearchResult;

/// Fuse a BM25 result list with a vector-search result list via RRF.
///
/// # Parameters
///
/// - `bm25`: ordered BM25 results (rank 0 = best). Carries full
///   `KnowledgeSearchResult` metadata.
/// - `vector_hits`: ordered cosine-KNN results from
///   [`podcast_knowledge::top_k_search`] (rank 0 = highest cosine score).
///   Each [`SearchResult`] has a `.chunk.episode_id`; the caller must
///   over-fetch to `KNOWLEDGE_SEARCH_TOP_K * 4` before passing here.
/// - `labels`: `episode_id → (podcast_title, episode_title)` map built
///   from the library at search time. Vector hits whose episode_id is not
///   in this map (unsubscribed since indexing) are silently skipped.
/// - `top_k`: maximum results to return.
/// - `rrf_k`: RRF smoothing constant (pass `RRF_K` = 60.0 in production;
///   exposed for unit-test overrides).
///
/// # Returns
///
/// `Vec<KnowledgeSearchResult>` sorted descending by fused RRF score,
/// length ≤ `top_k`. The `relevance_score` field carries the RRF score
/// (not a raw cosine or BM25 score).
pub fn fuse_rrf(
    bm25: Vec<KnowledgeSearchResult>,
    vector_hits: Vec<SearchResult>,
    labels: &HashMap<String, (String, String)>,
    top_k: usize,
    rrf_k: f64,
) -> Vec<KnowledgeSearchResult> {
    // Accumulate RRF scores and collect metadata per episode_id.
    let mut scores: HashMap<String, f64> = HashMap::new();
    // Best metadata seen so far per episode_id (last-write-wins for vector
    // hits that upgrade snippet/start_secs).
    let mut meta: HashMap<String, KnowledgeSearchResult> = HashMap::new();

    // -- BM25 list contribution --
    for (rank, row) in bm25.iter().enumerate() {
        let ep_id = &row.episode_id;
        *scores.entry(ep_id.clone()).or_insert(0.0) += 1.0 / (rrf_k + rank as f64 + 1.0);
        meta.entry(ep_id.clone()).or_insert_with(|| row.clone());
    }

    // -- Vector list contribution (best chunk per episode wins metadata) --
    // `vector_hits` is sorted best-to-worst by cosine score; we track
    // which episode_ids we've already seen so the best (first) chunk wins
    // the metadata slot.
    let mut seen_in_vector: HashMap<String, bool> = HashMap::new();
    for (rank, hit) in vector_hits.iter().enumerate() {
        let ep_id = &hit.chunk.episode_id;

        // Skip episodes not in the current library.
        let (podcast_title, episode_title) = match labels.get(ep_id.as_str()) {
            Some(pair) => pair,
            None => continue,
        };

        *scores.entry(ep_id.clone()).or_insert(0.0) += 1.0 / (rrf_k + rank as f64 + 1.0);

        // Only the best chunk (lowest rank = first occurrence) upgrades metadata.
        if !seen_in_vector.contains_key(ep_id.as_str()) {
            seen_in_vector.insert(ep_id.clone(), true);
            // Build a result from vector hit — it carries a real start_secs
            // and chunk-level snippet (higher fidelity than BM25 description hit).
            let vector_meta = KnowledgeSearchResult {
                episode_id: ep_id.clone(),
                episode_title: episode_title.clone(),
                podcast_title: podcast_title.clone(),
                snippet: hit.chunk.text.chars().take(200).collect(),
                start_secs: Some(hit.chunk.start_secs),
                // Placeholder — overwritten from `scores` after fusion.
                relevance_score: 0.0,
            };
            // Vector metadata wins over BM25 metadata when the episode appears
            // in both lists (chunk is higher-fidelity signal).
            meta.insert(ep_id.clone(), vector_meta);
        }
    }

    // -- Sort by fused RRF score and truncate --
    let mut fused: Vec<(String, f64)> = scores.into_iter().collect();
    fused.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    fused.truncate(top_k);

    fused
        .into_iter()
        .filter_map(|(ep_id, rrf_score)| {
            meta.remove(&ep_id).map(|mut row| {
                row.relevance_score = rrf_score as f32;
                row
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use podcast_knowledge::types::TranscriptChunk;
    use podcast_knowledge::SearchResult;

    use crate::ffi::projections::KnowledgeSearchResult;

    use super::fuse_rrf;

    fn make_bm25(episode_id: &str, score: f32) -> KnowledgeSearchResult {
        KnowledgeSearchResult {
            episode_id: episode_id.to_owned(),
            episode_title: format!("Episode {episode_id}"),
            podcast_title: "Test Podcast".to_owned(),
            snippet: format!("snippet for {episode_id}"),
            start_secs: None,
            relevance_score: score,
        }
    }

    fn make_vector_hit(episode_id: &str, score: f32, chunk_index: u32) -> SearchResult {
        SearchResult {
            chunk: TranscriptChunk {
                episode_id: episode_id.to_owned(),
                chunk_index,
                start_secs: 42.0 + chunk_index as f64,
                end_secs: 60.0 + chunk_index as f64,
                text: format!("vector hit text for {episode_id}"),
                word_count: 5,
            },
            score,
        }
    }

    fn labels_for(ids: &[&str]) -> HashMap<String, (String, String)> {
        ids.iter()
            .map(|id| {
                (
                    id.to_string(),
                    (
                        "Test Podcast".to_owned(),
                        format!("Episode {id}"),
                    ),
                )
            })
            .collect()
    }

    /// An episode that appears in BOTH lists must outrank one that only
    /// appears in either alone (hand-computed RRF).
    ///
    /// Setup:
    /// - ep-A: BM25 rank 0 + vector rank 1 → 1/61 + 1/62 ≈ 0.0164 + 0.0161 = 0.0325
    /// - ep-B: BM25 rank 1 only            → 1/62               ≈ 0.0161
    /// - ep-C: vector rank 0 only          → 1/61               ≈ 0.0164
    ///
    /// ep-A wins (both lists, combined score highest).
    /// ep-C (rank 0 in vector) outranks ep-B (rank 1 in BM25) by 1/61 vs 1/62.
    /// Expected order: ep-A > ep-C > ep-B
    #[test]
    fn fuse_rrf_both_lists_outranks_single_list() {
        let bm25 = vec![
            make_bm25("ep-A", 1.0), // rank 0
            make_bm25("ep-B", 0.8), // rank 1
        ];
        let vector_hits = vec![
            make_vector_hit("ep-C", 0.99, 0), // rank 0 in vector
            make_vector_hit("ep-A", 0.80, 1), // rank 1 in vector
        ];
        let labels = labels_for(&["ep-A", "ep-B", "ep-C"]);

        let result = fuse_rrf(bm25, vector_hits, &labels, 10, 60.0);

        assert_eq!(result.len(), 3, "should have 3 unique episodes");
        assert_eq!(result[0].episode_id, "ep-A", "ep-A must rank first (both lists)");
        // ep-C (rank 0 in vector) beats ep-B (rank 1 in BM25 only)
        assert_eq!(result[1].episode_id, "ep-C", "ep-C beats ep-B");
        assert_eq!(result[2].episode_id, "ep-B");

        // ep-A's score must be larger than ep-C and ep-B.
        assert!(
            result[0].relevance_score > result[1].relevance_score,
            "ep-A score {} must beat ep-C score {}",
            result[0].relevance_score,
            result[1].relevance_score
        );
    }

    /// When all vector hits have NULL embeddings (empty vector_hits list),
    /// the fused result must equal BM25-only (degrade gracefully).
    #[test]
    fn fuse_rrf_degrade_to_bm25_when_vector_empty() {
        let bm25 = vec![
            make_bm25("ep-1", 1.0),
            make_bm25("ep-2", 0.7),
            make_bm25("ep-3", 0.4),
        ];
        let labels = labels_for(&["ep-1", "ep-2", "ep-3"]);

        let fused = fuse_rrf(bm25.clone(), vec![], &labels, 10, 60.0);

        // Same episode ordering as BM25.
        let fused_ids: Vec<&str> = fused.iter().map(|r| r.episode_id.as_str()).collect();
        let bm25_ids: Vec<&str> = bm25.iter().map(|r| r.episode_id.as_str()).collect();
        assert_eq!(fused_ids, bm25_ids, "degrade: fused order must match BM25 order");
        assert_eq!(fused.len(), 3);
    }

    /// Vector hits whose episode_id is not in the labels map (unsubscribed
    /// episodes) must be silently skipped.
    #[test]
    fn fuse_rrf_skips_unlabeled_vector_hits() {
        let bm25 = vec![make_bm25("ep-known", 1.0)];
        let vector_hits = vec![
            make_vector_hit("ep-known", 0.9, 0),
            make_vector_hit("ep-unknown", 0.95, 0), // not in labels
        ];
        // Only ep-known is in the library.
        let labels = labels_for(&["ep-known"]);

        let fused = fuse_rrf(bm25, vector_hits, &labels, 10, 60.0);

        assert_eq!(fused.len(), 1, "ep-unknown must be skipped");
        assert_eq!(fused[0].episode_id, "ep-known");
    }

    /// Top-k truncation: even if there are more fused results, output is
    /// capped at `top_k`.
    #[test]
    fn fuse_rrf_truncates_to_top_k() {
        let bm25: Vec<KnowledgeSearchResult> = (0..8)
            .map(|i| make_bm25(&format!("ep-{i}"), 1.0 - i as f32 * 0.1))
            .collect();
        let ids: Vec<String> = (0..8).map(|i| format!("ep-{i}")).collect();
        let label_strs: Vec<&str> = ids.iter().map(String::as_str).collect();
        let labels = labels_for(&label_strs);

        let fused = fuse_rrf(bm25, vec![], &labels, 3, 60.0);

        assert_eq!(fused.len(), 3, "must be truncated to top_k=3");
    }

    /// Best chunk per episode: when multiple chunks from the same episode
    /// appear in the vector list, only the first (best) sets the metadata.
    #[test]
    fn fuse_rrf_best_chunk_per_episode_wins_metadata() {
        let bm25 = vec![];
        // Two chunks for ep-X; chunk 0 has the better score and lower rank.
        let vector_hits = vec![
            make_vector_hit("ep-X", 0.99, 0), // rank 0 → sets metadata
            make_vector_hit("ep-X", 0.70, 1), // rank 1 → skipped for metadata
        ];
        let labels = labels_for(&["ep-X"]);

        let fused = fuse_rrf(bm25, vector_hits, &labels, 10, 60.0);

        assert_eq!(fused.len(), 1);
        // start_secs from chunk 0 (42.0).
        assert_eq!(
            fused[0].start_secs,
            Some(42.0),
            "best chunk (chunk 0) must provide start_secs"
        );
    }

    /// Semantic ranking: seed two episodes with nearly-orthogonal 1024-d
    /// embeddings and a query vector closest to ep-semantic-winner. BM25
    /// would rank ep-bm25-winner first (it has more keyword overlap) but
    /// the fused result must rank ep-semantic-winner first because cosine
    /// gives it rank-0 in the vector list.
    ///
    /// Embedding construction:
    /// - ep-bm25-winner chunk: all zeros except dim 0 = 1.0 (unit vec in dim 0).
    /// - ep-semantic-winner chunk: all zeros except dim 512 = 1.0 (orthogonal).
    /// - query: all zeros except dim 512 = 1.0 → cosine sim 1.0 with
    ///   ep-semantic-winner, 0.0 with ep-bm25-winner.
    ///
    /// BM25 ranks ep-bm25-winner first (rank 0); vector ranks ep-semantic-winner
    /// first (rank 0). After RRF fusion ep-semantic-winner wins because its
    /// combined score = 1/61 (vector rank 0) vs ep-bm25-winner = 1/61 (BM25
    /// rank 0) + 0 (not in top vector hits). Tie → stable sort; to break the
    /// tie deterministically we set ep-semantic-winner at BM25 rank 1 as well
    /// so BM25-winner score = 1/61 and semantic-winner = 1/61 + 1/62.
    #[test]
    fn semantic_ranking_beats_bm25_only() {
        use podcast_knowledge::{top_k_search, EmbeddingVector, KnowledgeChunk, KnowledgeStore};
        use podcast_transcripts::TranscriptChunk;

        // Build 1024-d unit vectors.
        let mut emb_bm25 = vec![0.0_f32; 1024];
        emb_bm25[0] = 1.0; // unit vec in dim 0

        let mut emb_semantic = vec![0.0_f32; 1024];
        emb_semantic[512] = 1.0; // unit vec in dim 512 — orthogonal to emb_bm25

        // Query vector matches ep-semantic-winner perfectly.
        let mut query_vec = vec![0.0_f32; 1024];
        query_vec[512] = 1.0;

        // Seed KnowledgeStore.
        let mut ks = KnowledgeStore::new();
        ks.upsert(KnowledgeChunk::with_embedding(
            TranscriptChunk {
                episode_id: "ep-bm25-winner".to_owned(),
                chunk_index: 0,
                start_secs: 0.0,
                end_secs: 10.0,
                text: "quantum computing entanglement superposition".to_owned(),
                word_count: 4,
            },
            EmbeddingVector::new(emb_bm25),
        ));
        ks.upsert(KnowledgeChunk::with_embedding(
            TranscriptChunk {
                episode_id: "ep-semantic-winner".to_owned(),
                chunk_index: 0,
                start_secs: 5.0,
                end_secs: 15.0,
                text: "unrelated text about cooking recipes".to_owned(),
                word_count: 5,
            },
            EmbeddingVector::new(emb_semantic),
        ));

        // Vector hits: ep-semantic-winner is rank 0 (cosine 1.0),
        // ep-bm25-winner is rank 1 (cosine 0.0, but included since k=2).
        let vector_hits = top_k_search(&ks, &query_vec, 2);
        assert_eq!(vector_hits.len(), 2, "both chunks must be found");
        assert_eq!(
            vector_hits[0].chunk.episode_id, "ep-semantic-winner",
            "semantic winner must be top cosine hit"
        );

        // BM25 list: ep-bm25-winner is rank 0, ep-semantic-winner rank 1.
        // (We simulate this manually — in production BM25 runs over title/desc.)
        let bm25 = vec![
            make_bm25("ep-bm25-winner", 1.0),    // rank 0
            make_bm25("ep-semantic-winner", 0.5), // rank 1
        ];

        let labels = labels_for(&["ep-bm25-winner", "ep-semantic-winner"]);

        // Fuse: ep-semantic-winner appears in both lists (vector rank 0 + BM25 rank 1).
        // ep-bm25-winner appears in both lists (BM25 rank 0 + vector rank 1).
        // Scores:
        //   ep-semantic-winner = 1/61 (vector rank 0) + 1/62 (BM25 rank 1) ≈ 0.03249
        //   ep-bm25-winner     = 1/62 (vector rank 1) + 1/61 (BM25 rank 0) ≈ 0.03249
        //
        // Wait — these are identical. Let's instead have ep-semantic-winner NOT in
        // BM25 (it mentions cooking, not quantum). Then:
        //   ep-semantic-winner = 1/61 (vector rank 0 only) ≈ 0.01639
        //   ep-bm25-winner     = 1/61 (BM25 rank 0) + 1/62 (vector rank 1) ≈ 0.01639+0.01613 = 0.03252
        //
        // With that setup BM25-winner would win. For semantic to win without BM25
        // we need ep-semantic-winner to be ONLY in the vector list AND rank 0
        // there. But we also want ep-bm25-winner to NOT appear in the vector list.
        //
        // The real test: query is orthogonal to ep-bm25-winner (cosine 0.0) so
        // top_k_search with k=1 returns ONLY ep-semantic-winner.
        let vector_hits_k1 = top_k_search(&ks, &query_vec, 1);
        assert_eq!(vector_hits_k1.len(), 1);
        assert_eq!(vector_hits_k1[0].chunk.episode_id, "ep-semantic-winner");

        // With only ep-semantic-winner in the vector list (k=1) and ep-bm25-winner
        // only in BM25, fused scores:
        //   ep-semantic-winner: BM25 rank 1 + vector rank 0 = 1/62 + 1/61 ≈ 0.03252
        //   ep-bm25-winner:     BM25 rank 0 only            = 1/61          ≈ 0.01639
        // ep-semantic-winner wins.
        let fused = fuse_rrf(bm25.clone(), vector_hits_k1, &labels, 10, 60.0);

        assert!(fused.len() >= 2, "both episodes must appear in fused result");
        assert_eq!(
            fused[0].episode_id, "ep-semantic-winner",
            "semantic winner must rank first: BM25 rank 1 + vector rank 0 > BM25 rank 0 alone"
        );
    }
}
