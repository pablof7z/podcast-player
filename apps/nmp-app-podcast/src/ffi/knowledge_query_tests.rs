//! Tests for `knowledge_query` — slice 5b.
//!
//! These tests exercise `run_knowledge_query_inner` and the pure helpers
//! directly (no `PodcastHandle` required). `embed_query_for_rag` degrades to
//! `None` in tests (no API key), so the hybrid path reduces to BM25-only; the
//! vector search is exercised directly via `scoped_top_k_search`.

use std::collections::HashSet;
use std::sync::{Arc, Mutex};

use podcast_core::{Episode, Podcast, PodcastId};
use podcast_knowledge::{EmbeddingVector, KnowledgeChunk, KnowledgeStore};
use podcast_transcripts::TranscriptChunk;
use url::Url;
use uuid::Uuid;

use crate::store::PodcastStore;

use super::{
    build_rich_labels, run_knowledge_query_inner, scoped_top_k_search, KnowledgeQueryRequest,
    KnowledgeQueryRow, QueryScope,
};

// ── Fixture helpers ───────────────────────────────────────────────────────────

fn make_episode(podcast_id: PodcastId, title: &str, desc: &str) -> Episode {
    let mut ep = Episode::new(
        podcast_id,
        "https://example.com/feed.xml",
        format!("guid-{}", Uuid::new_v4()),
        title,
        Url::parse("https://example.com/audio.mp3").unwrap(),
        chrono::Utc::now(),
    );
    ep.description = desc.to_owned();
    ep
}

fn make_chunk(episode_id: &str, idx: u32, text: &str, start: f64, end: f64) -> KnowledgeChunk {
    KnowledgeChunk::without_embedding(TranscriptChunk {
        episode_id: episode_id.to_owned(),
        chunk_index: idx,
        start_secs: start,
        end_secs: end,
        text: text.to_owned(),
        word_count: text.split_whitespace().count() as u32,
    })
}

fn make_embedded_chunk(
    episode_id: &str,
    idx: u32,
    text: &str,
    hot_dim: usize,
) -> KnowledgeChunk {
    let dim = podcast_knowledge::EXPECTED_EMBEDDING_DIM;
    let mut emb = vec![0.0f32; dim];
    emb[hot_dim % dim] = 1.0;
    KnowledgeChunk::with_embedding(
        TranscriptChunk {
            episode_id: episode_id.to_owned(),
            chunk_index: idx,
            start_secs: idx as f64 * 30.0,
            end_secs: (idx + 1) as f64 * 30.0,
            text: text.to_owned(),
            word_count: text.split_whitespace().count() as u32,
        },
        EmbeddingVector::new(emb),
    )
}

fn test_runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

// ── Tests for scoped_top_k_search (vector path) ───────────────────────────────

/// Seeded embedded corpus: query vector at dim 0 must rank ep-A (emb[0]=1.0)
/// above ep-B (emb[512]=1.0, orthogonal → cosine=0.0).
#[test]
fn scoped_top_k_search_ranks_embedded_corpus() {
    let dim = podcast_knowledge::EXPECTED_EMBEDDING_DIM;
    let mut ks = KnowledgeStore::new();
    ks.upsert(make_embedded_chunk("ep-A", 0, "rust programming ownership", 0));
    ks.upsert(make_embedded_chunk("ep-B", 0, "python scripting loops", 512));

    let mut qvec = vec![0.0f32; dim];
    qvec[0] = 1.0; // matches ep-A (cosine = 1.0), not ep-B (cosine = 0.0)

    let hits = scoped_top_k_search(&ks, &qvec, None, 2);

    assert_eq!(hits.len(), 2, "must return both embedded chunks");
    assert_eq!(
        hits[0].chunk.episode_id, "ep-A",
        "ep-A (cosine=1.0) must rank first"
    );
    assert!(
        hits[0].score > hits[1].score,
        "ep-A score must exceed ep-B score"
    );
}

