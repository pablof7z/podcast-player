use super::*;
use chrono::{TimeZone, Utc};
use podcast_core::types::episode::{Episode, EpisodeId};
use podcast_core::types::podcast::PodcastId;
use podcast_core::types::transcript::TranscriptKind;
use url::Url;
use uuid::Uuid;
fn fixture() -> Episode {
    let mut ep = Episode::new(
        PodcastId::generate(),
        "https://media.example/feed.xml",
        "publisher-guid",
        "Pilot",
        Url::parse("https://media.example/ep.m4a").unwrap(),
        Utc.timestamp_opt(1_700_000_000, 0).unwrap(),
    );
    // Pinned id so the d-tag assertions below stay stable. Real callers
    // either let `Episode::new` derive the id from `(feed_url, guid)` or
    // override it with a source-specific derivation (NIP-74 d-tag).
    ep.id = EpisodeId::new(
        Uuid::parse_str("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee").unwrap(),
    );
    ep.description = "First episode".into();
    ep.duration_secs = Some(1800.0);
    ep
}
#[test]
fn d_tag_uses_episode_id_with_prefix() {
    let ep = fixture();
    assert_eq!(
        episode_d_tag(&ep),
        "podcast:item:guid:aaaaaaaabbbbccccddddeeeeeeeeeeee"
    );
}
#[test]
fn minimal_episode_emits_required_tags() {
    let ep = fixture();
    let tags = episode_to_episode_tags(&ep, "agent-pk", "show-d");
    let names: Vec<&str> = tags.iter().filter_map(|t| t.first().map(String::as_str)).collect();
    assert_eq!(
        names,
        vec!["d", "title", "published_at", "a", "summary", "duration", "imeta"]
    );
    assert_eq!(
        tags[3],
        vec!["a".to_string(), "10154:agent-pk:show-d".into()]
    );
    assert_eq!(
        tags[2],
        vec!["published_at".to_string(), "1700000000".into()]
    );
}
#[test]
fn imeta_uses_default_mime_when_not_supplied() {
    let ep = fixture();
    let tags = episode_to_episode_tags(&ep, "pk", "d");
    let imeta = tags.iter().find(|t| t.first().map(String::as_str) == Some("imeta")).expect("imeta present");
    assert_eq!(imeta[1], "url https://media.example/ep.m4a");
    assert_eq!(imeta[2], "m audio/mp4");
    // duration is auto-folded from episode.duration_secs.
    assert!(imeta.iter().any(|p| p == "duration 1800"));
}
#[test]
fn imeta_includes_hash_and_size_when_supplied() {
    let ep = fixture();
    let imeta_info = ImetaInfo {
        mime_type: Some("audio/m4a".into()),
        sha256_hex: Some("deadbeef".into()),
        size_bytes: Some(99),
        duration_secs: Some(1800),
    };
    let tags = episode_to_episode_tags_with_imeta(&ep, "pk", "d", &imeta_info);
    let imeta = tags.iter().find(|t| t.first().map(String::as_str) == Some("imeta")).expect("imeta present");
    assert_eq!(imeta[1], "url https://media.example/ep.m4a");
    assert_eq!(imeta[2], "m audio/m4a");
    assert_eq!(imeta[3], "x deadbeef");
    assert_eq!(imeta[4], "size 99");
    assert_eq!(imeta[5], "duration 1800");
}
#[test]
fn full_episode_includes_chapters_and_transcript() {
    let mut ep = fixture();
    ep.chapters_url = Some(Url::parse("https://c.example/c.json").unwrap());
    ep.publisher_transcript_url = Some(Url::parse("https://t.example/t.vtt").unwrap());
    ep.publisher_transcript_type = Some(TranscriptKind::Vtt);
    ep.image_url = Some(Url::parse("https://img.example/cover.jpg").unwrap());
    let tags = episode_to_episode_tags(&ep, "pk", "show-d");
    let chapters = tags.iter().find(|t| t.first().map(String::as_str) == Some("chapters")).expect("chapters tag");
    assert_eq!(chapters[1], "https://c.example/c.json");
    assert_eq!(chapters[2], "application/json+chapters");
    let transcript = tags.iter().find(|t| t.first().map(String::as_str) == Some("transcript")).expect("transcript tag");
    assert_eq!(transcript[1], "https://t.example/t.vtt");
    assert_eq!(transcript[2], "text/vtt");
    let image = tags.iter().find(|t| t.first().map(String::as_str) == Some("image")).expect("image tag");
    assert_eq!(image[1], "https://img.example/cover.jpg");
}

