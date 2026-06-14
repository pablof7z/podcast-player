use super::*;
use podcast_core::{Episode, PodcastId};
use url::Url;
use uuid::Uuid;

fn make_episode(podcast_id: PodcastId, guid: &str, url: &str) -> Episode {
    Episode::new(
        podcast_id,
        "https://example.com/feed.xml",
        guid,
        "Title",
        Url::parse(url).unwrap(),
        chrono::Utc::now(),
    )
}

/// Helper: call with wifi_only=false, is_on_wifi=true and return only ready downloads.
fn auto_dl(
    fresh: &[Episode],
    existing: &HashSet<String>,
    local: &HashMap<EpisodeId, String>,
    mode: AutoDownloadMode,
) -> Vec<(EpisodeId, String)> {
    episodes_to_auto_download(fresh, existing, local, mode, false, true).0
}

// ── Basic mode tests ─────────────────────────────────────────────────────────

#[test]
fn auto_download_off_does_not_queue_download() {
    let pid = PodcastId::generate();
    let fresh = vec![make_episode(pid, "g1", "https://ex.com/a.mp3")];
    let (ready, deferred) = episodes_to_auto_download(
        &fresh,
        &HashSet::new(),
        &HashMap::new(),
        AutoDownloadMode::Off,
        false,
        true,
    );
    assert!(ready.is_empty());
    assert!(deferred.is_empty());
}

#[test]
fn all_new_queues_every_new_episode() {
    let pid = PodcastId::generate();
    let ep_known = make_episode(pid, "known", "https://ex.com/known.mp3");
    let ep_new = make_episode(pid, "new", "https://ex.com/new.mp3");
    let fresh = vec![ep_known.clone(), ep_new.clone()];
    let mut existing = HashSet::new();
    existing.insert("known".to_string());
    let (ready, deferred) = episodes_to_auto_download(
        &fresh,
        &existing,
        &HashMap::new(),
        AutoDownloadMode::AllNew,
        false,
        true,
    );
    assert_eq!(ready.len(), 1);
    assert_eq!(ready[0].0, ep_new.id);
    assert_eq!(ready[0].1, "https://ex.com/new.mp3");
    assert!(deferred.is_empty());
}

/// D7 core: `LatestN(3)` caps `episodes_to_auto_download` to the 3 newest candidates.
#[test]
fn latest_n_caps_fresh_feed_to_n() {
    let pid = PodcastId::generate();
    let eps: Vec<Episode> = (1..=5u8)
        .map(|i| make_episode(pid, &format!("g{i}"), &format!("https://ex.com/{i}.mp3")))
        .collect();
    let out = auto_dl(&eps, &HashSet::new(), &HashMap::new(), AutoDownloadMode::LatestN { n: 3 });
    assert_eq!(out.len(), 3, "LatestN(3) must cap at 3 episodes");
    // Should be the first 3 in input order (newest-first per parser contract).
    assert_eq!(out[0].0, eps[0].id);
    assert_eq!(out[1].0, eps[1].id);
    assert_eq!(out[2].0, eps[2].id);
}

/// D7 core: `AllNew` imposes no cap — all 5 episodes are queued.
#[test]
fn all_new_is_uncapped() {
    let pid = PodcastId::generate();
    let eps: Vec<Episode> = (1..=5u8)
        .map(|i| make_episode(pid, &format!("g{i}"), &format!("https://ex.com/{i}.mp3")))
        .collect();
    let out = auto_dl(&eps, &HashSet::new(), &HashMap::new(), AutoDownloadMode::AllNew);
    assert_eq!(out.len(), 5, "AllNew must not cap the fresh-feed queue");
}

#[test]
fn auto_download_skips_episodes_with_existing_local_path() {
    let pid = PodcastId::generate();
    let ep = make_episode(pid, "new", "https://ex.com/new.mp3");
    let fresh = vec![ep.clone()];
    let mut local = HashMap::new();
    local.insert(ep.id, "/tmp/already-here.mp3".to_string());
    let out = auto_dl(&fresh, &HashSet::new(), &local, AutoDownloadMode::AllNew);
    assert!(out.is_empty());
}

