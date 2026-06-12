//! Tests for [super::nip_f4] — NIP-F4 show/episode event parsing (kind 10154/54).
//!
//! Extracted from `nip_f4.rs` to keep that file under the 500-line hard limit.

use super::*;

fn full_tags() -> Vec<Vec<String>> {
    vec![
        vec!["title".into(), "Rust Talk".into()],
        vec!["summary".into(), "A show about Rust".into()],
        vec!["image".into(), "https://img.example/cover.jpg".into()],
        vec!["feed".into(), "https://feeds.example.com/rust.rss".into()],
        vec!["category".into(), "Technology".into()],
        vec!["category".into(), "Programming".into()],
    ]
}

#[test]
fn kind_constants_pinned() {
    assert_eq!(KIND_NIP_F4_SHOW, 10154);
    assert_eq!(KIND_NIP_F4_EPISODE, 54);
    assert_eq!(KIND_NIP_F4_AUTHOR_CLAIM, 10064);
}

#[test]
fn parse_full_show_collects_every_field() {
    let show = parse_kind_10154(
        KIND_NIP_F4_SHOW,
        "ev-id",
        "podcast-pk",
        "",
        &full_tags(),
    )
    .expect("parse");
    assert_eq!(show.event_id, "ev-id");
    assert_eq!(show.author_pubkey, "podcast-pk");
    assert_eq!(show.title, "Rust Talk");
    assert_eq!(show.description.as_deref(), Some("A show about Rust"));
    assert_eq!(show.artwork_url.as_deref(), Some("https://img.example/cover.jpg"));
    assert_eq!(
        show.feed_url.as_deref(),
        Some("https://feeds.example.com/rust.rss")
    );
    assert_eq!(
        show.categories,
        vec!["Technology".to_string(), "Programming".into()]
    );
}

#[test]
fn parse_minimal_show_with_only_title_succeeds() {
    let tags = vec![vec!["title".into(), "Solo".into()]];
    let show = parse_kind_10154(KIND_NIP_F4_SHOW, "id", "pk", "", &tags).expect("parse");
    assert_eq!(show.title, "Solo");
    assert!(show.description.is_none());
    assert!(show.feed_url.is_none());
    assert!(show.artwork_url.is_none());
    assert!(show.categories.is_empty());
}

#[test]
fn parse_rejects_wrong_kind() {
    let err = parse_kind_10154(30074, "id", "pk", "", &full_tags()).unwrap_err();
    assert!(matches!(
        err,
        ParseError::WrongKind {
            expected: KIND_NIP_F4_SHOW,
            got: 30074
        }
    ));
}

#[test]
fn parse_requires_a_title_or_content() {
    // No title tag, empty content.
    let tags = vec![vec!["feed".into(), "https://x.example/rss".into()]];
    let err = parse_kind_10154(KIND_NIP_F4_SHOW, "id", "pk", "", &tags).unwrap_err();
    assert_eq!(err, ParseError::MissingTag("title"));
}

#[test]
fn parse_falls_back_title_to_content_prefix() {
    let tags = vec![vec!["feed".into(), "https://x.example/rss".into()]];
    let show = parse_kind_10154(
        KIND_NIP_F4_SHOW,
        "id",
        "pk",
        "Content-as-title fallback",
        &tags,
    )
    .expect("parse");
    assert_eq!(show.title, "Content-as-title fallback");
    // Description falls back to content too.
    assert_eq!(show.description.as_deref(), Some("Content-as-title fallback"));
}

#[test]
fn parse_rejects_empty_title_tag() {
    // Title tag present but value is empty — first_tag_value drops it,
    // and with no content fallback the parse fails with MissingTag.
    let tags = vec![vec!["title".into(), String::new()]];
    let err = parse_kind_10154(KIND_NIP_F4_SHOW, "id", "pk", "", &tags).unwrap_err();
    assert_eq!(err, ParseError::MissingTag("title"));
}

#[test]
fn parse_ignores_unknown_tags() {
    let tags = vec![
        vec!["title".into(), "Show".into()],
        vec!["foreign".into(), "value".into()],
        vec!["e".into(), "ref-id".into()],
    ];
    let show = parse_kind_10154(KIND_NIP_F4_SHOW, "id", "pk", "", &tags).expect("parse");
    assert_eq!(show.title, "Show");
    assert!(show.categories.is_empty());
}

