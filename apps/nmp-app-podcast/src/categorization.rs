//! Actor-thread glue for the heuristic categorizer
//! ([`crate::ffi::actions::categorization_module`]).
//!
//! Wraps the pure `categorize_text` keyword matcher with the locking +
//! revision-bump dance that every `PodcastHostOpHandler` op needs:
//!
//! * `handle_run` — scan every episode in [`PodcastStore`], compute its
//!   label vector, and replace the kernel-side categorizer cache. Bumps
//!   `rev` so the next snapshot tick picks up the new labels. Returns
//!   `{"ok":true}`.
//! * `handle_categorize_episode` — same shape but for a single episode.
//!   Useful when the iOS shell wants to refresh one row without
//!   re-scanning the library. Returns
//!   `{"ok":true,"categories":["…"]}`.
//!
//! Locking discipline: `store` is read first into a small `Vec` of
//! `(episode_id, title, description)` triples, then the lock is dropped
//! before [`categorize_text`] runs the heuristic. The cache write
//! re-acquires its own lock. Snapshot reads observe a consistent
//! `HashMap` because `build_snapshot_payload` clones the whole map
//! under a short lock.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use crate::ffi::actions::categorization_module::categorize_text;
use crate::store::PodcastStore;

/// Re-run the categorizer over every episode in `store`.
///
/// Replaces the existing `cache` contents wholesale; episodes that have
/// since been removed from the library drop their labels. Returns the
/// number of episodes that picked up at least one category (the rest
/// are stored as empty vecs so the snapshot still skips them via
/// `Vec::is_empty`).
pub(crate) fn handle_run(
    store: &Arc<Mutex<PodcastStore>>,
    cache: &Arc<Mutex<HashMap<String, Vec<String>>>>,
    rev: &AtomicU64,
) -> serde_json::Value {
    let snapshot: Vec<(String, String, String)> = match store.lock() {
        Ok(s) => s
            .all_podcasts()
            .into_iter()
            .flat_map(|(_podcast, episodes)| {
                episodes.iter().map(|ep| {
                    (
                        ep.id.0.to_string(),
                        ep.title.clone(),
                        ep.description.clone(),
                    )
                }).collect::<Vec<_>>()
            })
            .collect(),
        Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
    };

    let mut next: HashMap<String, Vec<String>> = HashMap::with_capacity(snapshot.len());
    let mut categorized: usize = 0;
    for (id, title, description) in snapshot {
        let cats = categorize_text(&title, &description);
        if !cats.is_empty() {
            categorized += 1;
        }
        next.insert(id, cats);
    }

    match cache.lock() {
        Ok(mut c) => {
            *c = next;
            rev.fetch_add(1, Ordering::Relaxed);
            serde_json::json!({"ok": true, "categorized": categorized})
        }
        Err(_) => serde_json::json!({"ok": false, "error": "categorizer cache poisoned"}),
    }
}

/// Categorize a single episode, identified by its hyphenated UUID string.
/// Writes the labels into `cache` and bumps `rev`. Returns the labels
/// in a `categories` array.
pub(crate) fn handle_categorize_episode(
    store: &Arc<Mutex<PodcastStore>>,
    cache: &Arc<Mutex<HashMap<String, Vec<String>>>>,
    rev: &AtomicU64,
    episode_id: String,
) -> serde_json::Value {
    let (title, description) = match store.lock() {
        Ok(s) => match find_episode_text(&s, &episode_id) {
            Some(t) => t,
            None => {
                return serde_json::json!({
                    "ok": false,
                    "error": format!("episode not found: {episode_id}")
                })
            }
        },
        Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
    };

    let cats = categorize_text(&title, &description);

    match cache.lock() {
        Ok(mut c) => {
            c.insert(episode_id, cats.clone());
            rev.fetch_add(1, Ordering::Relaxed);
            serde_json::json!({"ok": true, "categories": cats})
        }
        Err(_) => serde_json::json!({"ok": false, "error": "categorizer cache poisoned"}),
    }
}

/// Look up `(title, description)` for an episode by id-string.
/// Returns `None` if the id doesn't match any episode in any subscribed
/// podcast.
fn find_episode_text(store: &PodcastStore, episode_id: &str) -> Option<(String, String)> {
    for (_podcast, episodes) in store.all_podcasts() {
        for ep in episodes {
            if ep.id.0.to_string() == episode_id {
                return Some((ep.title.clone(), ep.description.clone()));
            }
        }
    }
    None
}

#[cfg(test)]
#[path = "categorization_tests.rs"]
mod tests;