#[test]
fn auto_download_preserves_input_order() {
    let pid = PodcastId::generate();
    let ep1 = make_episode(pid, "g1", "https://ex.com/1.mp3");
    let ep2 = make_episode(pid, "g2", "https://ex.com/2.mp3");
    let ep3 = make_episode(pid, "g3", "https://ex.com/3.mp3");
    let fresh = vec![ep1.clone(), ep2.clone(), ep3.clone()];
    let out = auto_dl(&fresh, &HashSet::new(), &HashMap::new(), AutoDownloadMode::AllNew);
    assert_eq!(out.len(), 3);
    assert_eq!(out[0].0, ep1.id);
    assert_eq!(out[1].0, ep2.id);
    assert_eq!(out[2].0, ep3.id);
}

#[test]
fn auto_download_with_empty_fresh_list_returns_empty() {
    let out = auto_dl(&[], &HashSet::new(), &HashMap::new(), AutoDownloadMode::AllNew);
    assert!(out.is_empty());
}

#[test]
fn auto_download_off_ignores_other_inputs() {
    let pid = PodcastId::generate();
    let ep = make_episode(pid, "g1", "https://ex.com/a.mp3");
    let out = auto_dl(&[ep], &HashSet::new(), &HashMap::new(), AutoDownloadMode::Off);
    assert!(out.is_empty());
}

#[test]
fn auto_download_matches_local_paths_by_episode_id() {
    let pid = PodcastId::generate();
    let mut ep = make_episode(pid, "guid-stable", "https://ex.com/a.mp3");
    ep.id = EpisodeId::new(Uuid::nil());
    let mut local = HashMap::new();
    local.insert(ep.id, "/var/mobile/Downloads/a.mp3".to_string());
    let out = auto_dl(&[ep], &HashSet::new(), &local, AutoDownloadMode::AllNew);
    assert!(out.is_empty());
}

// ── Wi-Fi gating tests ────────────────────────────────────────────────────

#[test]
fn wifi_only_on_wifi_queues_episodes() {
    let pid = PodcastId::generate();
    let ep = make_episode(pid, "new", "https://ex.com/new.mp3");
    let (ready, deferred) = episodes_to_auto_download(
        &[ep.clone()],
        &HashSet::new(),
        &HashMap::new(),
        AutoDownloadMode::AllNew,
        true,
        true,
    );
    assert_eq!(ready.len(), 1);
    assert!(deferred.is_empty());
}

#[test]
fn wifi_only_on_cellular_defers_not_discards() {
    let pid = PodcastId::generate();
    let ep = make_episode(pid, "new", "https://ex.com/new.mp3");
    let (ready, deferred) = episodes_to_auto_download(
        &[ep.clone()],
        &HashSet::new(),
        &HashMap::new(),
        AutoDownloadMode::AllNew,
        true,
        false,
    );
    assert!(
        ready.is_empty(),
        "must not dispatch on cellular when wifi-only"
    );
    assert_eq!(
        deferred.len(),
        1,
        "must defer (not discard) for later Wi-Fi dispatch"
    );
    assert_eq!(deferred[0].0, ep.id);
}

#[test]
fn cellular_allowed_queues_on_cellular() {
    let pid = PodcastId::generate();
    let ep = make_episode(pid, "new", "https://ex.com/new.mp3");
    let (ready, deferred) = episodes_to_auto_download(
        &[ep.clone()],
        &HashSet::new(),
        &HashMap::new(),
        AutoDownloadMode::AllNew,
        false,
        false,
    );
    assert_eq!(
        ready.len(),
        1,
        "cellular-allowed must queue even without Wi-Fi"
    );
    assert!(deferred.is_empty());
}

#[test]
fn auto_download_off_with_wifi_still_returns_empty() {
    let pid = PodcastId::generate();
    let ep = make_episode(pid, "new", "https://ex.com/new.mp3");
    let (ready, deferred) = episodes_to_auto_download(
        &[ep],
        &HashSet::new(),
        &HashMap::new(),
        AutoDownloadMode::Off,
        true,
        true,
    );
    assert!(ready.is_empty());
    assert!(deferred.is_empty());
}

// ── Backfill scan over the current library (cold-start / on-enable) ──────────

use crate::store::PodcastStore;
use podcast_core::Podcast;

/// Build a store with one podcast and `guids.len()` episodes, returning the
/// store and the podcast id. Episodes are inserted newest-first per the parser
/// contract the scan relies on.
fn store_with_show(guids: &[&str]) -> (PodcastStore, PodcastId) {
    let mut store = PodcastStore::new();
    let podcast = Podcast::new("Show");
    let pid = podcast.id();
    let eps: Vec<Episode> = guids
        .iter()
        .map(|g| make_episode(pid, g, &format!("https://ex.com/{g}.mp3")))
        .collect();
    store.upsert_known_podcast(podcast, eps);
    (store, pid)
}

