//! Execution-driven tests for the semantic-search spawn body.
//!
//! `Infra::for_test` builds a `new_current_thread` tokio runtime that is never
//! driven by the bare `spawn` path in unit tests, so a spawned task body would
//! never run. These tests call the extracted `spawn_semantic_search_inner`
//! async fn via `runtime.block_on(...)` to genuinely exercise each degrade
//! path: assert no panic, BM25 results untouched, and the second-bump return
//! flag matches the design.

use std::sync::{Arc, Mutex};

use podcast_core::{Episode, Podcast, PodcastId};
use url::Url;
use uuid::Uuid;

use podcast_knowledge::{EmbeddingVector, KnowledgeChunk, KnowledgeStore};
use podcast_transcripts::TranscriptChunk;

use crate::ffi::projections::KnowledgeSearchResult;
use crate::state::Infra;
use crate::store::PodcastStore;

use super::{
    resolve_embeddings_provider, spawn_semantic_search_inner, validate_query_embedding,
};

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
