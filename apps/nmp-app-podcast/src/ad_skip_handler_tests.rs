use super::*;
use podcast_core::AdKind;
fn seg(start: f64, end: f64) -> AdSegment {
    AdSegment::new(start, end, AdKind::Midroll)
}
fn rev() -> Arc<AtomicU64> {
    Arc::new(AtomicU64::new(1))
}
#[test]
fn set_auto_skip_ads_propagates_to_store_and_actor() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let actor = Arc::new(Mutex::new(PlayerActor::new()));
    let r = rev();
    let res = handle_set_auto_skip_ads(&store, &actor, &r, true);
    assert_eq!(res["ok"], true);
    assert!(store.lock().unwrap().auto_skip_ads_enabled());
    assert!(actor.lock().unwrap().auto_skip_ads());
    assert!(r.load(Ordering::Relaxed) > 1);
}
#[test]
fn set_ad_segments_writes_to_store() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let actor = Arc::new(Mutex::new(PlayerActor::new()));
    let r = rev();
    let segs = vec![seg(30.0, 60.0)];
    let res = handle_set_ad_segments(&store, &actor, &r, "ep-1".into(), segs.clone());
    assert_eq!(res["ok"], true);
    let stored = store.lock().unwrap().ad_segments_for("ep-1").to_vec();
    assert_eq!(stored.len(), 1);
    assert_eq!(stored[0].start_secs, 30.0);
    // Actor untouched — the episode isn't loaded.
    assert!(actor.lock().unwrap().ad_segments().is_empty());
}
#[test]
fn set_ad_segments_refreshes_active_actor_when_episode_matches() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let actor = Arc::new(Mutex::new(PlayerActor::new()));
    let r = rev();
    actor
        .lock()
        .unwrap()
        .stage_load("ep-1", Some("pod-1".into()), "https://ex.com", 0.0);
    let segs = vec![seg(30.0, 60.0)];
    let _ = handle_set_ad_segments(&store, &actor, &r, "ep-1".into(), segs.clone());
    assert_eq!(actor.lock().unwrap().ad_segments().len(), 1);
}
#[test]
fn hydrate_actor_for_play_copies_store_into_actor() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let actor = Arc::new(Mutex::new(PlayerActor::new()));
    {
        let mut s = store.lock().unwrap();
        s.set_ad_segments_for("ep-1", vec![seg(30.0, 60.0)]);
        s.set_auto_skip_ads_enabled(true);
    }
    hydrate_actor_for_play(&store, &actor, "ep-1");
    let a = actor.lock().unwrap();
    assert_eq!(a.ad_segments().len(), 1);
    assert!(a.auto_skip_ads());
}

