//! Execution-driven tests for the semantic-search spawn body.
//!
//! `Infra::for_test` builds a `new_current_thread` tokio runtime that is never
//! driven by the bare `spawn` path in unit tests, so a spawned task body would
//! never run. These tests call the extracted `spawn_semantic_search_inner`
//! async fn via `runtime.block_on(...)` to genuinely exercise each degrade
//! path: assert no panic, BM25 results untouched, and the second-bump return
//! flag matches the design.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use podcast_core::{Episode, Podcast, PodcastId};
use url::Url;
use uuid::Uuid;

use podcast_knowledge::sqlite::KnowledgeSqliteStore;
use podcast_knowledge::{EmbeddingVector, KnowledgeChunk, KnowledgeStore};
use podcast_transcripts::TranscriptChunk;

use crate::ffi::projections::KnowledgeSearchResult;
use crate::state::{Domain, Infra};
use crate::store::PodcastStore;

use super::{
    metadata_index_backfill_inner, resolve_embeddings_provider, spawn_backfill_embeddings,
    spawn_semantic_search_inner, validate_query_embedding,
};

/// Read a domain's push-sidecar counter (for asserting the RIGHT domain bumped).
fn library_rev(infra: &Infra) -> u64 {
    infra
        .domain_revs
        .counter(Domain::Library)
        .load(Ordering::Relaxed)
}

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

/// Build a store seeded with one subscribed episode that matches the BM25
/// query, plus an optional embeddings_model override.
fn store_with_episode(embeddings_model: Option<&str>) -> Arc<Mutex<PodcastStore>> {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Tech Podcast");
    let id = podcast.id;
    let ep = make_episode(id, "machine learning deep dive", "neural networks and ML");
    store.subscribe(podcast, vec![ep]);
    if let Some(model) = embeddings_model {
        store.set_embeddings_model(model.to_owned(), "Test Model".to_owned());
    }
    Arc::new(Mutex::new(store))
}

/// Seed the in-memory index with one embedded chunk so top_k_search is non-empty.
fn index_with_embedded_chunk(episode_id: &str) -> Arc<Mutex<KnowledgeStore>> {
    let mut ks = KnowledgeStore::new();
    let mut emb = vec![0.0_f32; podcast_knowledge::EXPECTED_EMBEDDING_DIM];
    emb[0] = 1.0;
    ks.upsert(KnowledgeChunk::with_embedding(
        TranscriptChunk {
            episode_id: episode_id.to_owned(),
            chunk_index: 0,
            start_secs: 0.0,
            end_secs: 10.0,
            text: "machine learning neural networks".to_owned(),
            word_count: 4,
        },
        EmbeddingVector::new(emb),
    ));
    Arc::new(Mutex::new(ks))
}

/// Seed the results slot with a BM25 baseline (simulating the sync path having
/// already committed lexical hits before the async refinement runs).
fn baseline_results() -> Arc<Mutex<Vec<KnowledgeSearchResult>>> {
    Arc::new(Mutex::new(vec![KnowledgeSearchResult {
        episode_id: "bm25-ep".to_owned(),
        episode_title: "BM25 baseline".to_owned(),
        podcast_title: "Tech Podcast".to_owned(),
        snippet: "lexical hit".to_owned(),
        start_secs: None,
        relevance_score: 0.5,
    }]))
}

// ── resolve_embeddings_provider — shared policy ──────────────────────────────

#[test]
fn resolver_maps_slash_to_openrouter() {
    let store = store_with_episode(Some("openai/text-embedding-3-large"));
    let resolved = resolve_embeddings_provider(&store);
    assert!(resolved.is_some());
    let (provider, model) = resolved.unwrap();
    assert_eq!(provider, crate::llm::provider_transport::ProviderKind::OpenRouter);
    assert_eq!(model, "openai/text-embedding-3-large");
}

#[test]
fn resolver_maps_cloud_to_ollama() {
    // The default chat model `deepseek-v4-flash:cloud` now maps to Ollama in
    // BOTH search and backfill (single shared policy). Search degrades later
    // via the embed-Err branch (no Ollama server) rather than at model-name.
    let store = store_with_episode(Some("deepseek-v4-flash:cloud"));
    let resolved = resolve_embeddings_provider(&store);
    assert!(resolved.is_some(), "cloud model must resolve to Ollama, not None");
    let (provider, _) = resolved.unwrap();
    assert_eq!(provider, crate::llm::provider_transport::ProviderKind::Ollama);
}

