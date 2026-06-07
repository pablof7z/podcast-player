use super::*;
use podcast_core::{Episode, Podcast, TranscriptKind};
fn make_episode(podcast_id: podcast_core::PodcastId) -> Episode {
    let mut episode = Episode::new(
        podcast_id,
        "https://example.com/feed.xml",
        "guid-transcript",
        "Transcript Episode",
        url::Url::parse("https://example.com/audio.mp3").unwrap(),
        chrono::Utc::now(),
    );
    episode.publisher_transcript_url =
        Some(url::Url::parse("https://example.com/transcript.vtt").unwrap());
    episode.publisher_transcript_type = Some(TranscriptKind::Vtt);
    episode
}
#[test]
fn episode_publisher_transcript_returns_url_and_kind() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Transcript Show");
    let episode = make_episode(podcast.id);
    let id = episode.id.0.to_string();
    store.subscribe(podcast, vec![episode]);
    let (url, kind) = store
        .episode_publisher_transcript(&id)
        .expect("transcript info");
    assert_eq!(url, "https://example.com/transcript.vtt");
    assert_eq!(kind, TranscriptKind::Vtt);
}
#[test]
fn episode_publisher_transcript_returns_none_when_no_url() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("No Transcript Show");
    let episode = Episode::new(
        podcast.id,
        "https://example.com/feed.xml",
        "guid",
        "Episode",
        url::Url::parse("https://example.com/audio.mp3").unwrap(),
        chrono::Utc::now(),
    );
    let id = episode.id.0.to_string();
    store.subscribe(podcast, vec![episode]);
    assert!(store.episode_publisher_transcript(&id).is_none());
}
#[test]
fn episode_publisher_transcript_defaults_kind_to_json() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Show");
    let mut episode = Episode::new(
        podcast.id,
        "https://example.com/feed.xml",
        "guid",
        "Episode",
        url::Url::parse("https://example.com/audio.mp3").unwrap(),
        chrono::Utc::now(),
    );
    episode.publisher_transcript_url =
        Some(url::Url::parse("https://example.com/transcript").unwrap());
    episode.publisher_transcript_type = None;
    let id = episode.id.0.to_string();
    store.subscribe(podcast, vec![episode]);
    let (_url, kind) = store.episode_publisher_transcript(&id).expect("info");
    assert_eq!(kind, TranscriptKind::Json);
}
