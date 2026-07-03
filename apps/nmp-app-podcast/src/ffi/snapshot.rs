//! Snapshot entry points the host calls against a [`PodcastHandle`].
//!
//! [`PodcastUpdate`] type definition lives in `snapshot_update.rs`;
//! per-projection types live in [`super::projections`]; queue, owned-podcast,
//! and category build helpers live in `snapshot_queue/owned/categories` siblings.
//! The ~80-field [`SettingsSnapshot`] assembly lives in `snapshot_settings.rs`.

pub use super::snapshot_update::{AppRelayRow, PodcastUpdate};

use std::sync::atomic::Ordering;

use super::handle::PodcastHandle;
use super::projections::{AgentSnapshot, PodcastSummary};
use super::snapshot_categories::build_category_aggregate;
use super::snapshot_downloads::build_downloads_snapshot;
use super::snapshot_owned::collect_owned_podcasts;
use super::snapshot_queue::resolve_queue_rows;
use super::snapshot_settings::build_settings_snapshot;
use super::snapshot_widget::build_widget_snapshot;
// inbox_handler imports removed in Step 7 — InboxState now owns the projection
// and the proactive trigger.  See `state::inbox::InboxState::project()` and
// `InboxState::maybe_enqueue_triage()`.

pub(super) fn provider_key_present(key: Option<&str>) -> bool {
    key.is_some_and(|value| !value.trim().is_empty())
}

