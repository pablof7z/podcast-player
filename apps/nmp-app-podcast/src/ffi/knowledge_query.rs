//! `nmp_app_podcast_knowledge_query` / `nmp_app_podcast_knowledge_chunk` —
//! synchronous kernel RAG query surface (slice 5b).
//!
//! Two `block_on` FFI functions returning inline JSON. Distinct from the
//! reactive `KnowledgeAction::Search` which stages results into the
//! `PodcastUpdate` projection — these are request/response (synchronous, no
//! domain bump, no store mutation) intended for agent (5d) and wiki (5e).
//!
//! ## Threading
//!
//! Both FFIs BLOCK the calling thread via `block_on`. Call from a Swift
//! `async` detached Task or background thread — NEVER the kernel actor thread.

use std::collections::{HashMap, HashSet};
use std::ffi::{c_char, CStr, CString};
use std::sync::{Arc, Mutex};

use podcast_knowledge::{cosine_similarity, KnowledgeStore, SearchResult};
use serde::{Deserialize, Serialize};

use crate::ffi::guard::ffi_guard;
use crate::ffi::handle::PodcastHandle;
use crate::llm::provider_transport::{EmbeddingIntent, ProviderKind};
use crate::store::PodcastStore;

// ── Rich result DTO ───────────────────────────────────────────────────────────

/// Chunk-level RAG query result row returned by `nmp_app_podcast_knowledge_query`.
///
/// Distinct from the lean [`crate::ffi::projections::KnowledgeSearchResult`]
/// used by the Search-tab projection (per-episode, 200-char snippet). This DTO
/// carries:
/// * Full chunk `text` (no truncation — LLM callers need real context).
/// * `chunk_index` / `end_secs` — exact chunk boundaries for context windowing.
/// * `podcast_id` — so callers can scope follow-up queries without a library scan.
///
/// Serialised with default `serde::Serialize` → snake_case JSON field names.
/// Swift 5d/5e decoders will use `convertFromSnakeCase`; no explicit
/// `CodingKeys` annotation is needed on the Swift side.
#[derive(Debug, Serialize)]
pub struct KnowledgeQueryRow {
    pub episode_id: String,
    pub podcast_id: String,
    pub episode_title: String,
    pub podcast_title: String,
    pub chunk_index: u32,
    pub start_secs: f64,
    pub end_secs: f64,
    /// Full chunk text (no 200-char cap — agent / wiki callers need real LLM context).
    pub text: String,
    /// RRF-fused relevance score or BM25 score on the degrade path.
    pub relevance_score: f32,
}

// ── Input DTOs ────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize, Default)]
struct QueryScope {
    podcast_id: Option<String>,
    episode_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct KnowledgeQueryRequest {
    query: String,
    #[serde(default)]
    scope: QueryScope,
    limit: Option<usize>,
}

#[derive(Debug, Deserialize)]
struct KnowledgeChunkRequest {
    episode_id: String,
    chunk_index: u32,
}

// ── FFI entry points ──────────────────────────────────────────────────────────

/// Synchronous hybrid RAG query: BM25 + optional semantic + RRF fusion.
///
/// # Request JSON
///
/// ```json
/// {"query":"…","scope":{"podcast_id":"…"},"limit":10}
/// ```
///
/// Scope (`scope` field or fields within):
/// - `{"podcast_id":"…"}` — restrict to that podcast's episodes only.
/// - `{"episode_id":"…"}` — restrict to that episode's chunks only.
/// - absent / `{}` — whole library.
///
/// `limit` defaults to 10.
///
/// # Response JSON
///
/// ```json
/// {"result":[{"episode_id":"…","podcast_id":"…","episode_title":"…",
///             "podcast_title":"…","chunk_index":0,"start_secs":0.0,
///             "end_secs":30.0,"text":"…","relevance_score":0.85},...]}
/// ```
///
/// or `{"error":"…"}` on hard failure.
#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_knowledge_query(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return err_json("null argument").into_raw();
    }
    ffi_guard(
        "nmp_app_podcast_knowledge_query",
        || err_json("panic").into_raw(),
        || {
            let json_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return err_json("invalid UTF-8").into_raw(),
            };
            let req: KnowledgeQueryRequest = match serde_json::from_str(json_str) {
                Ok(r) => r,
                Err(e) => return err_json(&format!("JSON parse: {e}")).into_raw(),
            };
            let h = unsafe { &*handle };
            let store_arc = Arc::clone(&h.state.library.store);
            let index_arc = h.state.knowledge.index_arc();
            let runtime = Arc::clone(&h.state.infra.runtime);
            let rows = runtime.block_on(run_knowledge_query_inner(req, store_arc, index_arc));
            ok_json(&serde_json::json!({ "result": rows })).into_raw()
        },
    )
}

