use super::*;
use chrono::{TimeZone, Utc};
use podcast_core::{Episode, Podcast, PodcastId};
use url::Url;
use uuid::Uuid;
fn make_podcast(title: &str) -> Podcast {
    Podcast::new(title)
}
fn make_episode(podcast_id: PodcastId, title: &str, ts: i64) -> Episode {
    Episode::new(
        podcast_id,
        "https://example.com/feed.xml",
        format!("guid-{}", Uuid::new_v4()),
        title,
        Url::parse("https://example.com/audio.mp3").unwrap(),
        Utc.timestamp_opt(ts, 0).single().unwrap(),
    )
}
#[test]
fn collect_candidates_returns_all_episodes() {
    let mut store = PodcastStore::new();
    let p1 = make_podcast("Show A");
    let p1_id = p1.id;
    let p2 = make_podcast("Show B");
    let p2_id = p2.id;
    store.subscribe(p1, vec![
        make_episode(p1_id, "A-1", 100),
        make_episode(p1_id, "A-2", 200),
    ]);
    store.subscribe(p2, vec![make_episode(p2_id, "B-1", 300)]);
    let cands = collect_candidates(&store);
    assert_eq!(cands.len(), 3);
    // Show titles come through.
    let titles: std::collections::HashSet<&str> =
        cands.iter().map(|c| c.podcast_title.as_str()).collect();
    assert!(titles.contains("Show A"));
    assert!(titles.contains("Show B"));
}
#[test]
fn refresh_picks_writes_into_slot_and_bumps_rev() {
    let mut s = PodcastStore::new();
    let p = make_podcast("Refresh Show");
    let pid = p.id;
    s.subscribe(p, vec![make_episode(pid, "ep-1", 100)]);
    let store = Arc::new(Mutex::new(s));
    let slot = Arc::new(Mutex::new(Vec::<AgentPickSummary>::new()));
    let rev = Arc::new(AtomicU64::new(0));
    refresh_picks_into_slot(&store, &slot, &rev);
    let written = slot.lock().unwrap();
    assert_eq!(written.len(), 1);
    assert_eq!(written[0].podcast_title, "Refresh Show");
    assert_eq!(rev.load(Ordering::Relaxed), 1);
}
#[test]
fn handle_refresh_returns_ok_envelope_and_populates_slot() {
    let mut s = PodcastStore::new();
    let p = make_podcast("Envelope Show");
    let pid = p.id;
    s.subscribe(p, vec![make_episode(pid, "ep-1", 100)]);
    let store = Arc::new(Mutex::new(s));
    let slot = Arc::new(Mutex::new(Vec::<AgentPickSummary>::new()));
    let rev = Arc::new(AtomicU64::new(0));
    let resp = handle_refresh(&store, &slot, &rev);
    assert_eq!(resp["ok"], true);
    assert_eq!(slot.lock().unwrap().len(), 1);
}
#[test]
fn refresh_picks_on_empty_store_yields_empty_slot() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let slot = Arc::new(Mutex::new(Vec::<AgentPickSummary>::new()));
    let rev = Arc::new(AtomicU64::new(0));
    refresh_picks_into_slot(&store, &slot, &rev);
    assert!(slot.lock().unwrap().is_empty());
    // Slot rev still bumps — keeps the iOS poll loop simple.
    assert_eq!(rev.load(Ordering::Relaxed), 1);
}