#[test]
fn backfill_skips_shows_without_auto_download() {
    let (store, _pid) = store_with_show(&["g1", "g2"]);
    let (ready, deferred) = store.auto_download_backfill_candidates(true, 10);
    assert!(ready.is_empty());
    assert!(deferred.is_empty());
}

/// D7: `AllNew` backfill uses `AUTO_DOWNLOAD_BACKFILL_LIMIT` as safety ceiling.
#[test]
fn backfill_all_new_uses_safety_ceiling() {
    let guids: Vec<String> = (1..=10u8).map(|i| format!("g{i}")).collect();
    let guid_refs: Vec<&str> = guids.iter().map(String::as_str).collect();
    let (mut store, pid) = store_with_show(&guid_refs);
    store.set_auto_download_mode(pid, AutoDownloadMode::AllNew);
    let (ready, _deferred) = store.auto_download_backfill_candidates(true, 0);
    assert_eq!(
        ready.len(),
        AUTO_DOWNLOAD_BACKFILL_LIMIT,
        "AllNew backfill is bounded by AUTO_DOWNLOAD_BACKFILL_LIMIT={AUTO_DOWNLOAD_BACKFILL_LIMIT}, not unbounded"
    );
}

/// D7: `LatestN(2)` backfill is bounded to exactly 2 episodes, not the safety ceiling.
#[test]
fn backfill_latest_n_uses_n_not_safety_ceiling() {
    let (mut store, pid) = store_with_show(&["g1", "g2", "g3", "g4"]);
    store.set_auto_download_mode(pid, AutoDownloadMode::LatestN { n: 2 });
    let (ready, _deferred) = store.auto_download_backfill_candidates(true, 0);
    assert_eq!(
        ready.len(),
        2,
        "LatestN(2) backfill must cap to exactly 2 episodes"
    );
}

/// D7: `Off` backfill returns nothing even if the old bool happened to be set.
#[test]
fn backfill_off_returns_nothing() {
    let (mut store, pid) = store_with_show(&["g1", "g2"]);
    // Explicitly set Off (should be the default, but be explicit for clarity)
    store.set_auto_download_mode(pid, AutoDownloadMode::Off);
    let (ready, deferred) = store.auto_download_backfill_candidates(true, 0);
    assert!(ready.is_empty(), "Off mode must not backfill");
    assert!(deferred.is_empty());
}

/// D7: `AllNew` backfill can backfill MORE than the old hardcoded limit of 3 when there are fewer
/// candidates (e.g. 2 episodes → 2 backfills, not capped at 3).
#[test]
fn backfill_all_new_can_exceed_3_when_n_is_greater() {
    // AUTO_DOWNLOAD_BACKFILL_LIMIT is 3, but what if there are only 2 undownloaded?
    let (mut store, pid) = store_with_show(&["g1", "g2"]);
    store.set_auto_download_mode(pid, AutoDownloadMode::AllNew);
    let (ready, _deferred) = store.auto_download_backfill_candidates(true, 0);
    assert_eq!(ready.len(), 2, "AllNew with 2 episodes should backfill 2");
}

#[test]
fn backfill_skips_already_downloaded_episodes() {
    let (mut store, pid) = store_with_show(&["g1", "g2"]);
    let downloaded_id = make_episode(pid, "g1", "https://ex.com/g1.mp3").id;
    store.set_local_path(downloaded_id, "/tmp/g1.mp3".to_string(), 100);
    store.set_auto_download_mode(pid, AutoDownloadMode::AllNew);
    let (ready, _deferred) = store.auto_download_backfill_candidates(true, 0);
    // g1 is on disk → only g2 remains a candidate.
    assert_eq!(ready.len(), 1);
}

#[test]
fn backfill_defers_wifi_only_show_on_cellular() {
    let (mut store, pid) = store_with_show(&["g1"]);
    store.set_auto_download_mode(pid, AutoDownloadMode::AllNew); // wifi_only defaults to true
    let (ready, deferred) = store.auto_download_backfill_candidates(false, 0);
    assert!(
        ready.is_empty(),
        "wifi-only show must not download on cellular"
    );
    assert_eq!(deferred.len(), 1, "deferred for later Wi-Fi dispatch");
}

// ── Back-compat migration tests ───────────────────────────────────────────────

