//! Categories substate — Step 4 of the god-root consolidation.
//!
//! Owns the slot and the re-entrancy guard that were previously mirrored:
//!
//! * `cache` — AI categorization cache: episode_id → Vec<category_label>.
//!   **Derived** durability (rebuilt from persisted library + LLM/heuristic
//!   passes).
//! * `in_progress` — writer-only re-entrancy guard that coalesces repeated
//!   auto-categorize calls into a single background LLM pass.
//!   Folded inside this substate (it was duplicated between handler and
//!   `FeedFetchCoordinator`).
//!
//! ## Concurrency correctness
//!
//! Both a manual `podcast.categorize.run` dispatch and the async subscribe
//! completion in `FeedFetchCoordinator` used to spawn concurrent LLM
//! categorization passes because each held its OWN `categorization_in_progress`
//! guard.  This substate owns the SINGLE canonical guard.
//! `FeedFetchCoordinator` holds a clone of the `in_progress` Arc and the
//! `cache` Arc, sourced from `app_state.categories`.
//!
//! ## File-length ceiling
//!
//! AGENTS.md hard limit is 500 lines.

use std::collections::HashMap;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};

use crate::categorization::{
    handle_categorize_episode, handle_run as categorization_run_inner,
    handle_run_with_signal as categorization_run_with_signal_inner,
};
use crate::ffi::actions::categorization_module::CategorizationAction;
use crate::state::slot::Derived;
use crate::state::{Infra, Slot};
use crate::store::PodcastStore;

/// Categories feature substate.
///
/// Constructed once in `PodcastAppState::new` and referenced via
/// `state.categories` on both seams.
pub struct CategoriesState {
    /// Episode-id → category-labels mapping (heuristic + LLM-improved).
    /// Derived durability — rebuilt on demand.
    pub cache: Slot<HashMap<String, Vec<String>>, Derived>,
    /// Re-entrancy guard: set `true` when a background LLM categorization pass
    /// is spawned, cleared when it finishes.  Owned here — NOT mirrored on
    /// `FeedFetchCoordinator`.
    pub in_progress: Arc<AtomicBool>,
    /// Rev + signal + runtime.
    infra: Infra,
    /// The canonical persisted library.
    store: Arc<Mutex<PodcastStore>>,
}

impl CategoriesState {
    /// Production constructor — called from `PodcastAppState::new`.
    pub fn new(infra: Infra, store: Arc<Mutex<PodcastStore>>) -> Self {
        Self {
            cache: Slot::new(HashMap::new()),
            in_progress: Arc::new(AtomicBool::new(false)),
            infra,
            store,
        }
    }

    /// Test constructor.
    #[cfg(test)]
    pub fn for_test(store: Arc<Mutex<PodcastStore>>) -> Self {
        Self::new(Infra::for_test(), store)
    }

    // ── Snapshot projection ───────────────────────────────────────────────

    /// Clone current categories cache for the snapshot projection.
    pub fn categories_snapshot(&self) -> HashMap<String, Vec<String>> {
        self.cache
            .lock()
            .ok()
            .map(|c| c.clone())
            .unwrap_or_default()
    }

    // ── Action handler ────────────────────────────────────────────────────

    /// Route a single `podcast.categorize.*` action.
    pub fn handle(&self, action: CategorizationAction) -> serde_json::Value {
        match action {
            CategorizationAction::Run => self.auto_run(),
            CategorizationAction::CategorizeEpisode { episode_id } => {
                handle_categorize_episode(
                    &self.store,
                    &self.cache.share(),
                    &self.infra.rev,
                    episode_id,
                )
            }
        }
    }

    /// Re-run categorization over the whole library.
    ///
    /// Phase 1 (synchronous keyword pass) runs inline; Phase 2 (LLM pass)
    /// is spawned on the shared runtime if `in_progress` is not already set.
    /// Called from both the explicit `podcast.categorize.run` action arm and
    /// the `auto_categorize` trigger in `PodcastHostOpHandler` +
    /// `FeedFetchCoordinator`.
    pub fn auto_run(&self) -> serde_json::Value {
        if let Some(signal) = self.infra.signal.clone() {
            categorization_run_with_signal_inner(
                &self.store,
                &self.cache.share(),
                &self.infra.rev,
                &self.infra.runtime,
                &self.in_progress,
                signal,
            )
        } else {
            categorization_run_inner(
                &self.store,
                &self.cache.share(),
                &self.infra.rev,
                &self.infra.runtime,
                &self.in_progress,
            )
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use podcast_core::{Episode, Podcast};
    use url::Url;

    use crate::ffi::actions::categorization_module::CategorizationAction;
    use crate::store::PodcastStore;

    use super::*;

    fn make_state_with_episode(title: &str, description: &str) -> CategoriesState {
        let mut store = PodcastStore::new();
        let podcast = Podcast::new("Tech Talk");
        let pid = podcast.id;
        let mut ep = Episode::new(
            pid,
            "https://example.com/feed.xml",
            "guid-1",
            title,
            Url::parse("https://example.com/1.mp3").unwrap(),
            chrono::Utc::now(),
        );
        ep.description = description.to_owned();
        store.subscribe(podcast, vec![ep]);
        CategoriesState::for_test(Arc::new(Mutex::new(store)))
    }

    #[test]
    fn handle_run_populates_cache() {
        let state = make_state_with_episode(
            "AI and Machine Learning Trends",
            "Deep dive into neural networks and automation.",
        );
        let rev0 = state.infra.rev();
        let out = state.handle(CategorizationAction::Run);
        assert_eq!(out["ok"], true);
        let cache = state.categories_snapshot();
        // At least one episode should pick up a category label.
        assert!(
            cache.values().any(|v| !v.is_empty()),
            "keyword pass should assign at least one label"
        );
        assert!(state.infra.rev() > rev0, "run must bump rev");
    }

    #[test]
    fn categorize_episode_returns_labels() {
        let mut store = PodcastStore::new();
        let podcast = Podcast::new("Show");
        let pid = podcast.id;
        let mut ep = Episode::new(
            pid,
            "https://example.com/feed.xml",
            "guid-ep",
            "Python Programming Tutorial",
            Url::parse("https://example.com/ep.mp3").unwrap(),
            chrono::Utc::now(),
        );
        ep.description = "Learn python coding and software engineering".to_owned();
        let ep_id = ep.id.0.to_string();
        store.subscribe(podcast, vec![ep]);
        let state = CategoriesState::for_test(Arc::new(Mutex::new(store)));
        let out = state.handle(CategorizationAction::CategorizeEpisode {
            episode_id: ep_id,
        });
        assert_eq!(out["ok"], true);
        let cats = out["categories"].as_array().expect("categories array");
        assert!(!cats.is_empty(), "should assign at least one category");
    }
}
