//! Unit tests for `social_publish_handler` — kind:0 / kind:1 / kind:9802
//! publishing on behalf of the user's Nostr identity.
//!
//! Signing moved to the kernel's active-account signer; these handlers no
//! longer build or sign `nostr::Event`s. The live relay round-trip
//! (kernel sign → publish) is integration-tested in the headless scenario
//! binary. These unit tests cover the validation / short-circuit paths and
//! the pure kind:0 `fields` assembly helper. Under a null `app` the dispatch
//! helpers short-circuit to `{"status":"signed"}` without touching the FFI.

use std::sync::{Arc, Mutex};

use crate::social_publish_handler::{
    build_profile_fields, handle_publish_highlight, handle_publish_note, handle_publish_profile,
};
use crate::store::identity::IdentityStore;

const TEST_NSEC: &str = "nsec1cdxlq0ckkqeuauhzqaduugmrjpwuk3cgwq37ef2nvzje8at26lwqapk9us";

fn signed_in_identity() -> Arc<Mutex<IdentityStore>> {
    let mut id = IdentityStore::new();
    id.import_nsec(TEST_NSEC).unwrap();
    Arc::new(Mutex::new(id))
}

// ── build_profile_fields: pure kind:0 field assembly ─────────────────

#[test]
fn build_profile_fields_carries_all_present_fields() {
    let fields = build_profile_fields(
        "alice",
        Some("Alice"),
        Some("about me"),
        Some("https://example.com/a.png"),
    );
    assert_eq!(fields["name"], "alice");
    assert_eq!(fields["display_name"], "Alice");
    assert_eq!(fields["about"], "about me");
    assert_eq!(fields["picture"], "https://example.com/a.png");
}

#[test]
fn build_profile_fields_omits_absent_optional_fields() {
    let fields = build_profile_fields("bob", None, None, None);
    assert_eq!(fields["name"], "bob");
    assert!(!fields.contains_key("display_name"));
    assert!(!fields.contains_key("about"));
    assert!(!fields.contains_key("picture"));
}

// ── handle_*: validation / short-circuit ─────────────────────────────

#[test]
fn publish_profile_rejects_when_no_identity() {
    let identity = Arc::new(Mutex::new(IdentityStore::new())); // no key
    let v = handle_publish_profile(
        std::ptr::null_mut(),
        &identity,
        "alice",
        None,
        None,
        None,
        "corr",
    );
    assert_eq!(v["ok"], false);
    assert_eq!(v["error"], "not signed in");
}

#[test]
fn publish_profile_dispatches_under_null_app() {
    let identity = signed_in_identity();
    let v = handle_publish_profile(
        std::ptr::null_mut(),
        &identity,
        "alice",
        Some("Alice"),
        None,
        None,
        "corr",
    );
    assert_eq!(v["ok"], true);
    assert_eq!(v["status"], "signed");
}

#[test]
fn publish_note_rejects_empty_content() {
    let identity = signed_in_identity();
    let v = handle_publish_note(std::ptr::null_mut(), &identity, "   ", None, "corr");
    assert_eq!(v["ok"], false);
    assert_eq!(v["error"], "empty note");
}

#[test]
fn publish_note_rejects_when_no_identity() {
    let identity = Arc::new(Mutex::new(IdentityStore::new()));
    let v = handle_publish_note(std::ptr::null_mut(), &identity, "hi", None, "corr");
    assert_eq!(v["ok"], false);
    assert_eq!(v["error"], "not signed in");
}

#[test]
fn publish_note_dispatches_under_null_app() {
    let identity = signed_in_identity();
    let v = handle_publish_note(std::ptr::null_mut(), &identity, "hello", None, "corr");
    assert_eq!(v["ok"], true);
    assert_eq!(v["status"], "signed");
}

#[test]
fn publish_highlight_rejects_empty_content() {
    let identity = signed_in_identity();
    let v = handle_publish_highlight(std::ptr::null_mut(), &identity, "  ", None, "corr");
    assert_eq!(v["ok"], false);
    assert_eq!(v["error"], "empty highlight");
}

#[test]
fn publish_highlight_dispatches_under_null_app() {
    let identity = signed_in_identity();
    let tags = vec![vec!["context".to_string(), "ctx".to_string()]];
    let v = handle_publish_highlight(
        std::ptr::null_mut(),
        &identity,
        "a quote",
        Some(&tags),
        "corr",
    );
    assert_eq!(v["ok"], true);
    assert_eq!(v["status"], "signed");
}