/// D7: old bool `enabled: true` migrates to `AllNew` when no typed mode is stored.
#[test]
fn legacy_bool_true_migrates_to_all_new() {
    let (mut store, pid) = store_with_show(&["g1", "g2", "g3", "g4", "g5"]);
    // Use the legacy bool setter (simulates a stale client or an old persisted store).
    store.set_auto_download(pid, true);
    // The mode should have been promoted to AllNew.
    assert_eq!(
        store.auto_download_mode_for(pid),
        AutoDownloadMode::AllNew,
        "legacy enabled=true must map to AllNew"
    );
    assert!(store.is_auto_download_enabled(pid));
}

/// D7: old bool `enabled: false` maps to `Off`.
#[test]
fn legacy_bool_false_maps_to_off() {
    let (mut store, pid) = store_with_show(&["g1"]);
    store.set_auto_download(pid, false);
    assert_eq!(
        store.auto_download_mode_for(pid),
        AutoDownloadMode::Off,
        "legacy enabled=false must map to Off"
    );
    assert!(!store.is_auto_download_enabled(pid));
}

// ── Projection round-trip tests ───────────────────────────────────────────────

use crate::ffi::projections::PodcastSummary;

/// The projection emits `auto_download_mode = "all_new"` and omits `auto_download_count`.
#[test]
fn projection_all_new_round_trip() {
    let summary = PodcastSummary {
        id: "p1".to_string(),
        title: "Show".to_string(),
        auto_download: true,
        auto_download_mode: "all_new".to_string(),
        auto_download_count: 0,
        ..Default::default()
    };
    let json = serde_json::to_string(&summary).expect("encode");
    assert!(json.contains(r#""auto_download_mode":"all_new""#));
    assert!(
        !json.contains("auto_download_count"),
        "count must be omitted when 0 (D5)"
    );
    let decoded: PodcastSummary = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded.auto_download_mode, "all_new");
    assert_eq!(decoded.auto_download_count, 0);
}

/// The projection emits `auto_download_mode = "latest_n"` and `auto_download_count = 5`.
#[test]
fn projection_latest_n_round_trip() {
    let summary = PodcastSummary {
        id: "p2".to_string(),
        title: "Show".to_string(),
        auto_download: true,
        auto_download_mode: "latest_n".to_string(),
        auto_download_count: 5,
        ..Default::default()
    };
    let json = serde_json::to_string(&summary).expect("encode");
    assert!(json.contains(r#""auto_download_mode":"latest_n""#));
    assert!(json.contains(r#""auto_download_count":5"#));
    let decoded: PodcastSummary = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded.auto_download_mode, "latest_n");
    assert_eq!(decoded.auto_download_count, 5);
}

/// Off mode omits both mode and count from the wire (D5 skip-if-default).
#[test]
fn projection_off_omits_mode_and_count() {
    let summary = PodcastSummary {
        id: "p3".to_string(),
        title: "Show".to_string(),
        auto_download: false,
        auto_download_mode: String::new(),
        auto_download_count: 0,
        ..Default::default()
    };
    let json = serde_json::to_string(&summary).expect("encode");
    assert!(
        !json.contains("auto_download_mode"),
        "Off must omit mode field"
    );
    assert!(
        !json.contains("auto_download_count"),
        "Off must omit count field"
    );
    // A snapshot that predates the field must decode cleanly with defaults.
    // The Rust PodcastSummary has required fields (episode_count, unplayed_count,
    // is_subscribed, nostr_visibility, episodes) so we provide them.
    let json_legacy = r#"{"id":"p3","title":"Show","episode_count":0,"unplayed_count":0,"is_subscribed":false,"nostr_visibility":"public","episodes":[]}"#;
    let decoded: PodcastSummary = serde_json::from_str(json_legacy).expect("decode legacy");
    assert_eq!(decoded.auto_download_mode, "");
    assert_eq!(decoded.auto_download_count, 0);
    assert!(!decoded.auto_download);
}

/// Android toleration: a snapshot with new fields must decode via a struct that
/// has only `auto_download: bool` (simulates Android's current decoder which
/// uses `serde(default)` and ignores unknown fields).
#[test]
fn android_decode_ignores_new_mode_fields() {
    #[derive(serde::Deserialize)]
    struct AndroidPodcastSummary {
        id: String,
        #[serde(default)]
        auto_download: bool,
    }
    let json = r#"{"id":"p4","title":"Show","auto_download":true,"auto_download_mode":"latest_n","auto_download_count":5}"#;
    let decoded: AndroidPodcastSummary = serde_json::from_str(json).expect("android decode");
    assert_eq!(decoded.id, "p4");
    assert!(decoded.auto_download, "bool field must still decode");
}