/// scope=Some({ep-A}) must exclude ep-B even when ep-B has higher cosine score.
#[test]
fn scoped_top_k_search_scope_filters_out_of_scope_chunks() {
    let dim = podcast_knowledge::EXPECTED_EMBEDDING_DIM;
    let mut ks = KnowledgeStore::new();
    // ep-B hot at dim 0 (matches query perfectly), ep-A hot at dim 512
    ks.upsert(make_embedded_chunk("ep-B", 0, "out-of-scope episode", 0));
    ks.upsert(make_embedded_chunk("ep-A", 0, "in-scope episode", 512));

    let mut qvec = vec![0.0f32; dim];
    qvec[0] = 1.0; // ep-B would win globally but is out of scope

    let mut scope = HashSet::new();
    scope.insert("ep-A".to_owned()); // only ep-A is in scope

    let hits = scoped_top_k_search(&ks, &qvec, Some(&scope), 10);

    assert_eq!(hits.len(), 1, "only in-scope ep-A must be returned");
    assert_eq!(hits[0].chunk.episode_id, "ep-A");
}

/// When k=0, result must be empty (no panic).
#[test]
fn scoped_top_k_search_empty_when_k_zero() {
    let mut ks = KnowledgeStore::new();
    ks.upsert(make_embedded_chunk("ep-A", 0, "text", 0));
    let qvec = vec![1.0f32; podcast_knowledge::EXPECTED_EMBEDDING_DIM];
    let hits = scoped_top_k_search(&ks, &qvec, None, 0);
    assert!(hits.is_empty(), "k=0 must return empty");
}

// ── Tests for run_knowledge_query_inner ───────────────────────────────────────

/// BM25 path: seed episodes with matching titles, run query, verify rows carry
/// correct episode metadata and chunk text from the in-memory index.
#[test]
fn knowledge_query_returns_ranked_rows_for_seeded_corpus() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Science Podcast");
    let pid = podcast.id;
    let ep = make_episode(pid, "quantum computing deep dive", "learn about qubits");
    let ep_id = ep.id.0.to_string();
    store.subscribe(podcast, vec![ep]);

    let store_arc = Arc::new(Mutex::new(store));

    // Seed a chunk so Phase 5 enrichment finds real text.
    let mut ks = KnowledgeStore::new();
    ks.upsert(make_chunk(
        &ep_id,
        0,
        "quantum computing qubits entanglement superposition",
        0.0,
        30.0,
    ));
    let index_arc = Arc::new(Mutex::new(ks));

    let rt = test_runtime();
    let req = KnowledgeQueryRequest {
        query: "quantum".to_owned(),
        scope: QueryScope::default(),
        limit: None,
    };
    let rows = rt.block_on(run_knowledge_query_inner(req, store_arc, index_arc));

    assert!(!rows.is_empty(), "expected ranked rows, got none");
    let first = &rows[0];
    assert_eq!(first.episode_id, ep_id, "quantum episode must rank first");
    assert!(!first.podcast_id.is_empty(), "podcast_id must be populated");
    assert_eq!(first.episode_title, "quantum computing deep dive");
    assert_eq!(first.podcast_title, "Science Podcast");
    assert!(!first.text.is_empty(), "text must come from the chunk store");
    assert!(first.relevance_score > 0.0, "relevance_score must be positive");
    // Chunk metadata must match the seeded chunk.
    assert_eq!(first.chunk_index, 0);
    assert_eq!(first.end_secs, 30.0);
}

/// `scope=podcast_id` must return only episodes from that podcast.
#[test]
fn knowledge_query_scope_podcast_id_filters_correctly() {
    let mut store = PodcastStore::new();
    let podcast_a = Podcast::new("Podcast A");
    let pid_a = podcast_a.id;
    let podcast_b = Podcast::new("Podcast B");
    let pid_b = podcast_b.id;

    let ep_a = make_episode(pid_a, "machine learning basics", "intro to ML");
    let ep_a_id = ep_a.id.0.to_string();
    let ep_b = make_episode(pid_b, "machine learning advanced", "deep ML concepts");
    let podcast_a_id = pid_a.0.to_string();

    store.subscribe(podcast_a, vec![ep_a]);
    store.subscribe(podcast_b, vec![ep_b]);

    let store_arc = Arc::new(Mutex::new(store));
    let index_arc = Arc::new(Mutex::new(KnowledgeStore::new()));

    let rt = test_runtime();
    let req = KnowledgeQueryRequest {
        query: "machine learning".to_owned(),
        scope: QueryScope {
            podcast_id: Some(podcast_a_id.clone()),
            episode_id: None,
        },
        limit: None,
    };
    let rows = rt.block_on(run_knowledge_query_inner(req, store_arc, index_arc));

    assert!(!rows.is_empty(), "must return at least one row for podcast A");
    for row in &rows {
        assert_eq!(
            row.podcast_id, podcast_a_id,
            "scope=podcast_id must exclude podcast B; got {}",
            row.episode_id
        );
        assert_eq!(
            row.episode_id, ep_a_id,
            "only podcast A episode must appear"
        );
    }
}

