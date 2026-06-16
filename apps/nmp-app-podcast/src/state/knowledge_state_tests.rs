//! Tests for `KnowledgeState` — extracted from `state/knowledge.rs` to stay
//! under the 500-line file-length hard limit (AGENTS.md §File Length Limits).

use std::sync::{Arc, Mutex};

use podcast_core::{Episode, Podcast, PodcastId};
use url::Url;
use uuid::Uuid;

use crate::ffi::actions::knowledge_module::KnowledgeAction;
use crate::ffi::projections::KnowledgeSearchResult;
use crate::store::PodcastStore;

use super::KnowledgeState;

fn make_episode(podcast_id: PodcastId, title: &str, description: &str) -> Episode {
    let mut ep = Episode::new(
        podcast_id,
        "https://example.com/feed.xml",
        format!("guid-{}", Uuid::new_v4()),
        title,
        Url::parse("https://example.com/audio.mp3").unwrap(),
        chrono::Utc::now(),
    );
    ep.description = description.to_owned();
    ep
}

fn shared(store: PodcastStore) -> Arc<Mutex<PodcastStore>> {
    Arc::new(Mutex::new(store))
}

#[test]
fn empty_search_clears_results() {
    let state = KnowledgeState::for_test(shared(PodcastStore::new()));
    // Seed some dummy results.
    state.results.lock().unwrap().push(KnowledgeSearchResult {
        episode_id: "ep-1".to_owned(),
        ..Default::default()
    });
    let before = state.infra.rev();
    let out = state.handle(KnowledgeAction::Search {
        query: "  ".to_owned(),
    });
    assert_eq!(out["ok"], true);
    assert!(state.results_snapshot().is_empty());
    assert!(state.infra.rev() > before, "empty search must bump rev");
}

#[test]
fn search_finds_matching_episode() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Tech Talk");
    let id = podcast.id;
    let ep = make_episode(id, "machine learning deep dive", "learn about ML");
    store.subscribe(podcast, vec![ep.clone()]);

    let state = KnowledgeState::for_test(shared(store));
    let out = state.handle(KnowledgeAction::Search {
        query: "machine learning".to_owned(),
    });
    assert_eq!(out["ok"], true);
    let results = state.results_snapshot();
    assert!(!results.is_empty());
    assert_eq!(results[0].episode_id, ep.id.0.to_string());
}

#[test]
fn clear_results_bumps_rev_only_when_nonempty() {
    let state = KnowledgeState::for_test(shared(PodcastStore::new()));
    let rev0 = state.infra.rev();
    // Clear when already empty — no bump.
    let out = state.handle(KnowledgeAction::ClearResults);
    assert_eq!(out["ok"], true);
    assert_eq!(state.infra.rev(), rev0, "clear of empty must NOT bump rev");

    // Seed a result then clear.
    state.results.lock().unwrap().push(KnowledgeSearchResult {
        episode_id: "ep-1".to_owned(),
        ..Default::default()
    });
    let out2 = state.handle(KnowledgeAction::ClearResults);
    assert_eq!(out2["ok"], true);
    assert!(state.infra.rev() > rev0, "clear of non-empty must bump rev");
}

#[test]
fn index_episode_without_transcript_no_error() {
    let state = KnowledgeState::for_test(shared(PodcastStore::new()));
    let out = state.handle(KnowledgeAction::IndexEpisode {
        episode_id: "missing".to_owned(),
    });
    assert_eq!(out["ok"], true);
    assert_eq!(out["status"], "no_transcript");
}

#[test]
fn index_episode_chunks_and_bumps_rev() {
    let mut store = PodcastStore::new();
    let text = (0..300)
        .map(|i| format!("word{i}"))
        .collect::<Vec<_>>()
        .join(" ");
    store.set_transcript("ep-chunked".to_owned(), text);

    let state = KnowledgeState::for_test(shared(store));
    let rev0 = state.infra.rev();
    let out = state.handle(KnowledgeAction::IndexEpisode {
        episode_id: "ep-chunked".to_owned(),
    });
    assert_eq!(out["ok"], true);
    assert_eq!(out["status"], "indexed");
    assert!(out["chunk_count"].as_u64().unwrap() > 0);
    assert!(state.infra.rev() > rev0);
}

