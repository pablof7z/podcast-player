use super::*;
use podcast_core::{Episode, Podcast, PodcastId};
use url::Url;
use uuid::Uuid;
fn fixture_episode(podcast_id: PodcastId, title: &str) -> Episode {
    Episode::new(
        podcast_id,
        "https://example.com/feed.xml",
        format!("guid-{}", Uuid::new_v4()),
        title,
        Url::parse("https://example.com/audio.mp3").unwrap(),
        chrono::Utc::now(),
    )
}
#[test]
fn set_and_clear_owner_pubkey_hex_round_trip() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Owned");
    let id_str = podcast.id.0.to_string();
    store.subscribe(podcast, vec![]);
    store.set_owner_pubkey_hex(&id_str, "abc123".into());
    assert_eq!(
        store.podcast_by_id_str(&id_str).and_then(|p| p.owner_pubkey_hex.clone()),
        Some("abc123".into())
    );
    store.clear_owner_pubkey_hex(&id_str);
    assert_eq!(
        store.podcast_by_id_str(&id_str).and_then(|p| p.owner_pubkey_hex.clone()),
        None
    );
}
#[test]
fn set_owner_pubkey_hex_silently_ignores_unknown_podcast() {
    let mut store = PodcastStore::new();
    // No panic, no state change.
    store.set_owner_pubkey_hex("never-subscribed", "abc".into());
    store.clear_owner_pubkey_hex("never-subscribed");
    assert_eq!(store.podcast_count(), 0);
}
#[test]
fn episode_with_podcast_clone_returns_pair_for_known_episode() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Source");
    let pid = podcast.id;
    let ep = fixture_episode(pid, "Pilot");
    let eid_str = ep.id.0.to_string();
    store.subscribe(podcast, vec![ep]);
    let (p_out, e_out) = store
        .episode_with_podcast_clone(&eid_str)
        .expect("found");
    assert_eq!(p_out.id, pid);
    assert_eq!(e_out.title, "Pilot");
}
#[test]
fn episode_with_podcast_clone_returns_none_for_unknown_episode() {
    let store = PodcastStore::new();
    assert!(store.episode_with_podcast_clone("no-such-episode").is_none());
}

