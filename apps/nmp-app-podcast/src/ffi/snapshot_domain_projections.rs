//! Per-domain typed projection builders and registration helpers.
//!
//! Each domain owns:
//!  - A serializable payload type (JSON, wrapped in `TypedProjectionData`)
//!  - A `build_<domain>_domain_payload` helper that assembles the payload from the handle
//!  - A `register_<domain>_projection` free function that wires the typed projection
//!    closure into the app via `register_typed_snapshot_projection`
//!
//! ## Delta semantics
//!
//! Each closure maintains a `last_emitted: AtomicU64`. On every tick it reads the
//! domain's `Arc<AtomicU64>` rev:
//!  - If domain rev == last_emitted → return `None` (sidecar omitted from the frame)
//!  - If domain rev > last_emitted  → serialize the payload, update last_emitted, return `Some`
//!
//! This gives true per-domain delta: a playback tick that bumps only `domain_revs.playback`
//! results in a frame carrying only the `podcast.playback` sidecar — the `podcast.library`
//! closure sees no change and returns `None`, so the library sidecar is absent from the frame.
//!
//! ## Decoder contract
//!
//! The payload is a JSON-encoded byte vector wrapped in `TypedProjectionData`.
//! `schema_id` is the projection key (e.g. `"podcast.library"`).
//! `nmp_app_podcast_decode_update_frame` decodes all `podcast.*` sidecars and
//! injects them under `v.projections[key]` in the bridge JSON, so iOS/Android shells
//! can consume them without waiting for the pull path.
//!
//! ## CodingKeys contract (from MEMORY: FFI decode snake_case contract)
//!
//! Types embedded in the domain payloads MUST NOT carry explicit snake_case `CodingKeys`
//! — the bridge decoder uses `convertFromSnakeCase`; explicit CodingKeys override it and
//! cause `keyNotFound` errors that drop the entire frame. All field names must use Rust
//! snake_case and rely on the bridge's automatic conversion.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use nmp_core::TypedProjectionData;

use super::handle::PodcastHandle;
use super::snapshot::build_podcast_update;

// ── Schema IDs ────────────────────────────────────────────────────────────────

pub const SCHEMA_LIBRARY: &str = "podcast.library";
pub const SCHEMA_PLAYBACK: &str = "podcast.playback";
pub const SCHEMA_DOWNLOADS: &str = "podcast.downloads";
pub const SCHEMA_SETTINGS: &str = "podcast.settings";
pub const SCHEMA_IDENTITY: &str = "podcast.identity";
pub const SCHEMA_WIDGET: &str = "podcast.widget";
pub const SCHEMA_MISC: &str = "podcast.misc";

// ── Payload builders ──────────────────────────────────────────────────────────

/// Build the `podcast.library` domain payload from the current handle state.
/// Returns `None` when the library is empty (preserves byte-identical pull-path
/// behaviour for a fresh install).
fn build_library_payload(handle: &PodcastHandle) -> Option<serde_json::Value> {
    let update = build_podcast_update(handle);
    if update.library.is_empty() {
        return None;
    }
    Some(serde_json::json!({
        "rev": update.rev,
        "library": update.library,
        "categories": update.categories,
        "search_results": update.search_results,
        "nostr_results": update.nostr_results,
        "owned_podcasts": update.owned_podcasts,
    }))
}

/// Build the `podcast.playback` domain payload.
fn build_playback_payload(handle: &PodcastHandle) -> serde_json::Value {
    let update = build_podcast_update(handle);
    serde_json::json!({
        "rev": update.rev,
        "now_playing": update.now_playing,
        "queue": update.queue,
        "inbox": update.inbox,
        "inbox_triage_in_progress": update.inbox_triage_in_progress,
    })
}

/// Build the `podcast.downloads` domain payload. Returns `None` when there
/// are no active downloads (D5 — omit rather than send an empty struct).
fn build_downloads_payload(handle: &PodcastHandle) -> Option<serde_json::Value> {
    let update = build_podcast_update(handle);
    update.downloads.map(|d| {
        serde_json::json!({
            "rev": update.rev,
            "downloads": d,
        })
    })
}

/// Build the `podcast.settings` domain payload.
fn build_settings_payload(handle: &PodcastHandle) -> serde_json::Value {
    let update = build_podcast_update(handle);
    serde_json::json!({
        "rev": update.rev,
        "settings": update.settings,
        "configured_relays": update.configured_relays,
    })
}