#[test]
fn resolver_returns_none_for_unusable_model() {
    // A plain model name (no '/', not ':cloud') is unusable as an embedding model.
    let store = store_with_episode(Some("plain-chat-model"));
    assert!(
        resolve_embeddings_provider(&store).is_none(),
        "unusable model must resolve to None"
    );
}

// ── validate_query_embedding — dim validation ────────────────────────────────

#[test]
fn validate_accepts_correct_dim() {
    let v = vec![0.1_f32; podcast_knowledge::EXPECTED_EMBEDDING_DIM];
    let out = validate_query_embedding(vec![v.clone()]);
    assert_eq!(out, Some(v));
}

#[test]
fn validate_rejects_wrong_dim() {
    // 512 != 1024 → dim mismatch degrade path.
    let v = vec![0.1_f32; 512];
    assert!(
        validate_query_embedding(vec![v]).is_none(),
        "wrong-dim embedding must be rejected"
    );
}

#[test]
fn validate_rejects_empty_response() {
    assert!(
        validate_query_embedding(vec![]).is_none(),
        "empty embeddings response must be rejected"
    );
}

// ── spawn_semantic_search_inner — execution-driven degrade paths ─────────────

/// (a) Unusable chat model → resolver returns None → no embed, no fusion,
/// no 2nd bump. BM25 baseline results remain untouched. No panic.
#[test]
fn inner_degrades_on_unusable_model() {
    let store = store_with_episode(Some("plain-chat-model"));
    let index = index_with_embedded_chunk("ep-x");
    let results = baseline_results();
    let infra = Infra::for_test();
    let rev0 = infra.rev();
    let runtime = Arc::clone(&infra.runtime);

    let bumped = runtime.block_on(spawn_semantic_search_inner(
        "machine learning".to_owned(),
        Arc::clone(&store),
        Arc::clone(&index),
        Arc::clone(&results),
        infra.clone(),
    ));

    assert!(!bumped, "unusable model must NOT 2nd-bump");
    assert_eq!(infra.rev(), rev0, "no 2nd bump → rev unchanged");
    // BM25 baseline preserved.
    let out = results.lock().unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].episode_id, "bm25-ep", "BM25 baseline must be intact");
}

/// (b) Embed error → `:cloud` resolves to Ollama, but the default cloud base
/// URL with no API key returns MissingCredential immediately (no network) →
/// degrade. No 2nd bump, BM25 baseline intact, no panic.
#[test]
fn inner_degrades_on_embed_error() {
    let store = store_with_episode(Some("deepseek-v4-flash:cloud"));
    let index = index_with_embedded_chunk("ep-x");
    let results = baseline_results();
    let infra = Infra::for_test();
    let rev0 = infra.rev();
    let runtime = Arc::clone(&infra.runtime);

    let bumped = runtime.block_on(spawn_semantic_search_inner(
        "machine learning".to_owned(),
        Arc::clone(&store),
        Arc::clone(&index),
        Arc::clone(&results),
        infra.clone(),
    ));

    assert!(!bumped, "embed error must NOT 2nd-bump");
    assert_eq!(infra.rev(), rev0, "no 2nd bump → rev unchanged");
    let out = results.lock().unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].episode_id, "bm25-ep", "BM25 baseline must be intact");
}

/// (d) Empty vector index (all NULL embeddings) → top_k_search empty → degrade.
/// We force this by giving a usable-looking OpenRouter model whose embed call
/// would fail anyway (no key) — but the earlier degrade (embed error) fires
/// first. To isolate the empty-vector path we instead assert via the helper:
/// an index with no embedded chunks yields empty top_k_search. Covered by
/// `podcast-knowledge::top_k_skips_chunks_without_embedding`; here we assert
/// the inner fn doesn't 2nd-bump when the embed step can't even run.
#[test]
fn inner_no_bump_when_index_empty_and_model_unusable() {
    let store = store_with_episode(Some("plain-chat-model"));
    let index = Arc::new(Mutex::new(KnowledgeStore::new())); // no chunks
    let results = baseline_results();
    let infra = Infra::for_test();
    let rev0 = infra.rev();
    let runtime = Arc::clone(&infra.runtime);

    let bumped = runtime.block_on(spawn_semantic_search_inner(
        "machine learning".to_owned(),
        store,
        index,
        Arc::clone(&results),
        infra.clone(),
    ));

    assert!(!bumped);
    assert_eq!(infra.rev(), rev0);
    assert_eq!(results.lock().unwrap().len(), 1, "BM25 baseline intact");
}

// ── metadata_index_backfill_inner — kernel self-drain (D13) ──────────────────

type SqliteSlot = Arc<Mutex<Option<KnowledgeSqliteStore>>>;