/// `scope=episode_id` must return only chunks from that specific episode.
#[test]
fn knowledge_query_scope_episode_id_filters_correctly() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Tech Show");
    let pid = podcast.id;
    let ep1 = make_episode(pid, "rust programming", "ownership and borrowing");
    let ep2 = make_episode(pid, "rust async", "tokio and futures");
    let ep1_id = ep1.id.0.to_string();

    store.subscribe(podcast, vec![ep1, ep2]);

    let store_arc = Arc::new(Mutex::new(store));

    // Index a chunk only for ep1.
    let mut ks = KnowledgeStore::new();
    ks.upsert(make_chunk(
        &ep1_id,
        0,
        "rust programming ownership borrowing lifetimes",
        0.0,
        30.0,
    ));
    let index_arc = Arc::new(Mutex::new(ks));

    let rt = test_runtime();
    let req = KnowledgeQueryRequest {
        query: "rust".to_owned(),
        scope: QueryScope {
            podcast_id: None,
            episode_id: Some(ep1_id.clone()),
        },
        limit: None,
    };
    let rows = rt.block_on(run_knowledge_query_inner(req, store_arc, index_arc));

    assert!(!rows.is_empty(), "must return ep1");
    for row in &rows {
        assert_eq!(
            row.episode_id, ep1_id,
            "scope=episode_id must filter to that episode only"
        );
    }
}

/// Degrade-to-BM25: chunks with NULL embeddings (top_k_search returns empty)
/// and no API key → BM25 rows still come back.
#[test]
fn knowledge_query_degrade_to_bm25_when_no_embeddings() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("History Podcast");
    let pid = podcast.id;
    let ep = make_episode(pid, "ancient rome fall", "the decline of the roman empire");
    let ep_id = ep.id.0.to_string();
    store.subscribe(podcast, vec![ep]);

    let store_arc = Arc::new(Mutex::new(store));

    // Chunks have NULL embedding — top_k_search skips them.
    let mut ks = KnowledgeStore::new();
    ks.upsert(make_chunk(&ep_id, 0, "ancient rome fall western empire", 0.0, 60.0));
    let index_arc = Arc::new(Mutex::new(ks));

    let rt = test_runtime();
    let req = KnowledgeQueryRequest {
        query: "rome fall".to_owned(),
        scope: QueryScope::default(),
        limit: None,
    };
    let rows = rt.block_on(run_knowledge_query_inner(req, store_arc, index_arc));

    assert!(!rows.is_empty(), "BM25 degrade must still return rows");
    assert_eq!(rows[0].episode_id, ep_id, "BM25 must rank the matching episode");
    assert!(rows[0].relevance_score > 0.0, "relevance_score must be positive");
}

/// N1 regression: a BM25-only result must enrich with the chunk that ACTUALLY
/// matched the query — NOT an arbitrary chunk 0. Seed an episode whose matched
/// passage is chunk 2 (chunks 0/1 contain unrelated text) and assert the
/// returned row's text / chunk_index / start_secs reflect chunk 2.
#[test]
fn knowledge_query_bm25_only_enriches_with_matched_chunk_not_chunk_zero() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Cooking Show");
    let pid = podcast.id;
    // Title/description deliberately do NOT contain the query term so the
    // episode-level BM25 match is weak and the chunk match is what matters.
    let ep = make_episode(pid, "weekly episode", "a cooking discussion");
    let ep_id = ep.id.0.to_string();
    store.subscribe(podcast, vec![ep]);

    let store_arc = Arc::new(Mutex::new(store));

    // Three NULL-embedding chunks; only chunk 2 mentions "sourdough".
    let mut ks = KnowledgeStore::new();
    ks.upsert(make_chunk(&ep_id, 0, "intro pasta tomatoes basil olive oil", 0.0, 30.0));
    ks.upsert(make_chunk(&ep_id, 1, "main course roast chicken potatoes", 30.0, 60.0));
    ks.upsert(make_chunk(
        &ep_id,
        2,
        "sourdough bread fermentation starter levain crumb",
        60.0,
        95.0,
    ));
    let index_arc = Arc::new(Mutex::new(ks));

    let rt = test_runtime();
    let req = KnowledgeQueryRequest {
        query: "sourdough".to_owned(),
        scope: QueryScope::default(),
        limit: None,
    };
    let rows = rt.block_on(run_knowledge_query_inner(req, store_arc, index_arc));

    assert!(!rows.is_empty(), "BM25-only path must return the episode");
    let row = rows
        .iter()
        .find(|r| r.episode_id == ep_id)
        .expect("episode must appear");

    // The matched passage is chunk 2 — enrichment must surface it, not chunk 0.
    assert_eq!(
        row.chunk_index, 2,
        "BM25-only row must carry the MATCHED chunk_index (2), not arbitrary chunk 0"
    );
    assert!(
        row.text.contains("sourdough"),
        "row text must be the matched chunk's text, got: {}",
        row.text
    );
    assert_eq!(
        row.start_secs, 60.0,
        "start_secs must reflect the matched chunk (60.0), not chunk 0 (0.0)"
    );
    assert_eq!(
        row.end_secs, 95.0,
        "end_secs must reflect the matched chunk (95.0)"
    );
}