// ── parse_event_json ──────────────────────────────────────────────────

#[test]
fn parse_event_json_handles_full_event() {
    let json = r#"{
        "id": "abc123",
        "pubkey": "deadbeef",
        "kind": 10154,
        "created_at": 1700000000,
        "content": "show notes",
        "tags": [
            ["title", "Test"],
            ["feed", "https://feeds.example.com/x.rss"]
        ]
    }"#;
    let show = parse_event_json(json).expect("decode");
    assert_eq!(show.event_id, "abc123");
    assert_eq!(show.author_pubkey, "deadbeef");
    assert_eq!(show.title, "Test");
    assert_eq!(
        show.feed_url.as_deref(),
        Some("https://feeds.example.com/x.rss")
    );
    // Content used as description fallback when no summary tag.
    assert_eq!(show.description.as_deref(), Some("show notes"));
}

#[test]
fn parse_event_json_drops_wrong_kind() {
    let json = r#"{
        "id": "id", "pubkey": "pk", "kind": 1,
        "tags": [["title","X"]], "content": ""
    }"#;
    assert!(parse_event_json(json).is_none());
}

#[test]
fn parse_event_json_drops_missing_title() {
    let json = r#"{
        "id": "id", "pubkey": "pk", "kind": 10154,
        "tags": [], "content": ""
    }"#;
    assert!(parse_event_json(json).is_none());
}

#[test]
fn parse_event_json_drops_garbage() {
    assert!(parse_event_json("not json").is_none());
    assert!(parse_event_json("{}").is_none());
    assert!(parse_event_json("[]").is_none());
}

#[test]
fn parse_event_json_ignores_unknown_envelope_fields() {
    // Forward-compat: relay wrappers may add metadata around the
    // event ("relays": [...], "score": 0.42, …). We only care about
    // the canonical NIP-01 fields.
    let json = r#"{
        "id": "id1", "pubkey": "pk1", "kind": 10154,
        "created_at": 0, "sig": "...",
        "extra": {"score": 0.42},
        "tags": [["title","Y"]], "content": ""
    }"#;
    let show = parse_event_json(json).expect("decode");
    assert_eq!(show.title, "Y");
}

// ── parse_kind_54 ─────────────────────────────────────────────────────────

fn full_episode_tags() -> Vec<Vec<String>> {
    vec![
        vec!["title".into(), "Ep 1".into()],
        vec!["description".into(), "Episode about Rust".into()],
        vec!["duration".into(), "3600".into()],
        vec!["image".into(), "https://img.example/ep1.jpg".into()],
        vec!["audio".into(), "https://audio.example/ep1.mp3".into(), "audio/mpeg".into()],
        vec![
            "chapters".into(),
            "https://chapters.example/ep1.json".into(),
            "application/json+chapters".into(),
        ],
        vec![
            "transcript".into(),
            "https://transcript.example/ep1.vtt".into(),
            "text/vtt".into(),
        ],
    ]
}

#[test]
fn parse_kind_54_collects_every_field() {
    let ep = parse_kind_54(
        KIND_NIP_F4_EPISODE,
        "ev-id",
        "podcast-pk",
        1_700_000_000,
        "",
        &full_episode_tags(),
    )
    .expect("parse");
    assert_eq!(ep.event_id, "ev-id");
    assert_eq!(ep.author_pubkey, "podcast-pk");
    assert_eq!(ep.title, "Ep 1");
    assert_eq!(ep.description.as_deref(), Some("Episode about Rust"));
    assert_eq!(ep.duration_secs, Some(3600.0));
    assert_eq!(ep.image_url.as_deref(), Some("https://img.example/ep1.jpg"));
    assert_eq!(ep.audio_url, "https://audio.example/ep1.mp3");
    assert_eq!(ep.audio_mime_type.as_deref(), Some("audio/mpeg"));
    assert_eq!(
        ep.chapters_url.as_deref(),
        Some("https://chapters.example/ep1.json")
    );
    assert_eq!(
        ep.transcript_url.as_deref(),
        Some("https://transcript.example/ep1.vtt")
    );
    assert_eq!(ep.transcript_mime_type.as_deref(), Some("text/vtt"));
    assert_eq!(ep.created_at, 1_700_000_000);
}

