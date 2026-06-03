//! In-app feedback (TENEX project notes) over the NMP relay pool.
//!
//! Replaces the Swift `FeedbackRelayClient`'s direct `URLSessionWebSocketTask`
//! fetch + publish to `wss://relay.tenex.chat`. NMP core owns all relay
//! connections (D7): the host never opens a relay socket for feedback.
//!
//! ## Relay
//!
//! * **Fetch** — `push_interest_via_nmp` with a `OneShot` interest declaring
//!   `kinds:[1,513]` + a `["a", coord]` `tag_ref` and `relay_pin` set to the
//!   feedback relay. NMP opens (and NIP-42-AUTHs) the subscription on its pooled
//!   connection; inbound events arrive at [`FeedbackObserver`].
//! * **Publish** — `publish_raw_explicit_via_nmp` with `PublishTarget::Explicit`
//!   pinned to the feedback relay. NMP signs with the active user signer and
//!   AUTHs the write. Feedback notes are NIP-70 protected (`["-"]`), so they
//!   must reach the project relay specifically — *not* the user's Auto outbox.
//!
//! ## Wire shape
//!
//! Roots, replies, and metadata all carry the project `["a", coord]` tag
//! (`publishFeedbackNote` adds it unconditionally), so a single `#a` interest
//! over kinds [1,513] captures the whole thread tree in one fetch. Swift's
//! `FeedbackStore.buildThreads` reconstructs threads/replies/metadata from the
//! flat event list.
//!
//! ## Cache
//!
//! Matching events are stored in `feedback_events_cache`
//! (`Arc<Mutex<Vec<serde_json::Value>>>`) as **`SignedNostrEvent`-shaped JSON**
//! — `KernelEvent` carries `author` (not `pubkey`) and no `sig`, but Swift's
//! `SignedNostrEvent` decoder needs `{id,pubkey,created_at,kind,tags,content,sig}`.
//! We map `pubkey = author` and `sig = ""` (D6: `buildThreads` never reads the
//! signature). The snapshot projects this slot onto `PodcastUpdate.feedback_events`.
//!
//! Unlike [`crate::agent_note_handler`], the observer does **not** drop
//! self-authored events: the Feedback UI defaults to showing the user's own
//! threads, so filtering them out would empty the list.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use nmp_core::planner::{InterestId, InterestLifecycle, InterestScope, LogicalInterest};
use nmp_core::stable_hash::stable_hash64;
use nmp_core::substrate::{KernelEvent, ViewDependencies};
use nmp_core::KernelEventObserver;

use crate::nmp_dispatch::{publish_raw_explicit_via_nmp, push_interest_via_nmp};
use nmp_ffi::NmpApp;

/// Feedback relay (TENEX project). The one relay feedback fetch/publish pins to.
pub(crate) const FEEDBACK_RELAY: &str = "wss://relay.tenex.chat";

/// NIP-72 community coordinate for the Podcastr feedback project. Every
/// feedback note + metadata event carries `["a", PROJECT_COORDINATE]`. Mirrors
/// `FeedbackRelayClient.projectCoordinate` on the Swift side — keep in sync.
pub(crate) const PROJECT_COORDINATE: &str =
    "31933:09d48a1a5dbe13404a729634f1d6ba722d40513468dd713c8ea38ca9b7b6f2c7:podcast";

/// kind:1 text note (feedback message / reply).
const KIND_TEXT_NOTE: u32 = 1;
/// kind:513 feedback metadata (title / summary / status).
const KIND_METADATA: u32 = 513;

/// Maximum feedback events to retain in the cache.
const MAX_FEEDBACK_EVENTS: usize = 500;

// ── subscribe ────────────────────────────────────────────────────────────────

/// Build the relay-pinned `OneShot` interest for the feedback project's
/// kind:1 + kind:513 events anchored to the project coordinate.
fn feedback_interest() -> LogicalInterest {
    let mut interest = ViewDependencies {
        kinds: vec![KIND_TEXT_NOTE, KIND_METADATA],
        tag_refs: vec![("a".to_string(), PROJECT_COORDINATE.to_string())],
        relay_pin: Some(FEEDBACK_RELAY.to_string()),
        limit: Some(MAX_FEEDBACK_EVENTS as u32),
        ..Default::default()
    }
    .into_logical_interest(
        InterestId(stable_hash64("podcast.feedback")),
        // Relay-pinned interests MUST use Global scope (the `relay_pin` field
        // routes them); they are not tied to one account's mailbox.
        InterestScope::Global,
        InterestLifecycle::OneShot,
    );
    // Defensive: `into_logical_interest` copies `relay_pin` from the shape, but
    // re-assert it so the routing lane is unambiguous if the bridge changes.
    interest.shape.relay_pin = Some(FEEDBACK_RELAY.to_string());
    interest
}

/// Fetch feedback events (kind:1 + kind:513 for the project coord) via the NMP
/// relay pool. Results arrive via [`FeedbackObserver`] and ride the next
/// snapshot on `PodcastUpdate.feedback_events`.
pub fn handle_fetch_feedback(app: *mut NmpApp) -> serde_json::Value {
    push_interest_via_nmp(app, feedback_interest());
    serde_json::json!({"ok": true, "status": "subscribed"})
}