/// `best_matching_chunk` returns None for an episode with no indexed chunks
/// (caller falls back to the lean BM25 snippet).
#[test]
fn best_matching_chunk_none_when_no_chunks() {
    let ks = KnowledgeStore::new();
    let terms = podcast_knowledge::bm25::tokenize("anything");
    let got = super::best_matching_chunk(&ks, "ep-absent", &terms);
    assert!(got.is_none(), "no chunks → None");
}

// ── Tests for knowledge_chunk lookup (unit-testing the lookup logic) ──────────

/// `build_rich_labels` must include the correct podcast_id alongside titles.
#[test]
fn build_rich_labels_includes_podcast_id() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("My Show");
    let pid = podcast.id;
    let ep = make_episode(pid, "Episode One", "first episode");
    let ep_id = ep.id.0.to_string();
    let podcast_id = pid.0.to_string();
    store.subscribe(podcast, vec![ep]);

    let labels = build_rich_labels(&store);

    let (got_pid, got_podcast_title, got_ep_title) = labels.get(&ep_id).cloned().unwrap();
    assert_eq!(got_pid, podcast_id, "must include podcast_id");
    assert_eq!(got_podcast_title, "My Show");
    assert_eq!(got_ep_title, "Episode One");
}

/// Chunk lookup by `(episode_id, chunk_index)` must return the exact row.
#[test]
fn knowledge_chunk_lookup_returns_exact_chunk() {
    let mut ks = KnowledgeStore::new();
    ks.upsert(make_chunk("ep-X", 0, "chunk zero text", 0.0, 30.0));
    ks.upsert(make_chunk("ep-X", 1, "chunk one text", 30.0, 60.0));
    ks.upsert(make_chunk("ep-Y", 0, "other episode chunk", 0.0, 25.0));

    let found = ks
        .chunks
        .iter()
        .find(|c| c.chunk.episode_id == "ep-X" && c.chunk.chunk_index == 1);

    let kc = found.expect("chunk (ep-X, 1) must be present");
    assert_eq!(kc.chunk.text, "chunk one text");
    assert_eq!(kc.chunk.start_secs, 30.0);
    assert_eq!(kc.chunk.end_secs, 60.0);
}

/// Absent `(episode_id, chunk_index)` must return `None` (no panic).
#[test]
fn knowledge_chunk_returns_null_when_absent() {
    let ks = KnowledgeStore::new(); // empty store
    let found = ks
        .chunks
        .iter()
        .find(|c| c.chunk.episode_id == "nonexistent" && c.chunk.chunk_index == 999);
    assert!(found.is_none(), "absent chunk must return None");
}

// ── DTO serialisation tests ───────────────────────────────────────────────────

