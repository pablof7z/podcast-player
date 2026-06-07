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
        store
            .podcast_by_id_str(&id_str)
            .and_then(|p| p.owner_pubkey_hex.clone()),
        Some("abc123".into())
    );
    store.clear_owner_pubkey_hex(&id_str);
    assert_eq!(
        store
            .podcast_by_id_str(&id_str)
            .and_then(|p| p.owner_pubkey_hex.clone()),
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
    let (p_out, e_out) = store.episode_with_podcast_clone(&eid_str).expect("found");
    assert_eq!(p_out.id, pid);
    assert_eq!(e_out.title, "Pilot");
}
#[test]
fn episode_with_podcast_clone_returns_none_for_unknown_episode() {
    let store = PodcastStore::new();
    assert!(store
        .episode_with_podcast_clone("no-such-episode")
        .is_none());
}

#[test]
fn create_podcast_creates_feedless_row() {
    let mut store = PodcastStore::new();
    let id = Uuid::new_v4().to_string();
    let ok = store.create_podcast(
        &id,
        "Agent Show".into(),
        "Desc".into(),
        "Agent".into(),
        None,
        Some("https://img/a.png".into()),
        Some("en".into()),
        vec!["Tech".into()],
        podcast_core::NostrVisibility::Public,
        false,
    );
    assert!(ok);
    let p = store.podcast_by_id_str(&id).expect("row present");
    assert_eq!(p.title, "Agent Show");
    assert_eq!(p.author, "Agent");
    assert!(p.feed_url.is_none());
    assert!(!p.title_is_placeholder);
    assert_eq!(
        p.image_url.as_ref().map(|u| u.as_str()),
        Some("https://img/a.png")
    );
    assert_eq!(p.categories, vec!["Tech".to_string()]);
}

#[test]
fn create_podcast_stores_feed_url_and_placeholder_flag() {
    // External-play placeholder path: a feed-backed row whose title is a
    // provisional fallback awaiting metadata hydration.
    let mut store = PodcastStore::new();
    let id = Uuid::new_v4().to_string();
    let ok = store.create_podcast(
        &id,
        "example.com".into(),
        String::new(),
        String::new(),
        Some("https://example.com/feed.xml".into()),
        None,
        None,
        vec![],
        podcast_core::NostrVisibility::Public,
        true,
    );
    assert!(ok);
    let p = store.podcast_by_id_str(&id).expect("row present");
    assert_eq!(
        p.feed_url.as_ref().map(|u| u.as_str()),
        Some("https://example.com/feed.xml")
    );
    assert!(p.title_is_placeholder);
}

#[test]
fn create_podcast_rejects_bad_uuid() {
    let mut store = PodcastStore::new();
    let ok = store.create_podcast(
        "not-a-uuid",
        "T".into(),
        String::new(),
        String::new(),
        None,
        None,
        None,
        vec![],
        podcast_core::NostrVisibility::Public,
        false,
    );
    assert!(!ok);
    assert_eq!(store.podcast_count(), 0);
}

#[test]
fn update_owned_metadata_partial_keeps_unset_fields() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Original");
    let id = podcast.id.0.to_string();
    store.subscribe(podcast, vec![]);
    let ok = store.update_owned_metadata(&id, Some("New".into()), None, None, None, None);
    assert!(ok);
    let p = store.podcast_by_id_str(&id).unwrap();
    assert_eq!(p.title, "New");
    // description untouched (was empty).
    assert_eq!(p.description, "");
}

#[test]
fn update_owned_metadata_applies_author_and_visibility() {
    // Anti-clobber guarantee: author + visibility must mutate the kernel row
    // so the next snapshot push does not revert a Swift-side edit.
    let mut store = PodcastStore::new();
    let mut podcast = Podcast::new("Show");
    podcast.author = "Old Author".into();
    podcast.nostr_visibility = podcast_core::NostrVisibility::Private;
    let id = podcast.id.0.to_string();
    store.subscribe(podcast, vec![]);
    let ok = store.update_owned_metadata(
        &id,
        None,
        None,
        Some("New Author".into()),
        None,
        Some(podcast_core::NostrVisibility::Public),
    );
    assert!(ok);
    let p = store.podcast_by_id_str(&id).unwrap();
    assert_eq!(p.author, "New Author");
    assert_eq!(p.nostr_visibility, podcast_core::NostrVisibility::Public);
}

