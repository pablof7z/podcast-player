//! Clip storage + action handler — owns `Vec<ClipRecord>` and the three
//! `podcast.clip.*` ops (`create`, `delete`, `auto_snip`).
//!
//! Lives in its own module so `host_op_handler.rs` stays under the 500-LOC
//! hard ceiling. `host_op_handler` only contains a small dispatch branch
//! that delegates to `ClipHandler`.
//!
//! ## Storage model
//!
//! Clips are kept in process memory on the actor thread, behind the same
//! `Arc<Mutex<…>>` discipline as `search_results`. Persistence to disk is
//! out of scope for this PR — clips evaporate on app restart. The wire
//! shape (`ffi::projections::ClipSummary`) is what the iOS shell reads;
//! the internal `ClipRecord` captures everything the snapshot builder
//! needs to re-project on every tick.
//!
//! ## Title freshness
//!
//! `ClipRecord` stamps the episode + podcast titles at create time so
//! the iOS list can still render the row when the clip's target episode
//! has been unsubscribed (in which case the library join in
//! `ffi::snapshot::project_clips` returns nothing). When the episode is
//! still in the library, the projection re-joins against the live
//! `PodcastStore` so renames take effect immediately.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use chrono::Utc;
use uuid::Uuid;

use crate::ffi::actions::clip_module::ClipAction;
use crate::ffi::projections::{ClipSummary, PodcastSummary};
use crate::store::PodcastStore;

/// Internal clip record — what the actor thread mutates.
///
/// `episode_title` / `podcast_title` are the values at create time;
/// they're only surfaced when the live library join in
/// `ffi::snapshot::project_clips` misses (episode unsubscribed).
#[derive(Clone, Debug, PartialEq)]
pub struct ClipRecord {
    pub id: String,
    pub episode_id: String,
    pub episode_title: String,
    pub podcast_title: String,
    pub start_secs: f64,
    pub end_secs: f64,
    pub title: Option<String>,
    pub created_at: i64,
}

/// Per-handle clip handler. Holds shared references to the clips Vec,
/// the rev counter, and the store (for episode/podcast lookup at
/// create + auto_snip time).
pub struct ClipHandler {
    clips: Arc<Mutex<Vec<ClipRecord>>>,
    store: Arc<Mutex<PodcastStore>>,
    rev: Arc<AtomicU64>,
}

impl ClipHandler {
    pub fn new(
        clips: Arc<Mutex<Vec<ClipRecord>>>,
        store: Arc<Mutex<PodcastStore>>,
        rev: Arc<AtomicU64>,
    ) -> Self {
        Self { clips, store, rev }
    }

    /// Top-level dispatch from `host_op_handler`.
    pub fn handle(&self, action: ClipAction) -> serde_json::Value {
        match action {
            ClipAction::Create {
                episode_id,
                start_secs,
                end_secs,
                title,
            } => self.handle_create(episode_id, start_secs, end_secs, title),
            ClipAction::Delete { clip_id } => self.handle_delete(clip_id),
            ClipAction::AutoSnip {
                episode_id,
                position_secs,
            } => self.handle_auto_snip(episode_id, position_secs),
        }
    }

    fn handle_create(
        &self,
        episode_id: String,
        start_secs: f64,
        end_secs: f64,
        title: Option<String>,
    ) -> serde_json::Value {
        let Some((ep_title, pod_title, _duration)) = self.episode_meta(&episode_id) else {
            return serde_json::json!({
                "ok": false,
                "error": format!("episode not found: {episode_id}")
            });
        };
        let (start, end) = normalize_range(start_secs, end_secs);
        if !(end > start) {
            return serde_json::json!({
                "ok": false,
                "error": "clip end must be greater than start"
            });
        }
        let id = Uuid::new_v4().to_string();
        let record = ClipRecord {
            id: id.clone(),
            episode_id,
            episode_title: ep_title,
            podcast_title: pod_title,
            start_secs: start,
            end_secs: end,
            title,
            created_at: Utc::now().timestamp(),
        };
        match self.clips.lock() {
            Ok(mut c) => {
                c.push(record);
                self.rev.fetch_add(1, Ordering::Relaxed);
                serde_json::json!({"ok": true, "clip_id": id})
            }
            Err(_) => serde_json::json!({"ok": false, "error": "clips poisoned"}),
        }
    }