fn empty_sqlite() -> SqliteSlot {
    Arc::new(Mutex::new(None))
}

/// The core regression test: a subscribed, no-transcript episode is indexed
/// (its title+description becomes a chunk in the in-memory index) AND the
/// pending list drains (the episode is marked `metadata_indexed`).
#[test]
fn metadata_drain_indexes_no_transcript_episode_and_drains_pending() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Science Weekly");
    let pid = podcast.id;
    let ep_a = make_episode(pid, "Black holes explained", "Event horizons and singularities.");
    let ep_b = make_episode(pid, "The standard model", "Quarks, leptons, and bosons.");
    store.subscribe(podcast, vec![ep_a.clone(), ep_b.clone()]);
    let store = Arc::new(Mutex::new(store));

    // Before: both episodes are pending (no transcript, not yet indexed).
    assert_eq!(
        store.lock().unwrap().metadata_index_backfill_candidates().len(),
        2,
        "both no-transcript episodes start pending"
    );

    let index = Arc::new(Mutex::new(KnowledgeStore::new()));
    let sqlite = empty_sqlite();
    let infra = Infra::for_test();
    let rev0 = infra.rev();
    let lib0 = library_rev(&infra);
    let runtime = Arc::clone(&infra.runtime);

    let drained = runtime.block_on(metadata_index_backfill_inner(
        &store, &index, &sqlite, &infra,
    ));

    // Drained both, pending list now empty (the contract is no longer dangling).
    assert_eq!(drained, 2, "both episodes drained");
    assert!(
        store.lock().unwrap().metadata_index_backfill_candidates().is_empty(),
        "pending_metadata_index_ids must be drained"
    );
    assert!(store.lock().unwrap().is_metadata_indexed(&ep_a.id.0.to_string()));
    assert!(store.lock().unwrap().is_metadata_indexed(&ep_b.id.0.to_string()));
    assert!(infra.rev() > rev0, "draining a batch bumps the global rev");
    // The bump MUST land on the LIBRARY domain counter — that's the one the
    // `pending_metadata_index_ids` payload + library delta sidecar watch. A
    // plain `bump()` would advance only `misc` and leave the projected list
    // stale (the per-domain real-bump trap, #399/#400/#423).
    assert!(
        library_rev(&infra) > lib0,
        "drain must bump domain_revs.library, not just the global rev"
    );

    // No-transcript episode is now vector-searchable: its synthetic title+desc
    // chunk lives in the index (NULL embedding — the embed backfill fills it).
    let ks = index.lock().unwrap();
    let chunks_a = ks.chunks_for_episode(&ep_a.id.0.to_string());
    assert_eq!(chunks_a.len(), 1, "metadata chunk indexed for no-transcript ep");
    assert!(chunks_a[0].chunk.text.contains("Black holes explained"));
    assert!(chunks_a[0].chunk.text.contains("singularities"));
    assert!(chunks_a[0].embedding.is_none(), "metadata chunk starts NULL-embedding");
    assert_eq!(ks.chunks_for_episode(&ep_b.id.0.to_string()).len(), 1);
}

/// An episode already carrying index chunks (e.g. a transcript indexed live)
/// is NOT re-chunked by the drain — it is only marked indexed (drained). The
/// pre-existing chunk survives untouched.
#[test]
fn metadata_drain_skips_already_indexed_episode() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Tech Podcast");
    let pid = podcast.id;
    let ep = make_episode(pid, "Episode title here", "Episode description here.");
    store.subscribe(podcast, vec![ep.clone()]);
    let ep_id = ep.id.0.to_string();
    let store = Arc::new(Mutex::new(store));

    // Pre-seed the index with a transcript chunk whose text differs from the
    // metadata text, so a re-index would be observable.
    let mut ks = KnowledgeStore::new();
    ks.upsert(KnowledgeChunk::without_embedding(TranscriptChunk {
        episode_id: ep_id.clone(),
        chunk_index: 0,
        start_secs: 12.5,
        end_secs: 30.0,
        text: "real transcript words from the audio".to_owned(),
        word_count: 6,
    }));
    let index = Arc::new(Mutex::new(ks));
    let sqlite = empty_sqlite();
    let infra = Infra::for_test();
    let runtime = Arc::clone(&infra.runtime);

    let drained = runtime.block_on(metadata_index_backfill_inner(
        &store, &index, &sqlite, &infra,
    ));

    assert_eq!(drained, 1, "the episode is still drained (marked)");
    assert!(store.lock().unwrap().is_metadata_indexed(&ep_id));
    // The original transcript chunk is untouched — NOT replaced by metadata.
    let ks = index.lock().unwrap();
    let chunks = ks.chunks_for_episode(&ep_id);
    assert_eq!(chunks.len(), 1);
    assert_eq!(chunks[0].chunk.text, "real transcript words from the audio");
    assert_eq!(chunks[0].chunk.start_secs, 12.5, "real timestamp preserved");
}