#[test]
fn parse_kind_54_minimal_only_audio_required() {
    let tags = vec![
        vec!["audio".into(), "https://a.example/ep.mp3".into(), "audio/mpeg".into()],
    ];
    let ep = parse_kind_54(KIND_NIP_F4_EPISODE, "id", "pk", 0, "", &tags).expect("parse");
    assert_eq!(ep.audio_url, "https://a.example/ep.mp3");
    assert!(ep.title.is_empty());
    assert!(ep.description.is_none());
    assert!(ep.duration_secs.is_none());
    assert!(ep.image_url.is_none());
    assert!(ep.chapters_url.is_none());
    assert!(ep.transcript_url.is_none());
}

#[test]
fn parse_kind_54_description_falls_back_to_content() {
    let tags = vec![
        vec!["audio".into(), "https://a.example/ep.mp3".into()],
    ];
    let ep = parse_kind_54(KIND_NIP_F4_EPISODE, "id", "pk", 0, "Content desc", &tags)
        .expect("parse");
    assert_eq!(ep.description.as_deref(), Some("Content desc"));
}

#[test]
fn parse_kind_54_rejects_wrong_kind() {
    let err = parse_kind_54(10154, "id", "pk", 0, "", &full_episode_tags()).unwrap_err();
    assert!(matches!(
        err,
        ParseError::WrongKind {
            expected: KIND_NIP_F4_EPISODE,
            got: 10154
        }
    ));
}

#[test]
fn parse_kind_54_rejects_missing_audio_tag() {
    let tags = vec![vec!["title".into(), "Episode".into()]];
    let err = parse_kind_54(KIND_NIP_F4_EPISODE, "id", "pk", 0, "", &tags).unwrap_err();
    assert!(matches!(err, ParseError::MissingTag("audio") | ParseError::MissingAudioUrl));
}

#[test]
fn parse_kind_54_rejects_empty_audio_url() {
    let tags = vec![vec!["audio".into(), String::new()]];
    let err = parse_kind_54(KIND_NIP_F4_EPISODE, "id", "pk", 0, "", &tags).unwrap_err();
    assert_eq!(err, ParseError::MissingAudioUrl);
}

#[test]
fn parse_kind_54_ignores_unknown_tags() {
    let tags = vec![
        vec!["audio".into(), "https://a.example/ep.mp3".into()],
        vec!["foreign".into(), "value".into()],
    ];
    let ep = parse_kind_54(KIND_NIP_F4_EPISODE, "id", "pk", 0, "", &tags).expect("parse");
    assert_eq!(ep.audio_url, "https://a.example/ep.mp3");
}

/// Round-trip: `episode_to_episode_tags` → `parse_kind_54` preserves all fields.
#[test]
fn parse_kind_54_round_trips_with_builder() {
    use podcast_core::types::episode::Episode;
    use podcast_core::types::podcast::PodcastId;
    use url::Url;
    use uuid::Uuid;
    use crate::build::{episode_to_episode_tags, ImetaInfo};

    let podcast_id = PodcastId::new(Uuid::nil());
    let mut ep = Episode::new(
        podcast_id,
        "https://feeds.example/ep.rss",
        "ep-guid-1",
        "Round-Trip Episode".to_string(),
        Url::parse("https://audio.example/ep.mp3").unwrap(),
        chrono::Utc::now(),
    );
    ep.description = "A great episode".to_string();
    ep.duration_secs = Some(1800.0);
    ep.enclosure_mime_type = Some("audio/mpeg".to_string());
    ep.image_url = Some(Url::parse("https://img.example/ep.jpg").unwrap());

    let tags = episode_to_episode_tags(&ep);
    let parsed = parse_kind_54(
        KIND_NIP_F4_EPISODE,
        "event-id-round-trip",
        "podcast-pk",
        1_700_000_000,
        "",
        &tags,
    )
    .expect("parse round-trip");

    assert_eq!(parsed.title, "Round-Trip Episode");
    assert_eq!(parsed.description.as_deref(), Some("A great episode"));
    assert_eq!(parsed.duration_secs, Some(1800.0));
    assert_eq!(parsed.audio_url, "https://audio.example/ep.mp3");
    assert_eq!(parsed.audio_mime_type.as_deref(), Some("audio/mpeg"));
    assert_eq!(parsed.image_url.as_deref(), Some("https://img.example/ep.jpg"));
}
