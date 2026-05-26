use super::*;

fn fixture() -> Episode {
    Episode::new(
        PodcastId::generate(),
        "https://example.com/feed.xml",
        "guid-1",
        "Pilot",
        Url::parse("https://example.com/audio.mp3").unwrap(),
        Utc::now(),
    )
}

#[test]
fn episode_round_trip() {
    let value = fixture();
    let json = serde_json::to_string(&value).unwrap();
    let back: Episode = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

#[test]
fn episode_with_chapters_round_trip() {
    let mut value = fixture();
    value.chapters = Some(vec![Chapter::new("Intro", 0.0)]);
    value.publisher_transcript_type = Some(TranscriptKind::Vtt);
    value.triage_decision = Some(TriageDecision::Inbox);
    value.triage_rationale = Some("Has the guest you follow".into());
    let json = serde_json::to_string(&value).unwrap();
    let back: Episode = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

#[test]
fn episode_id_is_stable_for_same_feed_and_guid() {
    let id1 = EpisodeId::from_feed_and_guid("https://feed.example/rss", "ep-1");
    let id2 = EpisodeId::from_feed_and_guid("https://feed.example/rss", "ep-1");
    assert_eq!(id1, id2);
}

#[test]
fn episode_id_differs_for_different_guid() {
    let id1 = EpisodeId::from_feed_and_guid("https://feed.example/rss", "ep-1");
    let id2 = EpisodeId::from_feed_and_guid("https://feed.example/rss", "ep-2");
    assert_ne!(id1, id2);
}

#[test]
fn episode_id_differs_for_different_feed() {
    let id1 = EpisodeId::from_feed_and_guid("https://feed-a.example/rss", "ep-1");
    let id2 = EpisodeId::from_feed_and_guid("https://feed-b.example/rss", "ep-1");
    assert_ne!(id1, id2);
}

#[test]
fn episode_new_derives_id_from_feed_and_guid() {
    let ep = Episode::new(
        PodcastId::generate(),
        "https://feed.example/rss",
        "ep-1",
        "Pilot",
        Url::parse("https://example.com/audio.mp3").unwrap(),
        Utc::now(),
    );
    let expected = EpisodeId::from_feed_and_guid("https://feed.example/rss", "ep-1");
    assert_eq!(ep.id, expected);
}