/// Build the typed [`PodcastUpdate`] directly from the handle state.
///
/// Rust-native path — no JSON round-trip. Used by the TUI and other
/// Rust consumers that want typed projections without paying serde
/// serialization + deserialization.
pub fn build_podcast_update(handle: &PodcastHandle) -> PodcastUpdate {
    let rev = handle.state.infra.rev.load(Ordering::Relaxed);

    // Step 14: player_actor now sourced from state.playback.player.
    let now_playing = handle.state.playback.player.lock().ok().and_then(|a| {
        let s = a.state().clone();
        if s.episode_id.is_some() {
            Some(s)
        } else {
            None
        }
    });

    // Snapshot caches before the store lock so we don't hold two locks at once.
    // Step 5b: transcripts now read from TranscriptsState.
    let transcripts = handle.state.transcripts.snapshot();
    // Step 4: categories_cache now read from CategoriesState.
    let categories_cache = handle.state.categories.categories_snapshot();

    // Single store lock → library + memory_facts + settings.
    let (library, memory_facts, settings) = handle
        .state
        .library
        .store
        .lock()
        .ok()
        .map(|s| {
            let library = super::snapshot_library::build_library_snapshot(
                handle,
                &s,
                &transcripts,
                &categories_cache,
            );
            let settings = build_settings_snapshot(&s);
            (library, s.all_memory_facts(), settings)
        })
        .unwrap_or_default();

    let subscribed_library: Vec<PodcastSummary> = library
        .iter()
        .filter(|p| p.is_subscribed)
        .cloned()
        .collect();
    let categories = build_category_aggregate(&subscribed_library);
    // Agent-prompt inventory context (kernel-owned selection/ordering/capping).
    // Derived from the already-assembled subscribed slice so it reuses resolved
    // position/played/triage/pub-date without a second store lock. `None` when
    // no shows are followed so a fresh install stays byte-identical to the stub.
    let agent_context = if subscribed_library.is_empty() {
        None
    } else {
        let now_unix = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        Some(super::agent_context::build_agent_context(
            &subscribed_library,
            now_unix,
        ))
    };
    // Step 9: search_results + nostr_results now read from DiscoveryState.
    let search_results = handle.state.discovery.itunes_snapshot();
    let nostr_results = handle.state.discovery.nostr_snapshot();
    // Step 14: queue now read from state.playback.queue.
    let queue_ids = handle.state.playback.queue_snapshot();
    let queue = resolve_queue_rows(&queue_ids, &library);
    // Step 3: picks slot is now owned by `state.picks`.
    let picks = handle.state.picks.picks_snapshot();
    // Step 6: agent_tasks now read from TasksState.
    let agent_tasks = handle.state.tasks.tasks_snapshot();
    let knowledge_search_results = handle.state.knowledge.results_snapshot();
    // Step 5a: clips now projected from ClipsState.
    let clips = handle.state.clips.project(&library);
    // Step 7 / D8: inbox projected from InboxState — pure, no side effects.
    // Proactive triage trigger was lifted to the feed-refresh path (Commit 2).
    let inbox = handle.state.inbox.project();
    // Step 7: inbox_triage_in_progress now read from InboxState.
    let inbox_triage_in_progress = handle.state.inbox.triage_in_progress_snapshot();
    let inbox_last_triaged_at = handle.state.inbox.last_triaged_at_snapshot();
    let owned_podcasts = collect_owned_podcasts(handle);
    // Step 14: downloads now read from state.playback.downloads.
    let downloads = handle
        .state
        .playback
        .downloads
        .lock()
        .ok()
        .and_then(|q| build_downloads_snapshot(&q));

    // Step 8: comments now read from CommentsState.
    // Project viewed-episode comments, falling back to now-playing.
    let comments = handle
        .state
        .comments
        .project(now_playing.as_ref().and_then(|np| np.episode_id.as_deref()));
    let notes = handle
        .state
        .notes
        .notes_snapshot()
        .into_iter()
        .map(Into::into)
        .collect();
    let friends = handle
        .state
        .friends
        .friends_snapshot()
        .into_iter()
        .map(Into::into)
        .collect();

    let active_account = super::snapshot_identity::build_active_account(handle);

    // Step 10: social now read from SocialState.
    let social = handle.state.social.social_snapshot();

    // NIP-10 threaded conversations (inbound + outbound turns merged by root_event_id).
    // The flat `agent_notes` list was retired — conversations subsume it.
    let nostr_conversations = handle.state.social.nostr_conversations_snapshot();

    // Feedback waits on pablof7z/nmp-feedback#3; keep the wire fields present
    // but empty until the app can consume the replacement feedback runtime.
    let feedback_events: Vec<serde_json::Value> = Vec::new();
    let feedback_threads: Vec<serde_json::Value> = Vec::new();

    // Configured app relays (NMP v0.2.1). Kernel-owned slot, projected by the
    // sibling helper. SAFETY: `handle.app` is the live `*mut NmpApp` the
    // host-op handler also dereferences; the actor joins before `nmp_app_free`.
    let configured_relays = unsafe { super::snapshot_relays::build_configured_relays(handle.app) };

    // Step 12: voice now projected from VoiceSubstate.
    let voice = handle.state.voice.voice_snapshot();

    // Step 11: agent chat now read from AgentChatState.
    let agent = {
        let messages = handle.state.agent_chat.conversation_snapshot();
        let touched = handle.state.agent_chat.is_touched();
        if messages.is_empty() && !touched {
            None
        } else {
            Some(AgentSnapshot {
                messages,
                is_busy: handle.state.agent_chat.is_busy(),
            })
        }
    };

    // Kernel-owned widget projection (D4 single source of truth). Built from
    // the player state + the already-assembled library (per-show
    // `unplayed_count` is reused, no rescan). The iOS shell serializes this
    // into the App Group key the widget extension reads; the old Swift-side
    // `NowPlayingSnapshot` derivation is retired.
    let widget = build_widget_snapshot(now_playing.as_ref(), &library);

    PodcastUpdate {
        rev,
        now_playing,
        library,
        widget,
        active_account,
        search_results,
        nostr_results,
        settings,
        comments,
        notes,
        friends,
        queue,
        picks,
        agent_tasks,
        knowledge_search_results,
        memory_facts,
        clips,
        inbox,
        inbox_triage_in_progress,
        inbox_last_triaged_at,
        owned_podcasts,
        downloads,
        voice,
        agent,
        agent_context,
        categories,
        social,
        nostr_conversations,
        configured_relays,
        feedback_events,
        feedback_threads,
        ..PodcastUpdate::default()
    }
}

