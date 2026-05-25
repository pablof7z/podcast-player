//! Inbox triage (feature #31).
//!
//! Owns both the **projection** (turn the store + dismissed-set into the
//! `Vec<InboxItem>` that surfaces on `PodcastUpdate.inbox`) and the
//! **action handlers** (`triage` / `dismiss` / `mark_listened`).
//!
//! Lives in its own crate-root module rather than under `ffi/` because the
//! projection is consumed by `ffi::snapshot::build_snapshot_payload` and
//! the handlers are consumed by `host_op_handler::PodcastHostOpHandler`.
//! Keeping it sibling-level lets both call sites import without crossing
//! through the snapshot module's private surface.
//!
//! ## Heuristic scoring (stub)
//!
//! The current scorer is intentionally trivial: every unlistened episode
//! is scored by a recency curve over the past 30 days, normalized to
//! `0.0..=1.0`. The `priority_reason` is the bucket the score lands in
//! ("Just published" / "Recent" / "From your library"). Real AI triage
//! (LLM classification by guest, topic, prior engagement) is a follow-up.
//! The wire contract (`InboxItem.priority_score` + `priority_reason`)
//! does not change when that swap happens.

use std::collections::HashSet;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use chrono::Utc;

use crate::ffi::actions::inbox_module::InboxAction;
use crate::ffi::projections::InboxItem;
use crate::store::PodcastStore;

/// Build the `Vec<InboxItem>` for one snapshot tick.
///
/// Walks every subscribed podcast, picks the unlistened-and-not-dismissed
/// episodes, scores them by recency, and returns the list sorted
/// highest-score-first.
///
/// Reads `store` + `dismissed` under their respective short-duration locks;
/// callers must not hold either lock when calling.
pub fn build_inbox(
    store: &Arc<Mutex<PodcastStore>>,
    dismissed: &Arc<Mutex<HashSet<String>>>,
) -> Vec<InboxItem> {
    let dismissed_snapshot: HashSet<String> = match dismissed.lock() {
        Ok(d) => d.clone(),
        Err(_) => return Vec::new(),
    };

    let store_guard = match store.lock() {
        Ok(s) => s,
        Err(_) => return Vec::new(),
    };

    let now = Utc::now().timestamp();
    let mut items: Vec<InboxItem> = Vec::new();

    for (podcast, episodes) in store_guard.all_podcasts() {
        for ep in episodes {
            if ep.played {
                continue;
            }
            let ep_id = ep.id.0.to_string();
            if dismissed_snapshot.contains(&ep_id) {
                continue;
            }

            let published_at = ep.pub_date.timestamp();
            let (priority_score, priority_reason) = score(now, published_at);

            items.push(InboxItem {
                episode_id: ep_id,
                episode_title: ep.title.clone(),
                podcast_id: podcast.id.0.to_string(),
                podcast_title: podcast.title.clone(),
                artwork_url: ep
                    .image_url
                    .as_ref()
                    .map(|u| u.to_string())
                    .or_else(|| podcast.image_url.as_ref().map(|u| u.to_string())),
                published_at,
                duration_secs: ep.duration_secs,
                priority_score,
                priority_reason: Some(priority_reason.to_owned()),
                ai_categories: vec![],
            });
        }
    }

    // Highest score first; ties broken newest-first so the visible order
    // is deterministic when many episodes published near the same time.
    items.sort_by(|a, b| {
        b.priority_score
            .partial_cmp(&a.priority_score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| b.published_at.cmp(&a.published_at))
    });
    items
}

/// Recency-weighted heuristic: score newer episodes higher.
///
/// Returns the score (`0.0..=1.0`) and a short human-readable bucket
/// label that the row caption renders verbatim. The 30-day window is
/// the rough useful lifetime of an inbox item; older episodes get a
/// small but non-zero floor so the inbox isn't empty when the user is
/// catching up on a long-tail show.
fn score(now_unix: i64, published_at_unix: i64) -> (f32, &'static str) {
    const ONE_HOUR: i64 = 3_600;
    const ONE_DAY: i64 = 24 * ONE_HOUR;
    const WINDOW_SECS: i64 = 30 * ONE_DAY;

    let age = (now_unix - published_at_unix).max(0);
    if age < 12 * ONE_HOUR {
        return (1.0, "Just published");
    }
    if age < 3 * ONE_DAY {
        return (0.85, "Recent");
    }
    if age < 7 * ONE_DAY {
        return (0.65, "This week");
    }
    if age < WINDOW_SECS {
        // Linear taper from 0.55 down to 0.20 across the rest of the window.
        let progress = (age - 7 * ONE_DAY) as f32 / (WINDOW_SECS - 7 * ONE_DAY) as f32;
        let score = 0.55 - progress.clamp(0.0, 1.0) * 0.35;
        return (score, "From your library");
    }
    // Long-tail: keep a small floor so the inbox stays useful when the
    // user is on a catch-up binge against an old show.
    (0.15, "From your library")
}