/// Build the `podcast.identity` domain payload. Returns `None` when no account
/// is active (fresh install / logged-out state).
fn build_identity_payload(handle: &PodcastHandle) -> Option<serde_json::Value> {
    let update = build_podcast_update(handle);
    update.active_account.as_ref()?;
    Some(serde_json::json!({
        "rev": update.rev,
        "active_account": update.active_account,
    }))
}

/// Build the `podcast.widget` domain payload. Returns `None` when the widget
/// has nothing to display (no playback, no unplayed episodes).
fn build_widget_payload(handle: &PodcastHandle) -> Option<serde_json::Value> {
    let update = build_podcast_update(handle);
    update.widget.as_ref()?;
    Some(serde_json::json!({
        "rev": update.rev,
        "widget": update.widget,
    }))
}

/// Build the `podcast.misc` domain payload — the catch-all for everything
/// not covered by a dedicated domain.
fn build_misc_payload(handle: &PodcastHandle) -> serde_json::Value {
    let update = build_podcast_update(handle);
    serde_json::json!({
        "rev": update.rev,
        "wiki_articles": update.wiki_articles,
        "wiki_search_results": update.wiki_search_results,
        "picks": update.picks,
        "agent_tasks": update.agent_tasks,
        "knowledge_search_results": update.knowledge_search_results,
        "memory_facts": update.memory_facts,
        "clips": update.clips,
        "social": update.social,
        "agent_notes": update.agent_notes,
        "comments": update.comments,
        "voice": update.voice,
        "agent": update.agent,
        "agent_context": update.agent_context,
        "feedback_events": update.feedback_events,
        "feedback_threads": update.feedback_threads,
    })
}

// ── TypedProjectionData assembly ──────────────────────────────────────────────

fn make_typed(schema_id: &str, payload: serde_json::Value) -> TypedProjectionData {
    let bytes = serde_json::to_vec(&payload).unwrap_or_default();
    TypedProjectionData {
        key: schema_id.to_string(),
        schema_id: schema_id.to_string(),
        schema_version: 1,
        file_identifier: String::new(),
        payload: bytes,
    }
}

// ── Registration helpers ──────────────────────────────────────────────────────