#[test]
fn update_owned_metadata_ignores_unparseable_artwork() {
    let mut store = PodcastStore::new();
    let mut podcast = Podcast::new("Art");
    podcast.image_url = Some(Url::parse("https://old/a.png").unwrap());
    let id = podcast.id.0.to_string();
    store.subscribe(podcast, vec![]);
    store.update_owned_metadata(&id, None, None, None, Some("::::not a url".into()), None);
    let p = store.podcast_by_id_str(&id).unwrap();
    // Prior artwork preserved, not blanked.
    assert_eq!(
        p.image_url.as_ref().map(|u| u.as_str()),
        Some("https://old/a.png")
    );
}

#[test]
fn update_owned_metadata_returns_false_for_unknown() {
    let mut store = PodcastStore::new();
    assert!(!store.update_owned_metadata("nope", Some("x".into()), None, None, None, None));
}

/// Insert a feed-less podcast row for the episode tests below.
fn seed_podcast(store: &mut PodcastStore, pid: &str) {
    store.create_podcast(
        pid,
        "Agent Generated".into(),
        String::new(),
        "Agent".into(),
        None,
        None,
        None,
        vec![],
        NostrVisibility::Public,
        false,
    );
}

#[test]
fn add_episode_local_file_is_downloaded() {
    let mut store = PodcastStore::new();
    let pid = Uuid::new_v4().to_string();
    seed_podcast(&mut store, &pid);

    // A real temp file so the file:// URL + byte-count path resolves.
    let dir = std::env::temp_dir();
    let audio = dir.join(format!("agent-{}.m4a", Uuid::new_v4()));
    std::fs::write(&audio, b"fake-m4a-bytes").unwrap();
    let audio_path = audio.to_string_lossy().to_string();

    let eid = Uuid::new_v4().to_string();
    let ok = store.add_episode(
        &pid,
        &eid,
        "Episode One".into(),
        &audio_path,
        "Episode description".into(),
        Some(123.5),
        None,
        vec![
            EpisodeChapter {
                start_secs: 0.0,
                title: "Intro".into(),
                image_url: None,
                source_episode_id: None,
            },
            EpisodeChapter {
                start_secs: 30.0,
                title: "Clip".into(),
                image_url: Some("https://img/clip.png".into()),
                source_episode_id: Some("source-ep-id".into()),
            },
        ],
        Some("hello world transcript".into()),
    );
    assert!(ok);

    let parsed = Uuid::parse_str(&eid).unwrap();
    let ep_id = EpisodeId(parsed);
    let pod_id = PodcastId(Uuid::parse_str(&pid).unwrap());
    let eps = store.episodes_for(pod_id);
    assert_eq!(eps.len(), 1);
    let ep = &eps[0];
    assert_eq!(ep.id, ep_id);
    assert_eq!(ep.title, "Episode One");
    assert_eq!(ep.description, "Episode description");
    assert_eq!(ep.duration_secs, Some(123.5));
    assert!(!ep.played);
    assert_eq!(ep.position_secs, 0.0);
    assert!(matches!(
        ep.download_state,
        podcast_core::types::download::DownloadState::Downloaded { .. }
    ));
    // Episode artwork inherited from the first chapter that has one.
    assert_eq!(
        ep.image_url.as_ref().map(|u| u.as_str()),
        Some("https://img/clip.png")
    );
    let chapters = ep.chapters.as_ref().expect("chapters present");
    assert_eq!(chapters.len(), 2);
    assert!(chapters.iter().all(|c| c.is_ai_generated));
    assert_eq!(
        chapters[1].source_episode_id.as_deref(),
        Some("source-ep-id")
    );
    assert_eq!(
        chapters[1].image_url.as_ref().map(|u| u.as_str()),
        Some("https://img/clip.png")
    );

    // Side-maps: download_path projection source + flat transcript + empty ads.
    assert_eq!(store.local_path_for(&ep_id), Some(audio_path.as_str()));
    assert_eq!(store.transcript_for(&eid), Some("hello world transcript"));
    assert!(store.ad_segments_for(&eid).is_empty());

    let _ = std::fs::remove_file(&audio);
}