    fn handle_delete(&self, clip_id: String) -> serde_json::Value {
        match self.clips.lock() {
            Ok(mut c) => {
                let before = c.len();
                c.retain(|rec| rec.id != clip_id);
                if c.len() != before {
                    self.rev.fetch_add(1, Ordering::Relaxed);
                }
                serde_json::json!({"ok": true})
            }
            Err(_) => serde_json::json!({"ok": false, "error": "clips poisoned"}),
        }
    }

    fn handle_auto_snip(&self, episode_id: String, position_secs: f64) -> serde_json::Value {
        let Some((_, _, duration)) = self.episode_meta(&episode_id) else {
            return serde_json::json!({
                "ok": false,
                "error": format!("episode not found: {episode_id}")
            });
        };
        let pos = position_secs.max(0.0);
        let raw_start = pos - 30.0;
        let raw_end = pos + 30.0;
        let start = raw_start.max(0.0);
        let end = match duration {
            Some(d) if d > 0.0 => raw_end.min(d),
            _ => raw_end,
        };
        self.handle_create(episode_id, start, end, None)
    }

    /// Look up `(episode_title, podcast_title, duration_secs)` for an
    /// episode id. Returns `None` when the episode isn't in the store.
    fn episode_meta(&self, episode_id: &str) -> Option<(String, String, Option<f64>)> {
        let store = self.store.lock().ok()?;
        store.episode_titles_and_duration(episode_id)
    }
}

fn normalize_range(a: f64, b: f64) -> (f64, f64) {
    if a <= b {
        (a, b)
    } else {
        (b, a)
    }
}

/// Project the in-memory `Vec<ClipRecord>` into wire-format
/// `ClipSummary` rows, re-joining against the freshly-built `library`
/// so `episode_title` and `podcast_title` reflect the latest podcast /
/// episode names rather than whatever was current at clip-create time.
/// Clips whose target episode is no longer in the library still
/// surface with the create-time titles frozen on `ClipRecord` so the
/// iOS list can render them rather than silently dropping the row.
///
/// Ordering: newest-first (reverse insertion order). The iOS shell
/// renders the list as-given.
pub(crate) fn project_clips(
    clips: &Mutex<Vec<ClipRecord>>,
    library: &[PodcastSummary],
) -> Vec<ClipSummary> {
    let Ok(clips) = clips.lock() else {
        return Vec::new();
    };
    clips
        .iter()
        .rev()
        .map(|rec| {
            let (ep_title, pod_title) = lookup_titles(library, &rec.episode_id)
                .unwrap_or_else(|| (rec.episode_title.clone(), rec.podcast_title.clone()));
            ClipSummary {
                id: rec.id.clone(),
                episode_id: rec.episode_id.clone(),
                episode_title: ep_title,
                podcast_title: pod_title,
                start_secs: rec.start_secs,
                end_secs: rec.end_secs,
                title: rec.title.clone(),
                created_at: rec.created_at,
            }
        })
        .collect()
}

