//! Async off-actor spawn helpers for `KnowledgeState`.
//!
//! Extracted from `state/knowledge.rs` to keep that file under the 500-line
//! hard limit (AGENTS.md §File Length Limits). Functions here are `pub(super)`
//! so only `KnowledgeState` methods can call them.
//!
//! ## Contract
//!
//! Called AFTER the synchronous BM25 path has already written results and
//! emitted the first `infra.bump()`. This function spawns an off-actor task
//! that:
//!
//! 1. Embeds the query using the configured embeddings model.
//! 2. Runs cosine KNN (`top_k_search`) over the in-memory chunk store.
//! 3. RRF-fuses with a freshly re-collected BM25 set.
//! 4. Overwrites `results` and emits a second `infra.bump()`.
//!
//! Failures at any step degrade gracefully: the first BM25 results remain
//! visible, no second bump is emitted, and no panic occurs.

use std::sync::{Arc, Mutex};

use podcast_knowledge::sqlite::KnowledgeSqliteStore;
use podcast_knowledge::KnowledgeStore;

use crate::ffi::projections::KnowledgeSearchResult;
use crate::llm::provider_transport::ProviderKind;
use crate::state::Infra;
use crate::store::PodcastStore;

use super::warn_unusable_embedding_model_once;

/// Batch size for the embedding backfill scanner (number of NULL rows per iteration).
const EMBED_BACKFILL_BATCH_SIZE: usize = 32;
/// Millisecond delay between backfill batch embed calls to avoid flooding the provider.
const EMBED_BACKFILL_INTER_BATCH_DELAY_MS: u64 = 200;

/// Resolve the embeddings `(provider, model)` from settings — the SINGLE
/// policy used by BOTH the query-embed (search) and backfill paths so they
/// can never diverge.
///
/// Mapping:
/// * `model` containing `/` → OpenRouter (e.g. `openai/text-embedding-3-large`)
/// * `model` ending `:cloud` → Ollama (e.g. a local Ollama cloud-tagged model);
///   degrades safely via the embed-Err branch when no Ollama server is present
/// * anything else → unusable embedding model: `warn_unusable_embedding_model_once`
///   and return `None` (caller degrades to BM25 / halts backfill).
///
/// Returns `None` on poisoned store lock or an unusable model.
fn resolve_embeddings_provider(
    store_c: &Arc<Mutex<PodcastStore>>,
) -> Option<(ProviderKind, String)> {
    let s = store_c.lock().ok()?;
    let model_str = s.embeddings_model().to_owned();
    let provider = if model_str.contains('/') {
        ProviderKind::OpenRouter
    } else if model_str.ends_with(":cloud") {
        ProviderKind::Ollama
    } else {
        warn_unusable_embedding_model_once(&model_str);
        return None;
    };
    Some((provider, model_str))
}

/// Pull the first embedding from a provider response and validate its
/// dimension. Returns `None` (degrade to BM25) when the response is empty or
/// the dimension is not [`podcast_knowledge::EXPECTED_EMBEDDING_DIM`].
///
/// Pure — unit-tested directly so the dim-mismatch / empty-response degrade
/// paths are proven by execution, not inspection.
fn validate_query_embedding(embeddings: Vec<Vec<f32>>) -> Option<Vec<f32>> {
    match embeddings.into_iter().next() {
        Some(v) if v.len() == podcast_knowledge::EXPECTED_EMBEDDING_DIM => Some(v),
        Some(v) => {
            log::warn!(
                "[knowledge] query embed dim mismatch: expected {}, got {}",
                podcast_knowledge::EXPECTED_EMBEDDING_DIM,
                v.len()
            );
            None
        }
        None => {
            log::warn!("[knowledge] query embed returned empty embeddings");
            None
        }
    }
}

/// Spawn the off-actor query-embed + RRF-fusion task.
///
/// All arguments are pre-cloned `Arc`s so the caller can `move` them into
/// the async block without holding any guards.
///
/// # Parameters
///
/// - `query` — trimmed query string.
/// - `store_c` — shared settings + library store.
/// - `index_arc` — shared in-memory chunk store.
/// - `results_arc` — the results `Slot` whose `Arc<Mutex<Vec<...>>>` we write to.
/// - `infra_c` — cloned `Infra` for runtime + second bump.
pub(super) fn spawn_semantic_search(
    query: String,
    store_c: Arc<Mutex<PodcastStore>>,
    index_arc: Arc<Mutex<KnowledgeStore>>,
    results_arc: Arc<Mutex<Vec<KnowledgeSearchResult>>>,
    infra_c: Infra,
) {
    let runtime = Arc::clone(&infra_c.runtime);
    runtime.spawn(async move {
        spawn_semantic_search_inner(query, store_c, index_arc, results_arc, infra_c).await;
    });
}