#[test]
fn add_episode_http_enclosure_is_not_downloaded() {
    // Remote enclosure (RSS / external audio): NotDownloaded, no local path,
    // explicit image_url + description honored, no chapters.
    let mut store = PodcastStore::new();
    let pid = Uuid::new_v4().to_string();
    seed_podcast(&mut store, &pid);

    let eid = Uuid::new_v4().to_string();
    let ok = store.add_episode(
        &pid,
        &eid,
        "Remote Episode".into(),
        "https://example.com/audio.mp3",
        "Remote description".into(),
        Some(600.0),
        Some("https://img/episode.png".into()),
        vec![],
        None,
    );
    assert!(ok);

    let pod_id = PodcastId(Uuid::parse_str(&pid).unwrap());
    let parsed = Uuid::parse_str(&eid).unwrap();
    let ep_id = EpisodeId(parsed);
    let eps = store.episodes_for(pod_id);
    assert_eq!(eps.len(), 1);
    let ep = &eps[0];
    assert_eq!(ep.title, "Remote Episode");
    assert_eq!(ep.description, "Remote description");
    assert_eq!(ep.enclosure_url.as_str(), "https://example.com/audio.mp3");
    assert!(matches!(
        ep.download_state,
        podcast_core::types::download::DownloadState::NotDownloaded
    ));
    // No local path side-map for a remote enclosure.
    assert_eq!(store.local_path_for(&ep_id), None);
    // Explicit image_url wins.
    assert_eq!(
        ep.image_url.as_ref().map(|u| u.as_str()),
        Some("https://img/episode.png")
    );
    assert!(ep.chapters.is_none());
}

#[test]
fn add_episode_is_idempotent_on_episode_id() {
    let mut store = PodcastStore::new();
    let pid = Uuid::new_v4().to_string();
    seed_podcast(&mut store, &pid);
    let pod_id = PodcastId(Uuid::parse_str(&pid).unwrap());
    let eid = Uuid::new_v4().to_string();

    let insert = |store: &mut PodcastStore, title: &str| {
        store.add_episode(
            &pid,
            &eid,
            title.into(),
            "/tmp/agent-episode.m4a",
            String::new(),
            None,
            None,
            vec![],
            None,
        )
    };
    assert!(insert(&mut store, "First"));
    assert!(insert(&mut store, "Second"));
    let eps = store.episodes_for(pod_id);
    assert_eq!(eps.len(), 1, "re-add must replace, not duplicate");
    assert_eq!(eps[0].title, "Second");
}

#[test]
fn add_episode_rejects_unknown_podcast() {
    let mut store = PodcastStore::new();
    let ok = store.add_episode(
        &Uuid::new_v4().to_string(),
        &Uuid::new_v4().to_string(),
        "Orphan".into(),
        "/tmp/x.m4a",
        String::new(),
        None,
        None,
        vec![],
        None,
    );
    assert!(!ok);
}

#[test]
fn add_episode_rejects_bad_episode_id() {
    let mut store = PodcastStore::new();
    let pid = Uuid::new_v4().to_string();
    seed_podcast(&mut store, &pid);
    let ok = store.add_episode(
        &pid,
        "not-a-uuid",
        "Bad".into(),
        "/tmp/x.m4a",
        String::new(),
        None,
        None,
        vec![],
        None,
    );
    assert!(!ok);
}

#[test]
fn remove_podcast_and_episodes_clears_row_and_episodes() {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("ToDelete");
    let pid = podcast.id;
    let id = pid.0.to_string();
    let ep = fixture_episode(pid, "Ep");
    store.subscribe(podcast, vec![ep]);
    assert_eq!(store.podcast_count(), 1);
    store.remove_podcast_and_episodes(&id);
    assert_eq!(store.podcast_count(), 0);
    assert!(store.podcast_by_id_str(&id).is_none());
    assert!(store.episodes_for(pid).is_empty());
}