fn lookup_titles(library: &[PodcastSummary], episode_id: &str) -> Option<(String, String)> {
    for show in library {
        if let Some(ep) = show.episodes.iter().find(|e| e.id == episode_id) {
            return Some((ep.title.clone(), show.title.clone()));
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use podcast_core::{Episode, EpisodeId, Podcast};
    use url::Url;

    fn fresh_store_with_episode(ep_id: &str, duration: Option<f64>) -> Arc<Mutex<PodcastStore>> {
        let mut podcast = Podcast::new("Some Show");
        podcast.feed_url = Some(Url::parse("https://ex.com/rss").unwrap());
        let mut episode = Episode::new(
            podcast.id,
            "https://example.com/feed.xml",
            format!("guid-{}", Uuid::new_v4()),
            "Pilot",
            Url::parse("https://ex.com/ep-1.mp3").unwrap(),
            Utc::now(),
        );
        episode.id = EpisodeId(Uuid::parse_str(ep_id).unwrap());
        episode.duration_secs = duration;
        let store = Arc::new(Mutex::new(PodcastStore::new()));
        store.lock().unwrap().subscribe(podcast, vec![episode]);
        store
    }

    fn fresh_handler(store: Arc<Mutex<PodcastStore>>) -> (ClipHandler, Arc<Mutex<Vec<ClipRecord>>>, Arc<AtomicU64>) {
        let clips = Arc::new(Mutex::new(Vec::new()));
        let rev = Arc::new(AtomicU64::new(0));
        let h = ClipHandler::new(clips.clone(), store, rev.clone());
        (h, clips, rev)
    }

    #[test]
    fn create_rejects_unknown_episode() {
        let store = Arc::new(Mutex::new(PodcastStore::new()));
        let (h, clips, rev) = fresh_handler(store);
        let v = h.handle_create("ghost".into(), 1.0, 5.0, None);
        assert_eq!(v["ok"], false);
        assert!(clips.lock().unwrap().is_empty());
        assert_eq!(rev.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn create_rejects_inverted_range() {
        let ep_id = Uuid::new_v4().to_string();
        let store = fresh_store_with_episode(&ep_id, Some(300.0));
        let (h, clips, _rev) = fresh_handler(store);
        // start == end → 0-length, rejected.
        let v = h.handle_create(ep_id.clone(), 10.0, 10.0, None);
        assert_eq!(v["ok"], false);
        assert!(clips.lock().unwrap().is_empty());
    }

    #[test]
    fn create_swaps_inverted_inputs_into_valid_range() {
        let ep_id = Uuid::new_v4().to_string();
        let store = fresh_store_with_episode(&ep_id, Some(300.0));
        let (h, clips, rev) = fresh_handler(store);
        // start > end → normalize, then accept.
        let v = h.handle_create(ep_id.clone(), 70.0, 10.0, Some("flipped".into()));
        assert_eq!(v["ok"], true);
        assert!(v["clip_id"].is_string());
        let stored = clips.lock().unwrap();
        assert_eq!(stored.len(), 1);
        assert_eq!(stored[0].start_secs, 10.0);
        assert_eq!(stored[0].end_secs, 70.0);
        assert_eq!(rev.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn delete_removes_existing_clip_and_bumps_rev() {
        let ep_id = Uuid::new_v4().to_string();
        let store = fresh_store_with_episode(&ep_id, Some(300.0));
        let (h, clips, rev) = fresh_handler(store);
        let create = h.handle_create(ep_id, 5.0, 25.0, None);
        let clip_id = create["clip_id"].as_str().unwrap().to_owned();
        rev.store(0, Ordering::Relaxed);
        let v = h.handle_delete(clip_id);
        assert_eq!(v["ok"], true);
        assert!(clips.lock().unwrap().is_empty());
        assert_eq!(rev.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn delete_unknown_clip_is_ok_but_does_not_bump_rev() {
        let store = Arc::new(Mutex::new(PodcastStore::new()));
        let (h, _clips, rev) = fresh_handler(store);
        let v = h.handle_delete("nope".into());
        assert_eq!(v["ok"], true);
        assert_eq!(rev.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn auto_snip_uses_plus_minus_30_window() {
        let ep_id = Uuid::new_v4().to_string();
        let store = fresh_store_with_episode(&ep_id, Some(300.0));
        let (h, clips, _rev) = fresh_handler(store);
        let v = h.handle_auto_snip(ep_id, 100.0);
        assert_eq!(v["ok"], true);
        let stored = clips.lock().unwrap();
        assert_eq!(stored.len(), 1);
        assert!((stored[0].start_secs - 70.0).abs() < 1e-9);
        assert!((stored[0].end_secs - 130.0).abs() < 1e-9);
    }

    #[test]
    fn auto_snip_clamps_to_episode_bounds() {
        let ep_id = Uuid::new_v4().to_string();
        let store = fresh_store_with_episode(&ep_id, Some(40.0));
        let (h, clips, _rev) = fresh_handler(store);
        // Near the start — start should clamp to 0.
        let v = h.handle_auto_snip(ep_id.clone(), 5.0);
        assert_eq!(v["ok"], true);
        // Near the end — end should clamp to duration (40.0).
        let _ = h.handle_auto_snip(ep_id, 35.0);
        let stored = clips.lock().unwrap();
        assert_eq!(stored.len(), 2);
        assert_eq!(stored[0].start_secs, 0.0);
        // Second clip: end clamps to 40.0.
        assert!((stored[1].end_secs - 40.0).abs() < 1e-9);
    }

    #[test]
    fn auto_snip_without_known_duration_does_not_clamp_end() {
        let ep_id = Uuid::new_v4().to_string();
        let store = fresh_store_with_episode(&ep_id, None);
        let (h, clips, _rev) = fresh_handler(store);
        let v = h.handle_auto_snip(ep_id, 100.0);
        assert_eq!(v["ok"], true);
        let stored = clips.lock().unwrap();
        assert!((stored[0].end_secs - 130.0).abs() < 1e-9);
    }

    fn library_with_show(ep_id: &str, episode_title: &str, show_title: &str) -> Vec<PodcastSummary> {
        use crate::ffi::projections::EpisodeSummary;
        vec![PodcastSummary {
            id: Uuid::new_v4().to_string(),
            title: show_title.into(),
            episode_count: 1,
            unplayed_count: 0,
            artwork_url: None,
            feed_url: None,
            author: None,
            description: None,
            auto_download: false,
            episodes: vec![EpisodeSummary {
                id: ep_id.into(),
                title: episode_title.into(),
                podcast_id: None,
                podcast_title: Some(show_title.into()),
                ..EpisodeSummary::default()
            }],
        }]
    }

    #[test]
    fn project_clips_picks_up_renamed_titles_from_live_library() {
        // Clip captured with stale titles ("Old Show" / "Old Episode") still in
        // ClipRecord; library now reports new ones. Projection prefers the
        // live names.
        let ep_id = Uuid::new_v4().to_string();
        let clips = Arc::new(Mutex::new(vec![ClipRecord {
            id: "clip-1".into(),
            episode_id: ep_id.clone(),
            episode_title: "Old Episode".into(),
            podcast_title: "Old Show".into(),
            start_secs: 0.0,
            end_secs: 10.0,
            title: None,
            created_at: 1,
        }]));
        let library = library_with_show(&ep_id, "Fresh Episode", "Fresh Show");
        let projected = project_clips(&clips, &library);
        assert_eq!(projected.len(), 1);
        assert_eq!(projected[0].episode_title, "Fresh Episode");
        assert_eq!(projected[0].podcast_title, "Fresh Show");
    }

    #[test]
    fn project_clips_falls_back_to_frozen_titles_when_episode_missing() {
        // Episode no longer in the library (unsubscribed) — projection
        // surfaces the create-time titles so the row still renders.
        let clips = Arc::new(Mutex::new(vec![ClipRecord {
            id: "clip-1".into(),
            episode_id: "ghost-ep".into(),
            episode_title: "Frozen Episode".into(),
            podcast_title: "Frozen Show".into(),
            start_secs: 0.0,
            end_secs: 10.0,
            title: None,
            created_at: 1,
        }]));
        let projected = project_clips(&clips, &[]);
        assert_eq!(projected.len(), 1);
        assert_eq!(projected[0].episode_title, "Frozen Episode");
        assert_eq!(projected[0].podcast_title, "Frozen Show");
    }

    #[test]
    fn project_clips_returns_newest_first() {
        let clips = Arc::new(Mutex::new(vec![
            ClipRecord {
                id: "older".into(),
                episode_id: "ep".into(),
                episode_title: "Ep".into(),
                podcast_title: "Show".into(),
                start_secs: 0.0,
                end_secs: 10.0,
                title: None,
                created_at: 1,
            },
            ClipRecord {
                id: "newer".into(),
                episode_id: "ep".into(),
                episode_title: "Ep".into(),
                podcast_title: "Show".into(),
                start_secs: 0.0,
                end_secs: 10.0,
                title: None,
                created_at: 2,
            },
        ]));
        let projected = project_clips(&clips, &[]);
        assert_eq!(projected.len(), 2);
        assert_eq!(projected[0].id, "newer");
        assert_eq!(projected[1].id, "older");
    }
}