// ── publish ────────────────────────────────────────────────────────────────

/// Build the kind:1 tags for a feedback note/reply. Rust owns all tag
/// construction — Swift passes only the semantic values.
///
/// Tag structure mirrors the prior `publishFeedbackNote`:
/// * `["a", PROJECT_COORDINATE]` — NIP-72 project anchor.
/// * `["t", category]` — feedback category (`bug` / `feature-request` / …).
/// * `["-"]` — NIP-70 protected marker (relay-AUTH-gated note).
/// * `["e", parent, "", "root"]` — NIP-10 root marker for replies.
/// * `["p", reply_to_pubkey]` — recipient when replying.
pub(crate) fn build_feedback_tags(
    category: &str,
    parent_event_id: Option<&str>,
    reply_to_pubkey: Option<&str>,
) -> Vec<Vec<String>> {
    let mut tags: Vec<Vec<String>> = vec![
        vec!["a".to_string(), PROJECT_COORDINATE.to_string()],
        vec!["t".to_string(), category.to_string()],
        vec!["-".to_string()],
    ];
    if let Some(parent) = parent_event_id.filter(|s| !s.is_empty()) {
        tags.push(vec![
            "e".to_string(),
            parent.to_string(),
            String::new(),
            "root".to_string(),
        ]);
    }
    if let Some(pk) = reply_to_pubkey.filter(|s| !s.is_empty()) {
        tags.push(vec!["p".to_string(), pk.to_string()]);
    }
    tags
}

/// Sign + publish a feedback note (kind:1) to the feedback relay via NMP.
/// NMP signs with the active user signer and AUTHs the write — no secret bytes
/// in app code, no relay socket opened by the host.
pub fn handle_publish_feedback(
    app: *mut NmpApp,
    category: &str,
    content: &str,
    parent_event_id: Option<&str>,
    reply_to_pubkey: Option<&str>,
) -> serde_json::Value {
    if content.trim().is_empty() {
        return serde_json::json!({"ok": false, "error": "empty feedback"});
    }
    let tags = build_feedback_tags(category, parent_event_id, reply_to_pubkey);
    let status = publish_raw_explicit_via_nmp(
        app,
        KIND_TEXT_NOTE,
        &tags,
        content,
        &[FEEDBACK_RELAY],
    );
    serde_json::json!({"ok": true, "status": status})
}

// ── observer ─────────────────────────────────────────────────────────────────

/// Receives inbound feedback events (kind:1 + kind:513 bearing the project
/// `["a"]` coord) from NMP's relay pool and caches them as
/// `SignedNostrEvent`-shaped JSON for the snapshot projection.
pub struct FeedbackObserver {
    feedback_events_cache: Arc<Mutex<Vec<serde_json::Value>>>,
    rev: Arc<AtomicU64>,
}

impl FeedbackObserver {
    #[must_use]
    pub fn new(
        feedback_events_cache: Arc<Mutex<Vec<serde_json::Value>>>,
        rev: Arc<AtomicU64>,
    ) -> Self {
        Self { feedback_events_cache, rev }
    }
}

/// Project a [`KernelEvent`] onto the `SignedNostrEvent` JSON shape Swift
/// decodes (`pubkey = author`, `sig = ""`). `created_at` stays snake_case —
/// the snapshot decoder maps it to the Swift DTO's `createdAt`.
fn project_feedback_event(event: &KernelEvent) -> serde_json::Value {
    serde_json::json!({
        "id": event.id,
        "pubkey": event.author,
        "created_at": event.created_at,
        "kind": event.kind,
        "tags": event.tags,
        "content": event.content,
        "sig": "",
    })
}

/// `true` when `event` carries the project `["a", PROJECT_COORDINATE]` tag.
fn has_project_anchor(event: &KernelEvent) -> bool {
    event.tags.iter().any(|t| {
        t.first().map(|s| s == "a").unwrap_or(false)
            && t.get(1).map(|s| s == PROJECT_COORDINATE).unwrap_or(false)
    })
}

impl KernelEventObserver for FeedbackObserver {
    fn on_kernel_event(&self, event: &KernelEvent) {
        if event.kind != KIND_TEXT_NOTE && event.kind != KIND_METADATA {
            return;
        }
        // The observer sees ALL events, not just relay-pinned ones — filter to
        // the feedback project by its `["a"]` anchor.
        if !has_project_anchor(event) {
            return;
        }
        let projected = project_feedback_event(event);
        if let Ok(mut cache) = self.feedback_events_cache.lock() {
            // Dedupe by event id (a re-fetch or relay re-arrival fires again).
            let id = event.id.as_str();
            if cache
                .iter()
                .any(|e| e.get("id").and_then(|v| v.as_str()) == Some(id))
            {
                return;
            }
            cache.push(projected);
            if cache.len() > MAX_FEEDBACK_EVENTS {
                let overflow = cache.len() - MAX_FEEDBACK_EVENTS;
                cache.drain(0..overflow);
            }
            drop(cache);
            self.rev.fetch_add(1, Ordering::Relaxed);
        }
    }
}

#[cfg(test)]
#[path = "feedback_handler_tests.rs"]
mod tests;