/// Synchronous chunk lookup by `(episode_id, chunk_index)`.
///
/// # Request JSON
///
/// ```json
/// {"episode_id":"…","chunk_index":0}
/// ```
///
/// # Response JSON
///
/// `{"result":{…}}` — same shape as one `KnowledgeQueryRow`.
/// `{"result":null}` when the chunk is not in the store.
///
/// # Threading
///
/// Pure in-memory lookup (no network). Still call from a non-actor thread.
#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_knowledge_chunk(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return err_json("null argument").into_raw();
    }
    ffi_guard(
        "nmp_app_podcast_knowledge_chunk",
        || err_json("panic").into_raw(),
        || {
            let json_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return err_json("invalid UTF-8").into_raw(),
            };
            let req: KnowledgeChunkRequest = match serde_json::from_str(json_str) {
                Ok(r) => r,
                Err(e) => return err_json(&format!("JSON parse: {e}")).into_raw(),
            };
            let h = unsafe { &*handle };
            let store_arc = Arc::clone(&h.state.library.store);
            let index_arc = h.state.knowledge.index_arc();

            let labels = match store_arc.lock() {
                Ok(s) => build_rich_labels(&s),
                Err(_) => return err_json("store poisoned").into_raw(),
            };

            let row: Option<KnowledgeQueryRow> = match index_arc.lock() {
                Ok(ks) => ks
                    .chunks
                    .iter()
                    .find(|c| {
                        c.chunk.episode_id == req.episode_id
                            && c.chunk.chunk_index == req.chunk_index
                    })
                    .map(|kc| {
                        let (podcast_id, podcast_title, episode_title) = labels
                            .get(&kc.chunk.episode_id)
                            .cloned()
                            .unwrap_or_default();
                        KnowledgeQueryRow {
                            episode_id: kc.chunk.episode_id.clone(),
                            podcast_id,
                            episode_title,
                            podcast_title,
                            chunk_index: kc.chunk.chunk_index,
                            start_secs: kc.chunk.start_secs,
                            end_secs: kc.chunk.end_secs,
                            text: kc.chunk.text.clone(),
                            relevance_score: 0.0,
                        }
                    }),
                Err(_) => return err_json("knowledge_store poisoned").into_raw(),
            };

            ok_json(&serde_json::json!({ "result": row })).into_raw()
        },
    )
}

// ── Core query logic (async) ──────────────────────────────────────────────────