/// Handle a `podcast.inbox.*` action and return the JSON envelope the FFI
/// surface emits back to Swift.
///
/// `Triage` bumps `rev` so the next snapshot poll picks up the (possibly
/// freshly-computed) inbox. The projection itself is built every tick by
/// [`build_inbox`] so there's no cache to invalidate.
///
/// `Dismiss` records the episode id in the dismissed set; the next tick's
/// `build_inbox` filters it out.
///
/// `MarkListened` flips `Episode.played = true` in the store; the next
/// tick's `build_inbox` filters it out (same code path as natural play-to-
/// completion).
pub fn handle_inbox_action(
    action: InboxAction,
    store: &Arc<Mutex<PodcastStore>>,
    dismissed: &Arc<Mutex<HashSet<String>>>,
    rev: &Arc<AtomicU64>,
) -> serde_json::Value {
    match action {
        InboxAction::Triage => {
            rev.fetch_add(1, Ordering::Relaxed);
            serde_json::json!({"ok": true})
        }
        InboxAction::Dismiss { episode_id } => match dismissed.lock() {
            Ok(mut d) => {
                d.insert(episode_id);
                rev.fetch_add(1, Ordering::Relaxed);
                serde_json::json!({"ok": true})
            }
            Err(_) => serde_json::json!({"ok": false, "error": "dismissed_set poisoned"}),
        },
        InboxAction::MarkListened { episode_id } => match store.lock() {
            Ok(mut s) => {
                let _flipped = s.mark_episode_played(&episode_id);
                rev.fetch_add(1, Ordering::Relaxed);
                serde_json::json!({"ok": true})
            }
            Err(_) => serde_json::json!({"ok": false, "error": "store poisoned"}),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;
    use podcast_core::{Episode, Podcast};

    fn fixture_store(now_unix: i64) -> Arc<Mutex<PodcastStore>> {
        let mut store = PodcastStore::new();
        let podcast = Podcast::new("Heuristic Show");
        let podcast_id = podcast.id;

        // Three episodes: 1 hour old, 5 days old, 60 days old.
        let one_hour = Episode::new(
            podcast_id,
            "https://example.com/feed.xml",
            "guid-1h",
            "Fresh",
            url::Url::parse("https://ex.com/1.mp3").unwrap(),
            Utc.timestamp_opt(now_unix - 3_600, 0).unwrap(),
        );
        let five_days = Episode::new(
            podcast_id,
            "https://example.com/feed.xml",
            "guid-5d",
            "Mid",
            url::Url::parse("https://ex.com/2.mp3").unwrap(),
            Utc.timestamp_opt(now_unix - 5 * 24 * 3_600, 0).unwrap(),
        );
        let sixty_days = Episode::new(
            podcast_id,
            "https://example.com/feed.xml",
            "guid-60d",
            "Old",
            url::Url::parse("https://ex.com/3.mp3").unwrap(),
            Utc.timestamp_opt(now_unix - 60 * 24 * 3_600, 0).unwrap(),
        );
        store.subscribe(podcast, vec![one_hour, five_days, sixty_days]);
        Arc::new(Mutex::new(store))
    }

    #[test]
    fn build_inbox_returns_unlistened_episodes_sorted_by_score() {
        let now = Utc::now().timestamp();
        let store = fixture_store(now);
        let dismissed = Arc::new(Mutex::new(HashSet::<String>::new()));

        let items = build_inbox(&store, &dismissed);
        assert_eq!(items.len(), 3);

        // Just-published first, long-tail last.
        assert_eq!(items[0].episode_title, "Fresh");
        assert_eq!(items[2].episode_title, "Old");
        assert!(items[0].priority_score >= items[1].priority_score);
        assert!(items[1].priority_score >= items[2].priority_score);
    }

    #[test]
    fn build_inbox_skips_dismissed_episodes() {
        let now = Utc::now().timestamp();
        let store = fixture_store(now);
        let dismissed = Arc::new(Mutex::new(HashSet::<String>::new()));

        // Dismiss the freshest episode.
        let fresh_id = {
            let s = store.lock().unwrap();
            let (_, eps) = s.all_podcasts()[0];
            eps.iter().find(|e| e.title == "Fresh").unwrap().id.0.to_string()
        };
        dismissed.lock().unwrap().insert(fresh_id);

        let items = build_inbox(&store, &dismissed);
        assert_eq!(items.len(), 2);
        assert!(items.iter().all(|i| i.episode_title != "Fresh"));
    }

    #[test]
    fn build_inbox_skips_played_episodes() {
        let now = Utc::now().timestamp();
        let store = fixture_store(now);
        let dismissed = Arc::new(Mutex::new(HashSet::<String>::new()));

        // Mark "Fresh" as played in the store.
        let fresh_id = {
            let s = store.lock().unwrap();
            let (_, eps) = s.all_podcasts()[0];
            eps.iter().find(|e| e.title == "Fresh").unwrap().id.0.to_string()
        };
        store.lock().unwrap().mark_episode_played(&fresh_id);

        let items = build_inbox(&store, &dismissed);
        assert_eq!(items.len(), 2);
        assert!(items.iter().all(|i| i.episode_title != "Fresh"));
    }

    #[test]
    fn handle_dismiss_records_in_set_and_bumps_rev() {
        let now = Utc::now().timestamp();
        let store = fixture_store(now);
        let dismissed = Arc::new(Mutex::new(HashSet::<String>::new()));
        let rev = Arc::new(AtomicU64::new(0));

        let result = handle_inbox_action(
            InboxAction::Dismiss {
                episode_id: "ep-7".into(),
            },
            &store,
            &dismissed,
            &rev,
        );
        assert_eq!(result["ok"], true);
        assert!(dismissed.lock().unwrap().contains("ep-7"));
        assert_eq!(rev.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn handle_triage_only_bumps_rev() {
        let now = Utc::now().timestamp();
        let store = fixture_store(now);
        let dismissed = Arc::new(Mutex::new(HashSet::<String>::new()));
        let rev = Arc::new(AtomicU64::new(0));

        let result = handle_inbox_action(InboxAction::Triage, &store, &dismissed, &rev);
        assert_eq!(result["ok"], true);
        assert_eq!(rev.load(Ordering::Relaxed), 1);
        // No dismissed entries added.
        assert!(dismissed.lock().unwrap().is_empty());
    }

    #[test]
    fn handle_mark_listened_flips_store_flag() {
        let now = Utc::now().timestamp();
        let store = fixture_store(now);
        let dismissed = Arc::new(Mutex::new(HashSet::<String>::new()));
        let rev = Arc::new(AtomicU64::new(0));

        let fresh_id = {
            let s = store.lock().unwrap();
            let (_, eps) = s.all_podcasts()[0];
            eps.iter().find(|e| e.title == "Fresh").unwrap().id.0.to_string()
        };

        let result = handle_inbox_action(
            InboxAction::MarkListened {
                episode_id: fresh_id.clone(),
            },
            &store,
            &dismissed,
            &rev,
        );
        assert_eq!(result["ok"], true);
        assert_eq!(rev.load(Ordering::Relaxed), 1);

        let played = store
            .lock()
            .unwrap()
            .all_podcasts()
            .iter()
            .flat_map(|(_, eps)| eps.iter())
            .find(|e| e.id.0.to_string() == fresh_id)
            .map(|e| e.played)
            .unwrap_or(false);
        assert!(played);
    }

    #[test]
    fn score_buckets_match_documented_thresholds() {
        let now = 1_000_000_000;
        assert_eq!(score(now, now - 3_600).1, "Just published");
        assert_eq!(score(now, now - 2 * 24 * 3_600).1, "Recent");
        assert_eq!(score(now, now - 5 * 24 * 3_600).1, "This week");
        assert_eq!(score(now, now - 20 * 24 * 3_600).1, "From your library");
        assert_eq!(score(now, now - 100 * 24 * 3_600).1, "From your library");
    }

    #[test]
    fn inbox_item_round_trips_with_all_fields() {
        let item = InboxItem {
            episode_id: "ep-42".into(),
            episode_title: "Pilot".into(),
            podcast_id: "pod-1".into(),
            podcast_title: "Some Show".into(),
            artwork_url: Some("https://ex.com/art.png".into()),
            published_at: 1_700_000_000,
            duration_secs: Some(2_700.0),
            priority_score: 0.87,
            priority_reason: Some("Just published".into()),
            ai_categories: vec![],
        };
        let json = serde_json::to_string(&item).expect("encode");
        let decoded: InboxItem = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, item);
    }

    #[test]
    fn mark_episode_played_flips_flag_then_idempotent() {
        // Lives here (vs. `store::tests`) so it stays next to the only
        // production caller — `handle_inbox_action(MarkListened…)`.
        let now = Utc::now().timestamp();
        let store = fixture_store(now);
        let fresh_id = {
            let s = store.lock().unwrap();
            let (_, eps) = s.all_podcasts()[0];
            eps.iter().find(|e| e.title == "Fresh").unwrap().id.0.to_string()
        };
        let mut guard = store.lock().unwrap();
        assert!(guard.mark_episode_played(&fresh_id));
        assert!(!guard.mark_episode_played(&fresh_id));
        assert!(!guard.mark_episode_played("not-a-real-uuid"));
    }

    #[test]
    fn inbox_item_omits_none_optionals() {
        let item = InboxItem {
            episode_id: "ep-1".into(),
            episode_title: "Pilot".into(),
            podcast_id: "pod-1".into(),
            podcast_title: "Some Show".into(),
            artwork_url: None,
            published_at: 1_700_000_000,
            duration_secs: None,
            priority_score: 0.5,
            priority_reason: None,
            ai_categories: vec![],
        };
        let json = serde_json::to_string(&item).expect("encode");
        assert!(!json.contains("artwork_url"));
        assert!(!json.contains("duration_secs"));
        assert!(!json.contains("priority_reason"));
        assert!(json.contains("\"priority_score\":0.5"));
    }
}