/// Register all per-domain typed snapshot projections.
///
/// Each closure captures:
///  - `handle: Arc<PodcastHandle>` — for state access
///  - `domain_rev: Arc<AtomicU64>` — the domain's own rev counter
///  - `last_emitted: Arc<AtomicU64>` — tracks what was last emitted; starts at 0
///
/// On every actor tick the closure:
///  1. Reads domain rev.
///  2. If unchanged since last_emitted → return `None` (sidecar omitted).
///  3. Otherwise serialize, update last_emitted, return `Some(TypedProjectionData)`.
pub fn register_domain_projections(
    app_ref: &nmp_ffi::NmpApp,
    handle: &Arc<PodcastHandle>,
) {
    let domain_revs = Arc::clone(&handle.state.infra.domain_revs);

    // ── podcast.library ───────────────────────────────────────────────────────
    {
        let h = Arc::clone(handle);
        let domain_rev = Arc::clone(&domain_revs.library);
        let last_emitted = Arc::new(AtomicU64::new(0));
        app_ref.register_typed_snapshot_projection(SCHEMA_LIBRARY, move || {
            let current = domain_rev.load(Ordering::Relaxed);
            let prev = last_emitted.load(Ordering::Relaxed);
            if current == prev {
                return None;
            }
            let payload = build_library_payload(&h)?;
            last_emitted.store(current, Ordering::Relaxed);
            Some(make_typed(SCHEMA_LIBRARY, payload))
        });
    }

    // ── podcast.playback ──────────────────────────────────────────────────────
    {
        let h = Arc::clone(handle);
        let domain_rev = Arc::clone(&domain_revs.playback);
        let last_emitted = Arc::new(AtomicU64::new(0));
        app_ref.register_typed_snapshot_projection(SCHEMA_PLAYBACK, move || {
            let current = domain_rev.load(Ordering::Relaxed);
            let prev = last_emitted.load(Ordering::Relaxed);
            if current == prev {
                return None;
            }
            let payload = build_playback_payload(&h);
            last_emitted.store(current, Ordering::Relaxed);
            Some(make_typed(SCHEMA_PLAYBACK, payload))
        });
    }

    // ── podcast.downloads ─────────────────────────────────────────────────────
    {
        let h = Arc::clone(handle);
        let domain_rev = Arc::clone(&domain_revs.downloads);
        let last_emitted = Arc::new(AtomicU64::new(0));
        app_ref.register_typed_snapshot_projection(SCHEMA_DOWNLOADS, move || {
            let current = domain_rev.load(Ordering::Relaxed);
            let prev = last_emitted.load(Ordering::Relaxed);
            if current == prev {
                return None;
            }
            // Returns None when nothing active — sidecar still omitted.
            let payload = build_downloads_payload(&h)?;
            last_emitted.store(current, Ordering::Relaxed);
            Some(make_typed(SCHEMA_DOWNLOADS, payload))
        });
    }

    // ── podcast.settings ──────────────────────────────────────────────────────
    {
        let h = Arc::clone(handle);
        let domain_rev = Arc::clone(&domain_revs.settings);
        let last_emitted = Arc::new(AtomicU64::new(0));
        app_ref.register_typed_snapshot_projection(SCHEMA_SETTINGS, move || {
            let current = domain_rev.load(Ordering::Relaxed);
            let prev = last_emitted.load(Ordering::Relaxed);
            if current == prev {
                return None;
            }
            let payload = build_settings_payload(&h);
            last_emitted.store(current, Ordering::Relaxed);
            Some(make_typed(SCHEMA_SETTINGS, payload))
        });
    }

    // ── podcast.identity ──────────────────────────────────────────────────────
    {
        let h = Arc::clone(handle);
        let domain_rev = Arc::clone(&domain_revs.identity);
        let last_emitted = Arc::new(AtomicU64::new(0));
        app_ref.register_typed_snapshot_projection(SCHEMA_IDENTITY, move || {
            let current = domain_rev.load(Ordering::Relaxed);
            let prev = last_emitted.load(Ordering::Relaxed);
            if current == prev {
                return None;
            }
            // Returns None when no account active.
            let payload = build_identity_payload(&h)?;
            last_emitted.store(current, Ordering::Relaxed);
            Some(make_typed(SCHEMA_IDENTITY, payload))
        });
    }

    // ── podcast.widget ────────────────────────────────────────────────────────
    {
        let h = Arc::clone(handle);
        let domain_rev = Arc::clone(&domain_revs.widget);
        let last_emitted = Arc::new(AtomicU64::new(0));
        app_ref.register_typed_snapshot_projection(SCHEMA_WIDGET, move || {
            let current = domain_rev.load(Ordering::Relaxed);
            let prev = last_emitted.load(Ordering::Relaxed);
            if current == prev {
                return None;
            }
            // Returns None when widget has nothing to show.
            let payload = build_widget_payload(&h)?;
            last_emitted.store(current, Ordering::Relaxed);
            Some(make_typed(SCHEMA_WIDGET, payload))
        });
    }

    // ── podcast.misc ──────────────────────────────────────────────────────────
    {
        let h = Arc::clone(handle);
        let domain_rev = Arc::clone(&domain_revs.misc);
        let last_emitted = Arc::new(AtomicU64::new(0));
        app_ref.register_typed_snapshot_projection(SCHEMA_MISC, move || {
            let current = domain_rev.load(Ordering::Relaxed);
            let prev = last_emitted.load(Ordering::Relaxed);
            if current == prev {
                return None;
            }
            let payload = build_misc_payload(&h);
            last_emitted.store(current, Ordering::Relaxed);
            Some(make_typed(SCHEMA_MISC, payload))
        });
    }
}

// ── Decoder helper ────────────────────────────────────────────────────────────

/// Decode all `podcast.*` typed sidecars from a raw update-frame slice and
/// return them as a JSON object mapping `key → decoded_value`.
///
/// Returns `None` when no `podcast.*` sidecar is present (D6 — degrade
/// silently, never panic). A sidecar whose payload is not valid JSON is
/// silently skipped (D6).
pub fn decode_podcast_domain_sidecars(slice: &[u8]) -> Option<serde_json::Map<String, serde_json::Value>> {
    let typed = nmp_core::decode_snapshot_typed_projections(slice).ok()?;
    let mut map = serde_json::Map::new();
    for entry in typed {
        if entry.schema_id.starts_with("podcast.") {
            if let Ok(value) = serde_json::from_slice::<serde_json::Value>(&entry.payload) {
                map.insert(entry.schema_id, value);
            }
        }
    }
    if map.is_empty() {
        None
    } else {
        Some(map)
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
#[path = "snapshot_domain_projection_tests.rs"]
mod tests;
