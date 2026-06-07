use super::*;
use crate::player::AdSegment;
use podcast_core::AdKind;
fn seg(start: f64, end: f64) -> AdSegment {
    AdSegment::new(start, end, AdKind::Midroll)
}
#[test]
fn ad_segments_for_returns_empty_when_unknown() {
    let store = PodcastStore::new();
    assert!(store.ad_segments_for("ep-x").is_empty());
}
#[test]
fn set_then_get_round_trips() {
    let mut store = PodcastStore::new();
    store.set_ad_segments_for("ep-1", vec![seg(30.0, 60.0)]);
    let got = store.ad_segments_for("ep-1");
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].start_secs, 30.0);
}
#[test]
fn set_empty_removes_entry() {
    let mut store = PodcastStore::new();
    store.set_ad_segments_for("ep-1", vec![seg(30.0, 60.0)]);
    store.set_ad_segments_for("ep-1", vec![]);
    assert!(store.ad_segments_for("ep-1").is_empty());
}
#[test]
fn auto_skip_toggle_round_trips() {
    let mut store = PodcastStore::new();
    assert!(!store.auto_skip_ads_enabled());
    store.set_auto_skip_ads_enabled(true);
    assert!(store.auto_skip_ads_enabled());
    store.set_auto_skip_ads_enabled(false);
    assert!(!store.auto_skip_ads_enabled());
}
#[test]
fn idempotent_toggle_is_safe() {
    let mut store = PodcastStore::new();
    store.set_auto_skip_ads_enabled(true);
    store.set_auto_skip_ads_enabled(true);
    assert!(store.auto_skip_ads_enabled());
}