pub(super) fn build_snapshot_payload(handle: &PodcastHandle) -> String {
    let rev = handle.state.infra.rev.load(Ordering::Relaxed);

    // Fast path: skip re-serialization when rev hasn't changed.
    if let Ok(cache) = handle.snapshot_cache.lock() {
        if let Some((cached_rev, ref cached_json)) = *cache {
            if cached_rev == rev {
                return cached_json.clone();
            }
        }
    }

    let update = build_podcast_update(handle);
    let json = serde_json::to_string(&update)
        .unwrap_or_else(|_| r#"{"running":true,"rev":0,"schema_version":1}"#.to_owned());

    if let Ok(mut cache) = handle.snapshot_cache.lock() {
        *cache = Some((rev, json.clone()));
    }
    json
}

impl PodcastHandle {
    /// Build the typed [`PodcastUpdate`] directly from the handle state.
    ///
    /// Rust-native path — no JSON round-trip. Used by the TUI and other
    /// Rust consumers that want typed projections without paying serde
    /// serialization + deserialization.
    pub fn update(&self) -> PodcastUpdate {
        build_podcast_update(self)
    }
}

pub(crate) fn decode_update_frame_json(slice: &[u8]) -> Option<String> {
    let envelope = nmp_core::decode_update_frame(slice).ok()?;
    let json = match envelope {
        nmp_core::UpdateEnvelope::Snapshot(env) => {
            let mut v = serde_json::json!({
                "rev": env.rev,
                "running": env.running,
                "schema_version": 1u32,
            });
            if let Some(toast) = env.last_error_toast {
                v["last_error_toast"] = serde_json::Value::String(toast);
            }
            if let Some(cat) = env.last_error_category {
                v["last_error_category"] = serde_json::Value::String(cat);
            }

            let signed_events_json = decode_signed_events_sidecar(slice);
            let action_results_json = decode_action_results_sidecar(slice);
            let domain_sidecars =
                super::snapshot_domain_projections::decode_podcast_domain_sidecars(slice);
            let nostr_search_sidecars = decode_nostr_search_sidecars(slice);

            if signed_events_json.is_some()
                || action_results_json.is_some()
                || domain_sidecars.is_some()
                || nostr_search_sidecars.is_some()
            {
                let mut projections = serde_json::Map::new();
                if let Some(se) = signed_events_json {
                    projections.insert("signed_events".to_string(), se);
                }
                if let Some(ar) = action_results_json {
                    projections.insert("action_results".to_string(), ar);
                }
                if let Some(domains) = domain_sidecars {
                    for (key, val) in domains {
                        projections.insert(key, val);
                    }
                }
                if let Some(searches) = nostr_search_sidecars {
                    for (key, val) in searches {
                        projections.insert(key, val);
                    }
                }
                v["projections"] = serde_json::Value::Object(projections);
            }
            serde_json::json!({ "t": "snapshot", "v": v })
        }
        nmp_core::UpdateEnvelope::Panic(panic) => {
            serde_json::json!({ "t": "panic", "message": panic.msg })
        }
    };
    Some(json.to_string())
}

/// Decode the `signed_events` typed FlatBuffer sidecar from a raw update-frame
/// slice and convert it to the JSON object `SignedEventsRegistry.ingest` expects:
/// `{ correlation_id: { "ok": true, "signed_json": "..." } }` or
/// `{ correlation_id: { "ok": false, "error": "..." } }`.
///
/// Returns `None` when the sidecar is absent, empty, or malformed (D6 — degrade
/// silently, never panic).
fn decode_signed_events_sidecar(slice: &[u8]) -> Option<serde_json::Value> {
    use nmp_core::typed_projections::{decode_signed_events, SIGNED_EVENTS_SCHEMA_ID};

    let typed = nmp_core::decode_snapshot_typed_projections(slice).ok()?;
    let entry = typed
        .into_iter()
        .find(|e| e.schema_id == SIGNED_EVENTS_SCHEMA_ID)?;
    let model = decode_signed_events(&entry.payload).ok()?;
    if model.entries.is_empty() {
        return None;
    }
    let mut map = serde_json::Map::with_capacity(model.entries.len());
    for (correlation_id, row) in model.entries {
        let value = if row.ok {
            serde_json::json!({ "ok": true, "signed_json": row.signed_json.unwrap_or_default() })
        } else {
            serde_json::json!({ "ok": false, "error": row.error.unwrap_or_default() })
        };
        map.insert(correlation_id, value);
    }
    Some(serde_json::Value::Object(map))
}

// Action-results sidecar decode lives in a sibling file to keep this file
// under the 500-line AGENTS.md hard limit. The function is `pub(super)` and
// visible here via the `#[path]`-linked module.
#[path = "snapshot_action_results.rs"]
mod snapshot_action_results;
use snapshot_action_results::decode_action_results_sidecar;
#[path = "snapshot_nostr_search.rs"]
mod snapshot_nostr_search;
use snapshot_nostr_search::decode_nostr_search_sidecars;

// Tests split into snapshot_tests.rs + snapshot_tests_ext.rs + snapshot_decode_tests.rs;
// #[path] keeps private items in scope.
#[cfg(test)]
#[path = "snapshot_decode_tests.rs"]
mod decode_tests;
#[cfg(test)]
#[path = "snapshot_tests.rs"]
mod tests;
#[cfg(test)]
#[path = "snapshot_tests_ext.rs"]
mod tests_ext;
