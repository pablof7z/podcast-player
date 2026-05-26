//! Picks-action `ActionModule` — routes all `"podcast.picks.*"` dispatches.
//!
//! Feature #46 (AI agent picks). The MVP computes picks locally via a
//! heuristic: newest episodes across the user's library, capped per show
//! for diversity, top-N overall. A future LLM-driven projection replaces
//! the compute body without changing the action wire format.
//!
//! Swift encodes every picks action as `{"op":"<variant>"}`. The
//! `#[serde(tag = "op", rename_all = "snake_case")]` discriminator maps
//! the string `op` value to the enum variant. The module's `execute`
//! body forwards the whole action as `ActorCommand::DispatchHostOp` so
//! the `PodcastHostOpHandler` (running on the actor thread) can read the
//! `PodcastStore`, run the heuristic, and stamp the result onto the
//! shared `Arc<Mutex<Vec<AgentPickSummary>>>` slot on `PodcastHandle`.

use serde::{Deserialize, Serialize};

use nmp_core::substrate::ActionModule;
use nmp_core::ActorCommand;

use crate::ffi::projections::AgentPickSummary;

/// Maximum picks the heuristic emits per refresh. The Home rail renders
/// a horizontal card stack — beyond ~10 the diversity-per-show cap stops
/// being meaningful and the rail just becomes a duplicate of the
/// "New Episodes" list below it.
pub const PICKS_LIMIT: usize = 10;

/// Maximum picks selected from any one show. Keeps the rail diverse:
/// without this, a single high-frequency feed (think a daily news show)
/// would monopolize all 10 slots.
pub const PICKS_PER_SHOW_CAP: usize = 2;

/// Wire enum for all `"podcast.picks"` namespace actions.
///
/// `#[serde(tag = "op", rename_all = "snake_case")]` makes the JSON
/// discriminator the lowercase snake-case variant name:
/// `refresh` → `{"op":"refresh"}`.
#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum PicksAction {
    /// Recompute the picks slot from the current library snapshot. The
    /// handler returns `{"ok":true}` once the slot is updated and
    /// bumps `rev` so the iOS poll observes the change.
    Refresh,
}

/// Action module for the `"podcast.picks"` namespace.
///
/// `execute` serializes the typed `PicksAction` back to JSON and hands it
/// to the actor as `ActorCommand::DispatchHostOp`. The installed
/// `PodcastHostOpHandler` deserializes it, runs the heuristic against the
/// store, writes the resulting `Vec<AgentPickSummary>` to the picks slot
/// on `PodcastHandle`, and returns a `{"ok":true}` envelope.
pub struct AgentPicksModule;

impl ActionModule for AgentPicksModule {
    const NAMESPACE: &'static str = "podcast.picks";

    type Action = PicksAction;

    fn is_async_completing() -> bool {
        false
    }

    fn execute(
        action: Self::Action,
        correlation_id: &str,
        send: &dyn Fn(ActorCommand),
    ) -> Result<(), String> {
        let action_json = serde_json::to_string(&action).map_err(|e| e.to_string())?;
        send(ActorCommand::DispatchHostOp {
            action_json,
            correlation_id: correlation_id.to_owned(),
        });
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Heuristic picks computation — pure function for testability
// ---------------------------------------------------------------------------

/// One row consumed by [`compute_picks`]. The `host_op_handler` builds these
/// directly from the `PodcastStore` so the heuristic stays independent of the
/// store internals (and so we can drive tests without instantiating one).
#[derive(Clone, Debug, PartialEq)]
pub struct CandidateEpisode {
    pub episode_id: String,
    pub episode_title: String,
    pub podcast_id: String,
    pub podcast_title: String,
    pub artwork_url: Option<String>,
    pub published_at: i64,
    pub duration_secs: Option<f64>,
}

/// Compute the picks list from a flat candidate set.
///
/// Algorithm:
///   1. Sort candidates by `published_at` descending (newest first).
///   2. Walk in order, accepting each episode that has not yet exceeded
///      [`PICKS_PER_SHOW_CAP`] picks for its show.
///   3. Stop at [`PICKS_LIMIT`].
///   4. Assign `pick_score = 1.0 - (rank / PICKS_LIMIT as f32)` so the top
///      pick gets 1.0 and the last accepted pick gets a positive non-zero.
///   5. `pick_reason = "New from {podcast_title}"`.
pub fn compute_picks(mut candidates: Vec<CandidateEpisode>) -> Vec<AgentPickSummary> {
    // Newest first. `sort_by` is stable, so ties keep input order.
    candidates.sort_by(|a, b| b.published_at.cmp(&a.published_at));

    let mut per_show: std::collections::HashMap<String, usize> =
        std::collections::HashMap::new();
    let mut picks: Vec<AgentPickSummary> = Vec::with_capacity(PICKS_LIMIT);

    for cand in candidates {
        if picks.len() >= PICKS_LIMIT {
            break;
        }
        let count = per_show.entry(cand.podcast_id.clone()).or_insert(0);
        if *count >= PICKS_PER_SHOW_CAP {
            continue;
        }
        *count += 1;

        let rank = picks.len();
        // rank 0 ⇒ 1.0, rank PICKS_LIMIT-1 ⇒ 1/PICKS_LIMIT.
        let score = 1.0_f32 - (rank as f32 / PICKS_LIMIT as f32);
        let reason = format!("New from {}", cand.podcast_title);

        picks.push(AgentPickSummary {
            episode_id: cand.episode_id,
            episode_title: cand.episode_title,
            podcast_id: cand.podcast_id,
            podcast_title: cand.podcast_title,
            artwork_url: cand.artwork_url,
            published_at: cand.published_at,
            duration_secs: cand.duration_secs,
            pick_reason: reason,
            pick_score: score,
        });
    }

    picks
}

#[cfg(test)]
#[path = "picks_module_tests.rs"]
mod tests;