/// Verify that indexed chunks survive a simulated restart: index an
/// episode, construct a new `KnowledgeState` (simulating cold start),
/// call `set_data_dir` on the same temp dir, and confirm search returns
/// results without re-indexing.
#[test]
fn knowledge_state_durability_round_trip() {
    let dir = tempfile::tempdir().expect("tempdir");

    // Build a podcast + episode so the label map is populated for
    // chunk-match deduplication (merge_chunk_matches skips chunks whose
    // episode id is absent from the label map).
    let podcast = Podcast::new("Tech Podcast");
    let podcast_id = podcast.id;
    let transcript_text =
        "machine learning neural networks deep dive transcript text".to_owned();
    let ep = make_episode(podcast_id, "ML Episode", "deep dive into ML");
    let episode_id = ep.id.0.to_string();

    let mut store = PodcastStore::new();
    store.subscribe(podcast, vec![ep]);
    store.set_transcript(episode_id.clone(), transcript_text);
    let shared_store = Arc::new(Mutex::new(store));

    // -- Session 1: index the episode
    let state1 = KnowledgeState::for_test(shared_store.clone());
    let loaded = state1.set_data_dir(dir.path());
    // Fresh dir -- nothing pre-loaded yet.
    assert_eq!(loaded, 0, "fresh dir should have 0 pre-loaded chunks");

    let out = state1.handle(KnowledgeAction::IndexEpisode {
        episode_id: episode_id.clone(),
    });
    assert_eq!(out["ok"], true, "index should succeed");
    assert!(out["chunk_count"].as_u64().unwrap() > 0);

    // Verify in-memory search finds the episode in session 1.
    let out_search = state1.handle(KnowledgeAction::Search {
        query: "machine learning".to_owned(),
    });
    assert_eq!(out_search["ok"], true);
    assert!(!state1.results_snapshot().is_empty(), "search1 should have hits");

    // -- Session 2: cold start -- new KnowledgeState, same data dir
    // Drop state1 to release the SQLite connection.
    drop(state1);

    let state2 = KnowledgeState::for_test(shared_store.clone());
    let reloaded = state2.set_data_dir(dir.path());
    assert!(reloaded > 0, "cold start must reload chunks from SQLite (got {reloaded})");

    // Search WITHOUT re-indexing -- chunks must come from disk.
    let out_search2 = state2.handle(KnowledgeAction::Search {
        query: "machine learning".to_owned(),
    });
    assert_eq!(out_search2["ok"], true);
    assert!(
        !state2.results_snapshot().is_empty(),
        "search after cold reload must return hits without re-indexing"
    );
}

/// index_episode writes NULL-embedding chunks synchronously; the in-memory
/// chunks have embedding == None immediately after handle() returns.
#[test]
fn index_episode_chunks_persist_with_null_embedding() {
    let mut store = PodcastStore::new();
    let text = (0..300)
        .map(|i| format!("word{i}"))
        .collect::<Vec<_>>()
        .join(" ");
    store.set_transcript("ep-null-emb".to_owned(), text);

    let state = KnowledgeState::for_test(shared(store));
    let rev0 = state.infra.rev();
    let out = state.handle(KnowledgeAction::IndexEpisode {
        episode_id: "ep-null-emb".to_owned(),
    });
    assert_eq!(out["ok"], true);
    assert_eq!(out["status"], "indexed");

    // Synchronous rev bump must have happened.
    assert!(state.infra.rev() > rev0, "rev must bump synchronously");

    // All in-memory chunks must have NULL embedding (embed is async/off-actor).
    let ks = state.index.lock().unwrap();
    let chunks = ks.chunks_for_episode("ep-null-emb");
    assert!(!chunks.is_empty(), "chunks must be present");
    for c in &chunks {
        assert!(
            c.embedding.is_none(),
            "synchronous path must write NULL embeddings; got Some for chunk {}",
            c.chunk.chunk_index
        );
    }
}

/// backfill_embeddings with no OpenRouter key configured (the default
/// `openai/text-embedding-3-large` routes to OpenRouter but the embed call
/// returns MissingCredential in-test) must terminate gracefully — no panic,
/// no deadlock.
///
/// We verify this indirectly: after set_data_dir the state is usable.
#[test]
fn backfill_picks_up_null_rows_gracefully() {
    let dir = tempfile::tempdir().expect("tempdir");

    // Seed a chunk with NULL embedding directly into SQLite.
    {
        use podcast_knowledge::sqlite::KnowledgeSqliteStore;
        use podcast_knowledge::KnowledgeChunk;
        use podcast_transcripts::TranscriptChunk;

        let db_path = dir.path().join("knowledge.sqlite");
        let sq = KnowledgeSqliteStore::open(&db_path);
        let chunk = KnowledgeChunk::without_embedding(TranscriptChunk {
            episode_id: "ep-backfill".to_owned(),
            chunk_index: 0,
            start_secs: 0.0,
            end_secs: 9.9,
            word_count: 5,
            text: "backfill test chunk".to_owned(),
        });
        sq.replace_episode_chunks("ep-backfill", &[chunk]).unwrap();
    }

    let state = KnowledgeState::for_test(shared(PodcastStore::new()));
    let reloaded = state.set_data_dir(dir.path());
    // The chunk must be cold-loaded.
    assert_eq!(reloaded, 1, "must cold-load the NULL-embedding chunk");
    // State is still usable -- no panic.
    let out = state.handle(KnowledgeAction::ClearResults);
    assert_eq!(out["ok"], true);
}

