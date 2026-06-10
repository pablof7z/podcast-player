//! Unit tests for the kernel-side feedback-thread reduction (#354) — the
//! Nostr semantics ported out of the iOS `FeedbackStore.buildThreads`.

use super::*;
use serde_json::json;

const COORD: &str = "31933:abc:podcast";

fn ev(id: &str, pubkey: &str, kind: u32, created_at: i64, tags: Value, content: &str) -> Value {
    json!({
        "id": id,
        "pubkey": pubkey,
        "created_at": created_at,
        "kind": kind,
        "tags": tags,
        "content": content,
        "sig": "",
    })
}

#[test]
fn root_with_reply_and_metadata_resolves() {
    let events = vec![
        // root note carrying the project coordinate + a category tag
        ev(
            "root1",
            "alice",
            1,
            100,
            json!([["a", COORD], ["t", "feature-request"]]),
            "please add X",
        ),
        // reply under root1
        ev(
            "reply1",
            "bob",
            1,
            150,
            json!([["e", "root1", "", "root"], ["a", COORD]]),
            "+1",
        ),
        // kind:513 metadata for root1
        ev(
            "meta1",
            "maintainer",
            513,
            200,
            json!([["e", "root1"], ["title", "Add X"], ["status", "open"]]),
            "",
        ),
    ];
    let threads = reduce_feedback_threads(&events, COORD);
    assert_eq!(threads.len(), 1);
    let t = &threads[0];
    assert_eq!(t.event_id, "root1");
    assert_eq!(t.author_pubkey, "alice");
    assert_eq!(t.category, "feature-request");
    assert_eq!(t.content, "please add X");
    assert_eq!(t.title.as_deref(), Some("Add X"));
    assert_eq!(t.status_label.as_deref(), Some("open"));
    assert_eq!(t.replies.len(), 1);
    assert_eq!(t.replies[0].event_id, "reply1");
}

#[test]
fn newest_kind_513_metadata_wins() {
    let events = vec![
        ev("root1", "a", 1, 100, json!([["a", COORD]]), "root"),
        ev(
            "old",
            "m",
            513,
            150,
            json!([["e", "root1"], ["status", "open"]]),
            "",
        ),
        ev(
            "new",
            "m",
            513,
            200,
            json!([["e", "root1"], ["status", "resolved"]]),
            "",
        ),
    ];
    let threads = reduce_feedback_threads(&events, COORD);
    assert_eq!(threads[0].status_label.as_deref(), Some("resolved"));
}

#[test]
fn roots_without_project_coordinate_are_excluded() {
    let events = vec![
        ev("mine", "a", 1, 100, json!([["a", COORD]]), "in project"),
        ev(
            "other",
            "a",
            1,
            100,
            json!([["a", "31933:xyz:other"]]),
            "different project",
        ),
        ev("untagged", "a", 1, 100, json!([]), "no coordinate"),
    ];
    let threads = reduce_feedback_threads(&events, COORD);
    assert_eq!(threads.len(), 1);
    assert_eq!(threads[0].event_id, "mine");
}

#[test]
fn roots_sorted_newest_first_replies_oldest_first() {
    let events = vec![
        ev("r_old", "a", 1, 100, json!([["a", COORD]]), "old root"),
        ev("r_new", "a", 1, 300, json!([["a", COORD]]), "new root"),
        ev("rep_b", "b", 1, 250, json!([["e", "r_new", "", "root"]]), "second"),
        ev("rep_a", "b", 1, 200, json!([["e", "r_new", "", "root"]]), "first"),
    ];
    let threads = reduce_feedback_threads(&events, COORD);
    assert_eq!(threads.len(), 2);
    assert_eq!(threads[0].event_id, "r_new"); // newest root first
    assert_eq!(threads[1].event_id, "r_old");
    assert_eq!(
        threads[0].replies.iter().map(|r| r.event_id.as_str()).collect::<Vec<_>>(),
        vec!["rep_a", "rep_b"] // replies oldest-first
    );
}

#[test]
fn category_defaults_to_bug_and_maps_aliases() {
    let mk = |tags: Value| {
        reduce_feedback_threads(&[ev("r", "a", 1, 1, tags, "c")], COORD)[0]
            .category
            .clone()
    };
    assert_eq!(mk(json!([["a", COORD]])), "bug"); // no category tag
    assert_eq!(mk(json!([["a", COORD], ["t", "Praise"]])), "praise"); // case-insensitive
    assert_eq!(mk(json!([["a", COORD], ["category", "question"]])), "question");
    assert_eq!(mk(json!([["a", COORD], ["t", "feature request"]])), "feature-request");
}

#[test]
fn metadata_falls_back_to_content_json() {
    let events = vec![
        ev("root1", "a", 1, 100, json!([["a", COORD]]), "root"),
        ev(
            "meta1",
            "m",
            513,
            150,
            json!([["e", "root1"]]),
            r#"{"title":"From JSON","summary":"sum","status_label":"closed"}"#,
        ),
    ];
    let t = &reduce_feedback_threads(&events, COORD)[0];
    assert_eq!(t.title.as_deref(), Some("From JSON"));
    assert_eq!(t.summary.as_deref(), Some("sum"));
    assert_eq!(t.status_label.as_deref(), Some("closed"));
}

#[test]
fn malformed_events_are_skipped_not_fatal() {
    let events = vec![
        json!({"not": "an event"}),
        json!("garbage"),
        ev("root1", "a", 1, 100, json!([["a", COORD]]), "ok"),
    ];
    let threads = reduce_feedback_threads(&events, COORD);
    assert_eq!(threads.len(), 1);
    assert_eq!(threads[0].event_id, "root1");
}

#[test]
fn empty_input_yields_no_threads() {
    assert!(reduce_feedback_threads(&[], COORD).is_empty());
}
