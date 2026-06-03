//! Unit tests for `feedback_handler` (in-app feedback over the NMP relay pool).

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use nmp_core::substrate::KernelEvent;
use nmp_core::KernelEventObserver;

use crate::feedback_handler::{
    build_feedback_tags, handle_fetch_feedback, handle_publish_feedback, FeedbackObserver,
    PROJECT_COORDINATE,
};

fn cache() -> (Arc<Mutex<Vec<serde_json::Value>>>, Arc<AtomicU64>) {
    (Arc::new(Mutex::new(Vec::new())), Arc::new(AtomicU64::new(0)))
}

fn feedback_event(id: &str, author: &str, kind: u32, with_anchor: bool) -> KernelEvent {
    let mut tags = vec![vec!["t".to_string(), "bug".to_string()]];
    if with_anchor {
        tags.insert(0, vec!["a".to_string(), PROJECT_COORDINATE.to_string()]);
    }
    KernelEvent {
        id: id.to_string(),
        author: author.to_string(),
        kind,
        created_at: 1_700_000_000,
        tags,
        content: "test feedback".to_string(),
    }
}

// ── tag building ──────────────────────────────────────────────────────

#[test]
fn root_tags_carry_anchor_category_and_protected_marker() {
    let tags = build_feedback_tags("bug", None, None);
    assert!(tags.iter().any(|t| t.first().map(|s| s == "a").unwrap_or(false)
        && t.get(1).map(|s| s == PROJECT_COORDINATE).unwrap_or(false)));
    assert!(tags.iter().any(|t| t.first().map(|s| s == "t").unwrap_or(false)
        && t.get(1).map(|s| s == "bug").unwrap_or(false)));
    // NIP-70 protected marker.
    assert!(tags.iter().any(|t| t.len() == 1 && t[0] == "-"));
    // A thread-opener has no e/p tags.
    assert!(!tags.iter().any(|t| t.first().map(|s| s == "e").unwrap_or(false)));
    assert!(!tags.iter().any(|t| t.first().map(|s| s == "p").unwrap_or(false)));
}

#[test]
fn reply_tags_carry_nip10_root_and_recipient() {
    let parent = "abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abcd";
    let pubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d";
    let tags = build_feedback_tags("question", Some(parent), Some(pubkey));
    let e_tag = tags
        .iter()
        .find(|t| t.first().map(|s| s == "e").unwrap_or(false))
        .expect("reply must have e tag");
    assert_eq!(e_tag.get(1).map(|s| s.as_str()), Some(parent));
    assert_eq!(e_tag.get(3).map(|s| s.as_str()), Some("root"));
    assert!(tags.iter().any(|t| t.first().map(|s| s == "p").unwrap_or(false)
        && t.get(1).map(|s| s == pubkey).unwrap_or(false)));
}

#[test]
fn empty_parent_and_recipient_produce_no_e_or_p_tags() {
    let tags = build_feedback_tags("praise", Some(""), Some(""));
    assert!(!tags.iter().any(|t| t.first().map(|s| s == "e").unwrap_or(false)));
    assert!(!tags.iter().any(|t| t.first().map(|s| s == "p").unwrap_or(false)));
}

// ── publish ───────────────────────────────────────────────────────────

#[test]
fn publish_rejects_empty_content() {
    let v = handle_publish_feedback(std::ptr::null_mut(), "bug", "   ", None, None);
    assert_eq!(v["ok"], false);
    assert_eq!(v["error"], "empty feedback");
}

#[test]
fn publish_returns_signed_with_null_app() {
    let v = handle_publish_feedback(std::ptr::null_mut(), "bug", "found a crash", None, None);
    assert_eq!(v["ok"], true);
    assert_eq!(v["status"], "signed");
}

// ── fetch ─────────────────────────────────────────────────────────────

#[test]
fn fetch_with_null_app_returns_subscribed() {
    let v = handle_fetch_feedback(std::ptr::null_mut());
    assert_eq!(v["ok"], true);
    assert_eq!(v["status"], "subscribed");
}

// ── observer ──────────────────────────────────────────────────────────

#[test]
fn observer_caches_event_in_signed_nostr_shape() {
    let (slot, rev) = cache();
    let obs = FeedbackObserver::new(slot.clone(), rev.clone());
    obs.on_kernel_event(&feedback_event("id1", "authorhex", 1, true));

    let guard = slot.lock().unwrap();
    assert_eq!(guard.len(), 1);
    let e = &guard[0];
    assert_eq!(e["id"], "id1");
    // author → pubkey remap.
    assert_eq!(e["pubkey"], "authorhex");
    // sig is empty placeholder.
    assert_eq!(e["sig"], "");
    assert_eq!(e["kind"], 1);
    assert_eq!(e["created_at"], 1_700_000_000_u64);
    assert_eq!(rev.load(Ordering::Relaxed), 1);
}

#[test]
fn observer_caches_metadata_kind_513() {
    let (slot, rev) = cache();
    let obs = FeedbackObserver::new(slot.clone(), rev.clone());
    obs.on_kernel_event(&feedback_event("meta1", "authorhex", 513, true));
    assert_eq!(slot.lock().unwrap().len(), 1);
}

#[test]
fn observer_does_not_self_filter() {
    // Unlike agent_note_handler, feedback caches events from ANY author —
    // the Feedback UI defaults to showing the user's own threads.
    let (slot, rev) = cache();
    let obs = FeedbackObserver::new(slot.clone(), rev.clone());
    obs.on_kernel_event(&feedback_event("mine", "myownpubkey", 1, true));
    assert_eq!(slot.lock().unwrap().len(), 1);
}

#[test]
fn observer_ignores_events_without_project_anchor() {
    let (slot, rev) = cache();
    let obs = FeedbackObserver::new(slot.clone(), rev.clone());
    obs.on_kernel_event(&feedback_event("no-anchor", "authorhex", 1, false));
    assert_eq!(slot.lock().unwrap().len(), 0);
    assert_eq!(rev.load(Ordering::Relaxed), 0);
}

#[test]
fn observer_ignores_unrelated_kinds() {
    let (slot, rev) = cache();
    let obs = FeedbackObserver::new(slot.clone(), rev.clone());
    obs.on_kernel_event(&feedback_event("kind9802", "authorhex", 9802, true));
    assert_eq!(slot.lock().unwrap().len(), 0);
}

#[test]
fn observer_dedupes_by_event_id() {
    let (slot, rev) = cache();
    let obs = FeedbackObserver::new(slot.clone(), rev.clone());
    obs.on_kernel_event(&feedback_event("dup", "authorhex", 1, true));
    obs.on_kernel_event(&feedback_event("dup", "authorhex", 1, true));
    assert_eq!(slot.lock().unwrap().len(), 1);
    assert_eq!(rev.load(Ordering::Relaxed), 1, "duplicate must not bump rev");
}