/// Calling index_episode without an OpenRouter key leaves chunks with NULL
/// embedding and does not panic -- the async embed task fails gracefully.
#[test]
fn embed_wiring_no_op_on_chat_model() {
    let mut store = PodcastStore::new();
    let text = (0..200)
        .map(|i| format!("word{i}"))
        .collect::<Vec<_>>()
        .join(" ");
    store.set_transcript("ep-noop".to_owned(), text);

    let state = KnowledgeState::for_test(shared(store));
    let out = state.handle(KnowledgeAction::IndexEpisode {
        episode_id: "ep-noop".to_owned(),
    });
    assert_eq!(out["ok"], true);

    // In-memory chunks are present (synchronous path ran).
    let ks = state.index.lock().unwrap();
    let chunks = ks.chunks_for_episode("ep-noop");
    assert!(!chunks.is_empty(), "chunks must exist");
    // All NULL embedding -- the async embed fails gracefully (no key in test).
    for c in &chunks {
        assert!(c.embedding.is_none(), "no-op path must leave NULL embedding");
    }
}

/// `search` with the default embedding model writes BM25 results synchronously
/// and emits exactly one rev bump before returning `{"ok":true}`. The spawned
/// async task routes to OpenRouter but (with no key in tests) returns
/// MissingCredential and degrades — BM25 results remain, no second bump.
/// The execution-driven variant lives in `knowledge_search` tests
/// (`degrade_*` via `block_on`); this asserts the synchronous contract.
#[test]
fn search_degrade_on_chat_model_no_panic() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Science Podcast");
    let id = podcast.id;
    let ep = make_episode(id, "quantum computing", "deep dive into quantum");
    store.subscribe(podcast, vec![ep.clone()]);

    let state = KnowledgeState::for_test(shared(store));
    let rev0 = state.infra.rev();

    let out = state.handle(KnowledgeAction::Search {
        query: "quantum".to_owned(),
    });
    assert_eq!(out["ok"], true);

    // BM25 sync bump must have occurred.
    assert!(state.infra.rev() > rev0, "BM25 sync bump must happen");

    // BM25 results must be present immediately (sync path committed them).
    let results = state.results_snapshot();
    assert!(
        !results.is_empty(),
        "BM25 results must be present (chat model degrades to BM25)"
    );
    // No panic — process is still alive.
}

/// `search` returns `{"ok":true}` synchronously (first bump happened before
/// the async spawn starts) — off-actor non-blocking contract.
#[test]
fn search_returns_ok_synchronously() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Tech Show");
    let id = podcast.id;
    let ep = make_episode(id, "async rust", "tokio and async");
    store.subscribe(podcast, vec![ep]);

    let state = KnowledgeState::for_test(shared(store));
    let rev_before = state.infra.rev();

    // Call search — must return without blocking.
    let out = state.handle(KnowledgeAction::Search {
        query: "rust async".to_owned(),
    });

    // The response is `{"ok":true}` and the first bump must have already
    // happened (sync path committed BM25 results before returning).
    assert_eq!(out["ok"], true);
    assert!(
        state.infra.rev() > rev_before,
        "first (BM25) bump must complete before search returns"
    );
}

// ── Slice 5a: timed-chunking tests ───────────────────────────────────────────