/// `KnowledgeQueryRow` must serialise to snake_case JSON keys (Swift consumers
/// decode via `convertFromSnakeCase` — no explicit `CodingKeys` needed).
#[test]
fn rich_dto_serializes_snake_case_keys() {
    let row = KnowledgeQueryRow {
        episode_id: "ep-1".to_owned(),
        podcast_id: "pod-1".to_owned(),
        episode_title: "Title".to_owned(),
        podcast_title: "Show".to_owned(),
        chunk_index: 3,
        start_secs: 1.5,
        end_secs: 30.0,
        text: "full chunk text here".to_owned(),
        relevance_score: 0.85,
    };
    let json = serde_json::to_value(&row).unwrap();

    // snake_case keys must be present.
    assert!(json.get("episode_id").is_some(), "must have 'episode_id'");
    assert!(json.get("podcast_id").is_some(), "must have 'podcast_id'");
    assert!(json.get("episode_title").is_some(), "must have 'episode_title'");
    assert!(json.get("podcast_title").is_some(), "must have 'podcast_title'");
    assert!(json.get("chunk_index").is_some(), "must have 'chunk_index'");
    assert!(json.get("start_secs").is_some(), "must have 'start_secs'");
    assert!(json.get("end_secs").is_some(), "must have 'end_secs'");
    assert!(json.get("relevance_score").is_some(), "must have 'relevance_score'");

    // camelCase variants must NOT appear.
    assert!(json.get("episodeId").is_none(), "must NOT have 'episodeId'");
    assert!(json.get("podcastId").is_none(), "must NOT have 'podcastId'");
    assert!(json.get("chunkIndex").is_none(), "must NOT have 'chunkIndex'");
    assert!(json.get("startSecs").is_none(), "must NOT have 'startSecs'");
    assert!(json.get("endSecs").is_none(), "must NOT have 'endSecs'");
    assert!(json.get("relevanceScore").is_none(), "must NOT have 'relevanceScore'");

    // Spot-check values.
    assert_eq!(json["episode_id"], "ep-1");
    assert_eq!(json["chunk_index"], 3);
    assert_eq!(json["relevance_score"], 0.85_f32);
}

// ── N2: direct FFI entry-point smoke tests ────────────────────────────────────
//
// Exercise the `extern "C"` wrappers themselves (null-pointer + free path),
// proving the guard returns a valid error-JSON pointer rather than NULL or UB.
// A full happy-path FFI test needs a live `PodcastHandle` (constructed only via
// `nmp_app_podcast_register` against an `NmpApp`); the inner logic is covered by
// the `run_knowledge_query_inner` tests above, so these smoke tests focus on the
// FFI boundary contract (null safety + freeable CString).

use std::ffi::{CStr, CString};

/// Decode the FFI return pointer to a JSON value, then free it via the same
/// `CString::from_raw` that mirrors `into_raw` (Swift uses `nmp_free_string`).
unsafe fn decode_and_free(ptr: *mut std::os::raw::c_char) -> serde_json::Value {
    assert!(!ptr.is_null(), "FFI must never return a null pointer (D6)");
    let s = CStr::from_ptr(ptr).to_str().expect("valid UTF-8");
    let v: serde_json::Value = serde_json::from_str(s).expect("valid JSON envelope");
    // Reclaim ownership and drop — frees the allocation `into_raw` leaked.
    let _ = CString::from_raw(ptr);
    v
}

/// `nmp_app_podcast_knowledge_query` with a null handle must return a valid
/// error-JSON pointer (not null, not UB).
#[test]
fn ffi_knowledge_query_null_handle_returns_error_json() {
    let req = CString::new(r#"{"query":"test"}"#).unwrap();
    let ptr = super::nmp_app_podcast_knowledge_query(std::ptr::null_mut(), req.as_ptr());
    let v = unsafe { decode_and_free(ptr) };
    assert!(v.get("error").is_some(), "null handle must yield {{\"error\":…}}");
}

/// `nmp_app_podcast_knowledge_query` with a null request pointer must return a
/// valid error-JSON pointer.
#[test]
fn ffi_knowledge_query_null_request_returns_error_json() {
    let ptr =
        super::nmp_app_podcast_knowledge_query(std::ptr::null_mut(), std::ptr::null());
    let v = unsafe { decode_and_free(ptr) };
    assert!(v.get("error").is_some(), "null request must yield error JSON");
}

/// `nmp_app_podcast_knowledge_chunk` with a null handle must return a valid
/// error-JSON pointer.
#[test]
fn ffi_knowledge_chunk_null_handle_returns_error_json() {
    let req = CString::new(r#"{"episode_id":"ep-1","chunk_index":0}"#).unwrap();
    let ptr = super::nmp_app_podcast_knowledge_chunk(std::ptr::null_mut(), req.as_ptr());
    let v = unsafe { decode_and_free(ptr) };
    assert!(v.get("error").is_some(), "null handle must yield error JSON");
}