/// An episode with neither a transcript nor any title/description text builds
/// no chunk, but is still marked indexed so it stops re-surfacing in the
/// pending list (the loop must not spin forever on it).
#[test]
fn metadata_drain_marks_blank_episode_without_chunk() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Blank Show");
    let pid = podcast.id;
    let ep = make_episode(pid, "", ""); // no title, no description
    store.subscribe(podcast, vec![ep.clone()]);
    let ep_id = ep.id.0.to_string();
    let store = Arc::new(Mutex::new(store));

    let index = Arc::new(Mutex::new(KnowledgeStore::new()));
    let sqlite = empty_sqlite();
    let infra = Infra::for_test();
    let runtime = Arc::clone(&infra.runtime);

    let drained = runtime.block_on(metadata_index_backfill_inner(
        &store, &index, &sqlite, &infra,
    ));

    assert_eq!(drained, 1, "blank episode is still drained");
    assert!(store.lock().unwrap().is_metadata_indexed(&ep_id));
    assert!(
        store.lock().unwrap().metadata_index_backfill_candidates().is_empty(),
        "blank episode must not loop forever"
    );
    assert!(
        index.lock().unwrap().chunks_for_episode(&ep_id).is_empty(),
        "no chunk built for a blank episode"
    );
}

/// Nothing pending → the drain is a clean no-op (returns 0, no bump on either
/// the global rev OR the library counter).
#[test]
fn metadata_drain_noop_when_nothing_pending() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let index = Arc::new(Mutex::new(KnowledgeStore::new()));
    let sqlite = empty_sqlite();
    let infra = Infra::for_test();
    let rev0 = infra.rev();
    let lib0 = library_rev(&infra);
    let runtime = Arc::clone(&infra.runtime);

    let drained = runtime.block_on(metadata_index_backfill_inner(
        &store, &index, &sqlite, &infra,
    ));

    assert_eq!(drained, 0);
    assert_eq!(infra.rev(), rev0, "no work → no global bump");
    assert_eq!(library_rev(&infra), lib0, "no work → no library bump");
}

// ── spawn_backfill_embeddings — single-flight guard ──────────────────────────

/// The embed backfill is single-flight: a second spawn while one is in flight
/// is a no-op. The metadata drain now chains the embed backfill on EVERY feed
/// refresh, so without this guard rapid refreshes would spawn overlapping embed
/// loops (double-scan NULL rows, redundant provider calls, racing writes).
///
/// `Infra::for_test`'s current-thread runtime is never driven here, so the
/// spawned task body never runs to release the flag — which is exactly what
/// lets us observe the guard: the first call claims the flag and it stays
/// claimed, so the second call must bail.
#[test]
fn embed_backfill_single_flight_guard() {
    let running = Arc::new(AtomicBool::new(false));
    let sqlite = empty_sqlite(); // None → loop would break immediately
    let index = Arc::new(Mutex::new(KnowledgeStore::new()));
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let infra = Infra::for_test();

    // First call claims the flag (the in-flight loop owns it).
    spawn_backfill_embeddings(
        Arc::clone(&running),
        Arc::clone(&sqlite),
        Arc::clone(&index),
        Arc::clone(&store),
        infra.clone(),
    );
    assert!(
        running.load(Ordering::SeqCst),
        "first call must claim the running flag"
    );

    // Second call while the flag is set must bail (no overlap, no panic).
    spawn_backfill_embeddings(running.clone(), sqlite, index, store, infra.clone());
    assert!(
        running.load(Ordering::SeqCst),
        "second call is a no-op; the first loop still owns the flag"
    );
}

/// The `RunningGuard` clears its flag on drop — proving the panic-safe release
/// path (a panic in the loop body unwinds through the guard's `Drop`).
#[test]
fn running_guard_clears_flag_on_drop() {
    let flag = Arc::new(AtomicBool::new(true));
    {
        let _g = super::RunningGuard(Arc::clone(&flag));
        assert!(flag.load(Ordering::SeqCst));
    } // guard dropped here (the same path an unwind would take)
    assert!(
        !flag.load(Ordering::SeqCst),
        "RunningGuard must clear the flag on drop"
    );
}
