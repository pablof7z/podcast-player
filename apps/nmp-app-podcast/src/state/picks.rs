//! Picks substate — Step 3 of the god-root consolidation.
//!
//! Owns the slot and the re-entrancy guard that were previously mirrored:
//!
//! * `picks` — AI agent picks, recomputed heuristically after every feed
//!   refresh and on explicit `podcast.picks.refresh` dispatches.
//!   **Derived** durability (rebuilt from persisted library + LLM scoring).
//! * `score_in_progress` — writer-only re-entrancy guard that coalesces
//!   repeated auto-refresh calls into a single background LLM scoring pass.
//!   Folded inside this substate (it was duplicated between handler and
//!   `FeedFetchCoordinator`).
//!
//! The free-function pair `handle_refresh` / `handle_refresh_with_signal` in
//! `crate::picks_handler` is replaced by `PicksState::handle` and
//! `PicksState::auto_refresh`.  The `_with_signal` fork disappears:
//! `infra.bump()` unifies both.
//!
//! ## Concurrency correctness
//!
//! Both a manual `podcast.picks.refresh` dispatch and the async subscribe
//! completion in `FeedFetchCoordinator` used to spawn concurrent LLM scoring
//! passes because each held its OWN `picks_score_in_progress` guard.  This
//! substate owns the SINGLE canonical guard.  `FeedFetchCoordinator` holds a
//! clone of `state.picks` and calls `state.picks.auto_refresh()` — no guard
//! on the coordinator side.
//!
//! ## File-length ceiling
//!
//! AGENTS.md hard limit is 500 lines.

use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};

use crate::ffi::actions::picks_module::PicksAction;
use crate::ffi::projections::AgentPickSummary;
use crate::picks_handler::{handle_refresh_inner, refresh_picks_into_slot};
use crate::state::slot::Derived;
use crate::state::{Infra, Slot};
use crate::store::PodcastStore;

/// Picks feature substate.
///
/// Constructed once in `PodcastAppState::new` and referenced via
/// `state.picks` on both seams.
pub struct PicksState {
    /// AI agent picks (heuristic + LLM-scored).  Derived durability.
    pub picks: Slot<Vec<AgentPickSummary>, Derived>,
    /// Re-entrancy guard: set `true` when a background LLM scoring pass
    /// is spawned, cleared when it finishes.  Owned here — NOT mirrored
    /// on `FeedFetchCoordinator`.
    pub score_in_progress: Arc<AtomicBool>,
    /// Rev + signal + runtime.
    infra: Infra,
    /// The canonical persisted library.
    store: Arc<Mutex<PodcastStore>>,
}

impl PicksState {
    /// Production constructor — called from `PodcastAppState::new`.
    pub fn new(infra: Infra, store: Arc<Mutex<PodcastStore>>) -> Self {
        Self {
            picks: Slot::new(Vec::new()),
            score_in_progress: Arc::new(AtomicBool::new(false)),
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

    /// Clone current picks for the snapshot projection.
    pub fn picks_snapshot(&self) -> Vec<AgentPickSummary> {
        self.picks.lock().ok().map(|p| p.clone()).unwrap_or_default()
    }

    // ── Action handler ────────────────────────────────────────────────────

    /// Route a single `podcast.picks.*` action.
    ///
    /// Currently only one action: `PicksAction::Refresh`.
    pub fn handle(&self, _action: PicksAction) -> serde_json::Value {
        self.auto_refresh()
    }

    /// Stamp the heuristic immediately, then (if not already running) spawn
    /// a background LLM scoring pass.
    ///
    /// Called from both the explicit `podcast.picks` action arm and the
    /// `auto_refresh_picks` trigger in `PodcastHostOpHandler` +
    /// `FeedFetchCoordinator`.  Using ONE call site with ONE guard eliminates
    /// the duplicate-guard race described in the module doc.
    pub fn auto_refresh(&self) -> serde_json::Value {
        handle_refresh_inner(
            &self.store,
            &self.picks.share(),
            &self.infra.rev,
            &self.infra.runtime,
            &self.score_in_progress,
            self.infra.signal.clone(),
        )
    }

    /// Synchronous heuristic stamp (no LLM pass, no guard).
    ///
    /// Used in fast-path contexts where only the heuristic is needed (e.g.
    /// early in a feed refresh before the LLM pass is scheduled).
    pub fn refresh_heuristic(&self) {
        refresh_picks_into_slot(&self.store, &self.picks.share(), &self.infra.rev);
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::Ordering;
    use std::sync::{Arc, Mutex};

    use podcast_core::{Episode, Podcast};
    use url::Url;

    use crate::ffi::actions::picks_module::PicksAction;
    use crate::store::PodcastStore;

    use super::*;

    fn make_state_with_episodes() -> PicksState {
        let mut store = PodcastStore::new();
        let podcast = Podcast::new("Tech Talk");
        let pid = podcast.id;
        let ep = Episode::new(
            pid,
            "https://example.com/feed.xml",
            "guid-1",
            "Episode One",
            Url::parse("https://example.com/1.mp3").unwrap(),
            chrono::Utc::now(),
        );
        store.subscribe(podcast, vec![ep]);
        PicksState::for_test(Arc::new(Mutex::new(store)))
    }

    #[test]
    fn handle_refresh_stamps_picks_slot() {
        let state = make_state_with_episodes();
        let rev0 = state.infra.rev();
        let out = state.handle(PicksAction::Refresh);
        assert_eq!(out["ok"], true);
        let picks = state.picks_snapshot();
        assert!(!picks.is_empty(), "should have at least one pick");
        assert!(state.infra.rev() > rev0, "refresh must bump rev");
    }

    #[test]
    fn score_in_progress_guard_prevents_concurrent_llm_pass() {
        let state = make_state_with_episodes();
        // Manually lock the guard to simulate an in-flight LLM pass.
        state
            .score_in_progress
            .store(true, Ordering::Relaxed);
        let out = state.auto_refresh();
        // Heuristic stamp still runs; LLM pass is skipped.
        assert_eq!(out["ok"], true);
        assert_eq!(out["status"], "already_running");
        // Release the guard.
        state
            .score_in_progress
            .store(false, Ordering::Relaxed);
    }

    #[test]
    fn refresh_heuristic_populates_slot_without_llm() {
        let state = make_state_with_episodes();
        let rev0 = state.infra.rev();
        state.refresh_heuristic();
        assert!(!state.picks_snapshot().is_empty());
        assert!(state.infra.rev() > rev0);
    }
}
