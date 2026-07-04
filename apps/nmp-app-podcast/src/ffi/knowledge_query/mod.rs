//! `nmp_app_podcast_knowledge_query` / `nmp_app_podcast_knowledge_similar_episode`
//! / `nmp_app_podcast_knowledge_chunk` — synchronous kernel RAG query surface
//! (slice 5b).
//!
//! `block_on` FFI functions returning inline JSON. Distinct from the
//! reactive `KnowledgeAction::Search` which stages results into the
//! `PodcastUpdate` projection — these are request/response (synchronous, no
//! domain bump, no store mutation) intended for agent (5d) and wiki (5e).
//!
//! ## Threading
//!
//! Both FFIs BLOCK the calling thread via `block_on`. Call from a Swift
//! `async` detached Task or background thread — NEVER the kernel actor thread.

mod helpers;
mod queries;
mod types;

pub use types::{HomeRelatedRow, KnowledgeQueryRow};

// Production imports used by the 4 extern "C" fns below.
use helpers::{build_rich_labels, err_json, ok_json};
use queries::{run_home_related_inner, run_knowledge_query_inner, run_similar_episode_inner};
use types::{
    HomeRelatedRequest, KnowledgeChunkRequest, KnowledgeQueryRequest, SimilarEpisodeRequest,
};

// Private re-exports consumed only by the test child module; Rust allows child
// modules to access private items defined or imported in their parent.
#[cfg(test)]
use helpers::{best_matching_chunk, scoped_top_k_search};
#[cfg(test)]
use types::QueryScope;

use std::ffi::{c_char, CStr};
use std::sync::Arc;

use crate::ffi::guard::ffi_guard;
use crate::ffi::handle::PodcastHandle;

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
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub fn nmp_app_podcast_knowledge_query(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    let handle = if handle.is_null() {
        None
    } else {
        // SAFETY: caller guarantees `handle` is a valid podcast handle.
        Some(unsafe { &*handle })
    };
    let request_json = match unsafe { request_json.as_ref() } {
        Some(_) => unsafe { CStr::from_ptr(request_json) }.to_str().ok(),
        None => None,
    };
    into_raw_json(knowledge_query_json(handle, request_json))
}

pub(crate) fn knowledge_query_json(
    handle: Option<&PodcastHandle>,
    request_json: Option<&str>,
) -> String {
    let Some(handle) = handle else {
        return error_json("null argument");
    };
    let Some(json_str) = request_json else {
        return error_json("null argument");
    };
    ffi_guard(
        "nmp_app_podcast_knowledge_query",
        || error_json("panic"),
        || {
            let req: KnowledgeQueryRequest = match serde_json::from_str(json_str) {
                Ok(r) => r,
                Err(e) => return error_json(&format!("JSON parse: {e}")),
            };
            let store_arc = Arc::clone(&handle.state.library.store);
            let index_arc = handle.state.knowledge.index_arc();
            let runtime = Arc::clone(&handle.state.infra.runtime);
            let rows = runtime.block_on(run_knowledge_query_inner(req, store_arc, index_arc));
            serde_json::json!({ "result": rows }).to_string()
        },
    )
}

/// Synchronous similar-episode lookup.
///
/// Rust owns the seed-query policy: resolve the seed episode from the store,
/// derive search text from title + description excerpt, run the shared hybrid
/// RAG path, and remove the seed episode from returned rows.
///
/// # Request JSON
///
/// ```json
/// {"episode_id":"…","limit":10}
/// ```
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub fn nmp_app_podcast_knowledge_similar_episode(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return err_json("null argument").into_raw();
    }
    ffi_guard(
        "nmp_app_podcast_knowledge_similar_episode",
        || err_json("panic").into_raw(),
        || {
            let json_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return err_json("invalid UTF-8").into_raw(),
            };
            let req: SimilarEpisodeRequest = match serde_json::from_str(json_str) {
                Ok(r) => r,
                Err(e) => return err_json(&format!("JSON parse: {e}")).into_raw(),
            };
            let h = unsafe { &*handle };
            let store_arc = Arc::clone(&h.state.library.store);
            let index_arc = h.state.knowledge.index_arc();
            let runtime = Arc::clone(&h.state.infra.runtime);
            let rows = runtime.block_on(run_similar_episode_inner(req, store_arc, index_arc));
            ok_json(&serde_json::json!({ "result": rows })).into_raw()
        },
    )
}

/// Home's "Related" sheet projection.
///
/// Rust owns the product policy: seed-query construction, topic-vs-source
/// lens limits, seed filtering, one-row-per-show collapse for the topic lens,
/// and the category fallback when the transcript index is empty.
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub fn nmp_app_podcast_knowledge_home_related(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return err_json("null argument").into_raw();
    }
    ffi_guard(
        "nmp_app_podcast_knowledge_home_related",
        || err_json("panic").into_raw(),
        || {
            let json_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return err_json("invalid UTF-8").into_raw(),
            };
            let req: HomeRelatedRequest = match serde_json::from_str(json_str) {
                Ok(r) => r,
                Err(e) => return err_json(&format!("JSON parse: {e}")).into_raw(),
            };
            let h = unsafe { &*handle };
            let store_arc = Arc::clone(&h.state.library.store);
            let index_arc = h.state.knowledge.index_arc();
            let runtime = Arc::clone(&h.state.infra.runtime);
            let categories = h.state.categories.categories_snapshot();
            let rows = runtime.block_on(run_home_related_inner(
                req, store_arc, index_arc, categories,
            ));
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
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub fn nmp_app_podcast_knowledge_chunk(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    let handle = if handle.is_null() {
        None
    } else {
        // SAFETY: caller guarantees `handle` is a valid podcast handle.
        Some(unsafe { &*handle })
    };
    let request_json = match unsafe { request_json.as_ref() } {
        Some(_) => unsafe { CStr::from_ptr(request_json) }.to_str().ok(),
        None => None,
    };
    into_raw_json(knowledge_chunk_json(handle, request_json))
}

pub(crate) fn knowledge_chunk_json(
    handle: Option<&PodcastHandle>,
    request_json: Option<&str>,
) -> String {
    let Some(handle) = handle else {
        return error_json("null argument");
    };
    let Some(json_str) = request_json else {
        return error_json("null argument");
    };
    ffi_guard(
        "nmp_app_podcast_knowledge_chunk",
        || error_json("panic"),
        || {
            let req: KnowledgeChunkRequest = match serde_json::from_str(json_str) {
                Ok(r) => r,
                Err(e) => return error_json(&format!("JSON parse: {e}")),
            };
            let store_arc = Arc::clone(&handle.state.library.store);
            let index_arc = handle.state.knowledge.index_arc();

            let labels = match store_arc.lock() {
                Ok(s) => build_rich_labels(&s),
                Err(_) => return error_json("store poisoned"),
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
                Err(_) => return error_json("knowledge_store poisoned"),
            };

            serde_json::json!({ "result": row }).to_string()
        },
    )
}

fn error_json(reason: &str) -> String {
    serde_json::json!({ "error": reason }).to_string()
}

fn into_raw_json(json: String) -> *mut c_char {
    std::ffi::CString::new(json)
        .unwrap_or_else(|_| err_json("encoding"))
        .into_raw()
}

#[cfg(test)]
#[path = "../knowledge_query_tests.rs"]
mod tests;