/// When `index_episode` is called and the store holds timed transcript entries,
/// the resulting RAG chunks must carry the real `start_secs` / `end_secs`
/// from those entries so transcript-search hits can seek to the right position.
#[test]
fn timed_transcript_produces_chunks_with_real_timestamps() {
    use podcast_transcripts::TranscriptEntry;

    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Timed Show");
    let pid = podcast.id;
    let ep = make_episode(pid, "Episode with timing", "An episode.");
    store.subscribe(podcast, vec![ep.clone()]);

    // Seed two timed entries spanning different time ranges.
    let ep_id = ep.id.0.to_string();
    store.set_timed_transcript(
        ep_id.clone(),
        vec![
            TranscriptEntry {
                start_secs: 10.0,
                end_secs: 20.0,
                text: "first entry text word1 word2 word3".to_owned(),
                speaker: None,
                words: None,
            },
            TranscriptEntry {
                start_secs: 25.0,
                end_secs: 40.0,
                text: "second entry text word4 word5 word6".to_owned(),
                speaker: None,
                words: None,
            },
        ],
    );

    let state = KnowledgeState::for_test(shared(store));
    let out = state.handle(KnowledgeAction::IndexEpisode {
        episode_id: ep_id.clone(),
    });

    assert_eq!(out["ok"], true);
    assert_eq!(out["status"], "indexed");
    let chunk_count = out["chunk_count"].as_u64().unwrap_or(0);
    assert!(chunk_count >= 1, "must produce at least one chunk");

    // Verify chunks have real timestamps via search (the knowledge store is
    // populated after IndexEpisode; searching surfaces the chunks via BM25).
    let search_out = state.handle(KnowledgeAction::Search {
        query: "first entry".to_owned(),
    });
    assert_eq!(search_out["ok"], true);

    let results = state.results_snapshot();
    let hit = results.iter().find(|r| r.episode_id == ep_id);
    assert!(hit.is_some(), "indexed episode must appear in search results");
    // The chunk hit must carry a non-None, non-zero start_secs — proof that
    // the timed chunker was used (legacy plain-text path always produces 0.0).
    let start = hit.unwrap().start_secs;
    assert!(
        start.is_some() && start.unwrap() >= 10.0,
        "chunk start_secs must reflect timed entry (>= 10.0), got {:?}",
        start
    );
}

/// When `index_episode` is called and only plain text was stored (legacy path),
/// the resulting chunks must have start_secs = 0.0 and the call must not panic.
#[test]
fn legacy_plain_text_transcript_produces_chunks_with_zero_start_secs() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Legacy Show");
    let pid = podcast.id;
    let ep = make_episode(pid, "Untimed Episode", "No timing info.");
    store.subscribe(podcast, vec![ep.clone()]);

    let ep_id = ep.id.0.to_string();
    // Store only plain text — no timed entries.
    store.set_transcript(ep_id.clone(), "hello world from the legacy path".to_owned());

    let state = KnowledgeState::for_test(shared(store));
    let out = state.handle(KnowledgeAction::IndexEpisode {
        episode_id: ep_id.clone(),
    });

    assert_eq!(out["ok"], true);
    assert_eq!(out["status"], "indexed");
    let chunk_count = out["chunk_count"].as_u64().unwrap_or(0);
    assert!(chunk_count >= 1, "must produce at least one chunk");

    // Search to verify the chunk was indexed with start_secs = Some(0.0).
    let search_out = state.handle(KnowledgeAction::Search {
        query: "hello".to_owned(),
    });
    assert_eq!(search_out["ok"], true);

    let results = state.results_snapshot();
    let hit = results.iter().find(|r| r.episode_id == ep_id);
    assert!(hit.is_some(), "legacy episode must appear in search results");
    // Plain-text chunker sets start_secs=0.0, projected as Some(0.0).
    assert_eq!(
        hit.unwrap().start_secs,
        Some(0.0),
        "legacy path must produce start_secs = 0.0"
    );
}

/// `index_episode` falls back to indexing the episode's **metadata**
/// (title + description) when no transcript is stored — so no-transcript
/// episodes still get semantic / lexical coverage (parity with the retired
/// Swift `EpisodeMetadataIndexer`). The synthetic chunk carries the title and
/// description text.
#[test]
fn index_episode_with_no_transcript_indexes_metadata() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Empty Show");
    let pid = podcast.id;
    let ep = make_episode(pid, "Quantum computing primer", "A gentle intro to qubits.");
    store.subscribe(podcast, vec![ep.clone()]);

    let state = KnowledgeState::for_test(shared(store));
    let out = state.handle(KnowledgeAction::IndexEpisode {
        episode_id: ep.id.0.to_string(),
    });

    assert_eq!(out["ok"], true);
    assert_eq!(out["status"], "indexed");
    assert_eq!(out["chunk_count"].as_u64().unwrap(), 1);

    // The synthetic metadata chunk carries title + description text.
    let chunks = state.index.lock().unwrap().chunks_for_episode(&ep.id.0.to_string());
    assert_eq!(chunks.len(), 1);
    assert!(chunks[0].chunk.text.contains("Quantum computing primer"));
    assert!(chunks[0].chunk.text.contains("qubits"));
    // No real timestamps for metadata chunks.
    assert_eq!(chunks[0].chunk.start_secs, 0.0);
}

/// `index_episode` still returns `no_transcript` (not an error) for an
/// **unknown** episode — there is genuinely nothing to index.
#[test]
fn index_episode_unknown_episode_returns_no_transcript() {
    let state = KnowledgeState::for_test(shared(PodcastStore::new()));
    let out = state.handle(KnowledgeAction::IndexEpisode {
        episode_id: Uuid::new_v4().to_string(),
    });
    assert_eq!(out["ok"], true);
    assert_eq!(out["status"], "no_transcript");
}