/// The actual query-embed + RRF-fusion body.
///
/// Extracted from the `spawn` closure so tests can `runtime.block_on(...)` it
/// directly and genuinely exercise the degrade paths (the `Infra::for_test`
/// `new_current_thread` runtime is never driven, so a spawned task body would
/// otherwise never run in a unit test).
///
/// Returns `true` iff a second bump was emitted (fusion completed and
/// overwrote results); `false` on any degrade path. Tests assert on this.
pub(super) async fn spawn_semantic_search_inner(
    query: String,
    store_c: Arc<Mutex<PodcastStore>>,
    index_arc: Arc<Mutex<KnowledgeStore>>,
    results_arc: Arc<Mutex<Vec<KnowledgeSearchResult>>>,
    infra_c: Infra,
) -> bool {
    // Resolve provider + model via the SHARED policy (same as backfill).
    let Some((provider, model)) = resolve_embeddings_provider(&store_c) else {
        return false; // unusable model → degrade to BM25, no 2nd bump
    };

    // Embed the query text (single string → first element of the result).
    let intent = crate::llm::provider_transport::EmbeddingIntent {
        provider,
        model: model.clone(),
        input: vec![query.clone()],
        dimensions: Some(podcast_knowledge::EXPECTED_EMBEDDING_DIM),
    };
    let embed_result =
        match crate::llm::provider_transport::embed(Arc::clone(&store_c), intent).await {
            Ok(r) => r,
            Err(e) => {
                log::warn!("[knowledge] query embed failed: {e}");
                return false; // degrade: keep BM25, no 2nd bump
            }
        };

    // Validate embedding dimension (pure helper — unit-tested directly).
    let Some(query_vec) = validate_query_embedding(embed_result.embeddings) else {
        return false; // degrade: empty or wrong-dim embedding → keep BM25
    };

    // Cosine KNN over-fetch (KNOWLEDGE_SEARCH_TOP_K * 4 candidates).
    let over_k = crate::knowledge::KNOWLEDGE_SEARCH_TOP_K * 4;
    let vector_hits: Vec<podcast_knowledge::SearchResult> = {
        let Ok(ks) = index_arc.lock() else { return false };
        podcast_knowledge::top_k_search(&ks, &query_vec, over_k)
    };

    if vector_hits.is_empty() {
        // All chunks have NULL embedding → degrade to BM25, no 2nd bump.
        return false;
    }

    // Re-collect BM25 baseline for fusion. Over-fetch to TOP_K*4 so a BM25 hit
    // at lexical rank 11–40 the vector list might rescue can enter fusion —
    // matching the vector side's over-fetch (symmetric candidate pools).
    // Labels may have changed since the sync path — that's acceptable.
    let (mut bm25_over, labels_now) = {
        let Ok(s) = store_c.lock() else { return false };
        (
            crate::knowledge::collect_knowledge_matches_n(&s, &query, over_k),
            crate::knowledge::build_episode_labels_pub(&s),
        )
    };
    // Ensure descending BM25 order for consistent RRF rank assignment.
    bm25_over.sort_by(|a, b| {
        b.relevance_score
            .partial_cmp(&a.relevance_score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    // RRF fusion (k=60, mirrors iOS VectorIndex.swift).
    let fused = crate::knowledge_fusion::fuse_rrf(
        bm25_over,
        vector_hits,
        &labels_now,
        crate::knowledge::KNOWLEDGE_SEARCH_TOP_K,
        60.0,
    );

    // Overwrite results with fused set. Drop guard before 2nd bump (§6.2).
    if let Ok(mut out) = results_arc.lock() {
        *out = fused;
        drop(out);
    } else {
        return false;
    }
    // Second bump — real completion site (guards dropped above).
    infra_c.bump();
    true
}

/// Spawn paced backfill embed task for NULL-embedding chunks from prior sessions.
///
/// Off-actor. Loops over NULL rows in batches of [`EMBED_BACKFILL_BATCH_SIZE`],
/// pacing with a 200ms sleep between batches.  Halts on provider error; resumes
/// on the next cold start when `set_data_dir` calls this again.
pub(super) fn spawn_backfill_embeddings(
    sqlite_c: Arc<Mutex<Option<KnowledgeSqliteStore>>>,
    index_c: Arc<Mutex<KnowledgeStore>>,
    store_c: Arc<Mutex<PodcastStore>>,
    infra_c: Infra,
) {
    let runtime = Arc::clone(&infra_c.runtime);
    runtime.spawn(async move {
        // Brief startup delay — let the main cold-load settle first.
        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

        loop {
            // Scan for NULL-embedding rows.
            let null_rows: Vec<(String, i64)> = {
                let Ok(guard) = sqlite_c.lock() else { break };
                match guard.as_ref() {
                    Some(sq) => sq.null_embedding_chunks(EMBED_BACKFILL_BATCH_SIZE),
                    None => break,
                }
            };
            if null_rows.is_empty() {
                break;
            }

            // Resolve provider + model via the SHARED policy (same as search).
            let Some((provider, model)) = resolve_embeddings_provider(&store_c) else {
                break; // unusable model → halt backfill (resumes next cold start)
            };

            // Group by episode — embed all chunks for each episode in one call.
            let mut by_episode: std::collections::HashMap<String, Vec<i64>> =
                std::collections::HashMap::new();
            for (ep_id, chunk_idx) in &null_rows {
                by_episode.entry(ep_id.clone()).or_default().push(*chunk_idx);
            }

            let mut had_error = false;
            for (ep_id, chunk_indices) in &by_episode {
                // Collect texts from in-memory index.
                let texts: Vec<(u32, String)> = {
                    let Ok(ks) = index_c.lock() else {
                        had_error = true;
                        break;
                    };
                    ks.chunks_for_episode(ep_id)
                        .into_iter()
                        .filter(|c| chunk_indices.contains(&(c.chunk.chunk_index as i64)))
                        .map(|c| (c.chunk.chunk_index, c.chunk.text.clone()))
                        .collect()
                };
                if texts.is_empty() {
                    continue;
                }

                let intent = crate::llm::provider_transport::EmbeddingIntent {
                    provider,
                    model: model.clone(),
                    input: texts.iter().map(|(_, t)| t.clone()).collect(),
                    dimensions: Some(podcast_knowledge::EXPECTED_EMBEDDING_DIM),
                };
                let result =
                    match crate::llm::provider_transport::embed(Arc::clone(&store_c), intent).await
                    {
                        Ok(r) => r,
                        Err(e) => {
                            log::warn!(
                                "[knowledge] backfill embed failed for episode {ep_id}: \
                                 {e} — halting"
                            );
                            had_error = true;
                            break;
                        }
                    };

                for ((chunk_index, chunk_text), raw_embedding) in
                    texts.iter().zip(result.embeddings.iter())
                {
                    if raw_embedding.len() != podcast_knowledge::EXPECTED_EMBEDDING_DIM {
                        log::warn!(
                            "[knowledge] backfill {ep_id} chunk {chunk_index}: \
                             dim mismatch ({} != {}) — skipping",
                            raw_embedding.len(),
                            podcast_knowledge::EXPECTED_EMBEDDING_DIM
                        );
                        continue;
                    }
                    let ev = podcast_knowledge::EmbeddingVector::new(raw_embedding.clone());
                    if let Ok(mut ks) = index_c.lock() {
                        ks.attach_embedding(ep_id, *chunk_index, ev.clone());
                    }
                    if let Ok(guard) = sqlite_c.lock() {
                        if let Some(sq) = guard.as_ref() {
                            let _ = sq.upsert_embedding(ep_id, *chunk_index, chunk_text, &ev);
                        }
                    }
                }
                infra_c.bump();
            }

            if had_error {
                break;
            }
            // Pace between batches.
            tokio::time::sleep(tokio::time::Duration::from_millis(
                EMBED_BACKFILL_INTER_BATCH_DELAY_MS,
            ))
            .await;
        }
    });
}

#[cfg(test)]
#[path = "knowledge_search_tests.rs"]
mod tests;