/// Inner async body for `nmp_app_podcast_knowledge_query`.
///
/// Extracted so tests can `runtime.block_on(...)` it directly without
/// constructing a full `PodcastHandle`.
///
/// ## Algorithm
///
/// 1. Build rich labels (`episode_id → (podcast_id, podcast_title, episode_title)`).
/// 2. Derive the in-scope episode set from `QueryScope` (podcast_id / episode_id / all).
/// 3. BM25 over the library (`collect_knowledge_matches_n`, `over_k = limit*4`),
///    filtered to the scope.
/// 4. Optionally embed the query via the configured provider and run scoped
///    cosine top-K. Degrades silently to BM25-only on: unusable model,
///    missing key, transport error, or dimension mismatch.
/// 5. RRF-fuse (k=60) both lists via `knowledge_fusion::fuse_rrf`.
/// 6. Enrich each result with full chunk text / `chunk_index` / `end_secs`
///    (vector-hit chunk wins; falls back to first indexed chunk for BM25-only).
async fn run_knowledge_query_inner(
    req: KnowledgeQueryRequest,
    store_arc: Arc<Mutex<PodcastStore>>,
    index_arc: Arc<Mutex<KnowledgeStore>>,
) -> Vec<KnowledgeQueryRow> {
    use crate::knowledge::{collect_knowledge_matches_n, KNOWLEDGE_SEARCH_TOP_K};

    let query = req.query.trim().to_owned();
    if query.is_empty() {
        return Vec::new();
    }
    let top_k = req.limit.unwrap_or(KNOWLEDGE_SEARCH_TOP_K);
    let over_k = top_k * 4;

    // ── Phase 1: build labels + scope, collect BM25 (store lock) ────────────
    let (rich_labels, scope_set, lean_labels, mut bm25_rows) = {
        let Ok(s) = store_arc.lock() else {
            return Vec::new();
        };
        let rich = build_rich_labels(&s);
        let scope = scope_set_from(&req.scope, &rich);
        let lean = lean_labels_from(&rich);
        let mut bm25 = collect_knowledge_matches_n(&s, &query, over_k);
        if let Some(ref sc) = scope {
            bm25.retain(|r| sc.contains(&r.episode_id));
        }
        (rich, scope, lean, bm25)
    };
    bm25_rows.sort_by(|a, b| {
        b.relevance_score
            .partial_cmp(&a.relevance_score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    // ── Phase 2: embed query (async — no locks held) ─────────────────────────
    let maybe_qvec = embed_query_for_rag(&store_arc, &query).await;

    // ── Phase 3: scoped cosine top-K + best-chunk map (index lock) ──────────
    let (vector_hits, best_vector_chunk) = {
        let Ok(ks) = index_arc.lock() else {
            // Index-lock failure: return BM25 rows with bare metadata
            return bm25_rows
                .into_iter()
                .take(top_k)
                .map(|lean| bare_row(lean, &rich_labels))
                .collect();
        };
        let hits = match maybe_qvec {
            Some(ref qvec) => scoped_top_k_search(&ks, qvec, scope_set.as_ref(), over_k),
            None => Vec::new(), // degrade
        };
        let mut best: HashMap<String, SearchResult> = HashMap::new();
        for hit in &hits {
            best.entry(hit.chunk.episode_id.clone())
                .or_insert_with(|| hit.clone());
        }
        (hits, best)
    };

    // ── Phase 4: RRF fusion ──────────────────────────────────────────────────
    let fused =
        crate::knowledge_fusion::fuse_rrf(bm25_rows, vector_hits, &lean_labels, top_k, 60.0);

    // ── Phase 5: enrich to rich DTO ─────────────────────────────────────────
    fused
        .into_iter()
        .map(|lean| {
            let (podcast_id, podcast_title, episode_title) =
                rich_labels.get(&lean.episode_id).cloned().unwrap_or_default();

            // Vector-hit chunk carries real chunk_index/end_secs/full text.
            // For BM25-only episodes: look up the first indexed chunk (best-effort).
            let (chunk_index, start_secs, end_secs, text) =
                if let Some(hit) = best_vector_chunk.get(&lean.episode_id) {
                    (
                        hit.chunk.chunk_index,
                        hit.chunk.start_secs,
                        hit.chunk.end_secs,
                        hit.chunk.text.clone(),
                    )
                } else {
                    let maybe_chunk = index_arc
                        .lock()
                        .ok()
                        .and_then(|ks| ks.chunks_for_episode(&lean.episode_id).into_iter().next());
                    maybe_chunk
                        .map(|c| (c.chunk.chunk_index, c.chunk.start_secs, c.chunk.end_secs, c.chunk.text.clone()))
                        .unwrap_or((0, lean.start_secs.unwrap_or(0.0), 0.0, lean.snippet.clone()))
                };

            KnowledgeQueryRow {
                episode_id: lean.episode_id,
                podcast_id,
                episode_title,
                podcast_title,
                chunk_index,
                start_secs,
                end_secs,
                text,
                relevance_score: lean.relevance_score,
            }
        })
        .collect()
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

/// Build `episode_id → (podcast_id, podcast_title, episode_title)`.
///
/// Extension of `crate::knowledge::build_episode_labels_pub` that includes
/// `podcast_id` so the rich DTO can carry it without a second store scan.
pub(crate) fn build_rich_labels(
    store: &PodcastStore,
) -> HashMap<String, (String, String, String)> {
    let mut map = HashMap::new();
    for (podcast, episodes) in store.subscribed_podcasts() {
        let pid = podcast.id.0.to_string();
        for ep in episodes {
            map.insert(
                ep.id.0.to_string(),
                (pid.clone(), podcast.title.clone(), ep.title.clone()),
            );
        }
    }
    map
}

/// Derive the in-scope episode set from a `QueryScope`.
///
/// - `episode_id` set → exactly that one episode.
/// - `podcast_id` set → all episodes whose `podcast_id` matches.
/// - Neither set → `None` (whole library).
fn scope_set_from(
    scope: &QueryScope,
    labels: &HashMap<String, (String, String, String)>,
) -> Option<HashSet<String>> {
    if let Some(ref ep_id) = scope.episode_id {
        return Some(std::iter::once(ep_id.clone()).collect());
    }
    if let Some(ref podcast_id) = scope.podcast_id {
        let set: HashSet<String> = labels
            .iter()
            .filter(|(_, (pid, _, _))| pid == podcast_id)
            .map(|(ep_id, _)| ep_id.clone())
            .collect();
        return Some(set);
    }
    None
}

/// Project rich labels to the lean `(podcast_title, episode_title)` map that
/// [`crate::knowledge_fusion::fuse_rrf`] requires.
fn lean_labels_from(
    rich: &HashMap<String, (String, String, String)>,
) -> HashMap<String, (String, String)> {
    rich.iter()
        .map(|(ep_id, (_, pt, et))| (ep_id.clone(), (pt.clone(), et.clone())))
        .collect()
}

/// Scope-filtered cosine top-K search.
///
/// Iterates only embedded chunks; when `scope` is `Some`, skips chunks whose
/// `episode_id` is not in the set. Avoids cloning the full store for scope
/// filtering — only `SearchResult.chunk` (text metadata, no embedding) is cloned.
pub(crate) fn scoped_top_k_search(
    store: &KnowledgeStore,
    query_embedding: &[f32],
    scope: Option<&HashSet<String>>,
    k: usize,
) -> Vec<SearchResult> {
    if k == 0 || query_embedding.is_empty() {
        return Vec::new();
    }
    let mut scored: Vec<SearchResult> = store
        .embedded()
        .filter(|(kc, _)| scope.map_or(true, |s| s.contains(&kc.chunk.episode_id)))
        .map(|(kc, emb)| SearchResult {
            chunk: kc.chunk.clone(),
            score: cosine_similarity(emb.as_slice(), query_embedding),
        })
        .collect();
    scored.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    scored.truncate(k);
    scored
}

/// Embed a query string using the configured provider.
///
/// Mirrors the degrade policy in `crate::state::knowledge_search` — returns
/// `None` on unusable model, missing key, transport error, or dim mismatch.
/// Never panics; the caller degrades to BM25-only when `None` is returned.
async fn embed_query_for_rag(
    store_arc: &Arc<Mutex<PodcastStore>>,
    query: &str,
) -> Option<Vec<f32>> {
    let (provider, model) = {
        let s = store_arc.lock().ok()?;
        let model_str = s.embeddings_model().to_owned();
        let prov = if model_str.contains('/') {
            ProviderKind::OpenRouter
        } else if model_str.ends_with(":cloud") {
            ProviderKind::Ollama
        } else {
            return None; // unusable model → degrade to BM25
        };
        (prov, model_str)
    };
    let intent = EmbeddingIntent {
        provider,
        model: model.clone(),
        input: vec![query.to_owned()],
        dimensions: Some(podcast_knowledge::EXPECTED_EMBEDDING_DIM),
    };
    match crate::llm::provider_transport::embed(Arc::clone(store_arc), intent).await {
        Ok(r) => match r.embeddings.into_iter().next() {
            Some(v) if v.len() == podcast_knowledge::EXPECTED_EMBEDDING_DIM => Some(v),
            _ => None,
        },
        Err(_) => None,
    }
}

/// Build a bare `KnowledgeQueryRow` from a lean BM25 result (no chunk lookup).
/// Used on the index-lock-failure error path.
fn bare_row(
    lean: crate::ffi::projections::KnowledgeSearchResult,
    labels: &HashMap<String, (String, String, String)>,
) -> KnowledgeQueryRow {
    let (podcast_id, podcast_title, episode_title) =
        labels.get(&lean.episode_id).cloned().unwrap_or_default();
    KnowledgeQueryRow {
        episode_id: lean.episode_id,
        podcast_id,
        episode_title,
        podcast_title,
        chunk_index: 0,
        start_secs: lean.start_secs.unwrap_or(0.0),
        end_secs: 0.0,
        text: lean.snippet,
        relevance_score: lean.relevance_score,
    }
}

// ── JSON envelope helpers ─────────────────────────────────────────────────────

fn ok_json(value: &serde_json::Value) -> CString {
    CString::new(value.to_string())
        .unwrap_or_else(|_| CString::new(r#"{"error":"encoding"}"#).unwrap())
}

fn err_json(reason: &str) -> CString {
    let json = serde_json::json!({"error": reason}).to_string();
    CString::new(json).unwrap_or_else(|_| CString::new(r#"{"error":"encoding"}"#).unwrap())
}

#[cfg(test)]
#[path = "knowledge_query_tests.rs"]
mod tests;
