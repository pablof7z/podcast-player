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
mod tests {
    use super::*;

    fn cand(ep: &str, pod_id: &str, pod_title: &str, ts: i64) -> CandidateEpisode {
        CandidateEpisode {
            episode_id: ep.into(),
            episode_title: format!("{ep} title"),
            podcast_id: pod_id.into(),
            podcast_title: pod_title.into(),
            artwork_url: None,
            published_at: ts,
            duration_secs: Some(1800.0),
        }
    }

    #[test]
    fn refresh_action_round_trips() {
        let a = PicksAction::Refresh;
        let json = serde_json::to_string(&a).expect("encode");
        assert_eq!(json, r#"{"op":"refresh"}"#);
        let decoded: PicksAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, a);
    }

    #[test]
    fn namespace_is_podcast_picks() {
        assert_eq!(AgentPicksModule::NAMESPACE, "podcast.picks");
    }

    #[test]
    fn execute_emits_dispatch_host_op() {
        let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
        AgentPicksModule::execute(PicksAction::Refresh, "corr-1", &|cmd| {
            commands.lock().unwrap().push(cmd);
        })
        .expect("execute ok");
        let commands = commands.into_inner().unwrap();
        assert_eq!(commands.len(), 1);
        let ActorCommand::DispatchHostOp { action_json, correlation_id } = &commands[0] else {
            panic!("expected DispatchHostOp");
        };
        assert_eq!(correlation_id, "corr-1");
        let v: serde_json::Value = serde_json::from_str(action_json).expect("json");
        assert_eq!(v["op"], "refresh");
    }

    #[test]
    fn compute_picks_empty_input_returns_empty() {
        let picks = compute_picks(vec![]);
        assert!(picks.is_empty());
    }

    #[test]
    fn compute_picks_orders_newest_first() {
        let candidates = vec![
            cand("ep-old", "pod-1", "Show A", 1_000),
            cand("ep-new", "pod-2", "Show B", 9_000),
            cand("ep-mid", "pod-3", "Show C", 5_000),
        ];
        let picks = compute_picks(candidates);
        assert_eq!(picks.len(), 3);
        assert_eq!(picks[0].episode_id, "ep-new");
        assert_eq!(picks[1].episode_id, "ep-mid");
        assert_eq!(picks[2].episode_id, "ep-old");
    }

    #[test]
    fn compute_picks_caps_per_show() {
        // Five episodes from the same show — only PICKS_PER_SHOW_CAP (2)
        // should make it through.
        let candidates: Vec<CandidateEpisode> = (0..5)
            .map(|i| cand(&format!("ep-{i}"), "pod-mono", "Daily Show", 100 + i as i64))
            .collect();
        let picks = compute_picks(candidates);
        assert_eq!(picks.len(), PICKS_PER_SHOW_CAP);
        // The two newest episodes from the mono-show should win.
        assert_eq!(picks[0].episode_id, "ep-4");
        assert_eq!(picks[1].episode_id, "ep-3");
    }

    #[test]
    fn compute_picks_caps_total_at_limit() {
        // 20 episodes across 20 shows — exactly PICKS_LIMIT (10) survive.
        let candidates: Vec<CandidateEpisode> = (0..20)
            .map(|i| {
                cand(
                    &format!("ep-{i}"),
                    &format!("pod-{i}"),
                    &format!("Show {i}"),
                    100 + i as i64,
                )
            })
            .collect();
        let picks = compute_picks(candidates);
        assert_eq!(picks.len(), PICKS_LIMIT);
    }

    #[test]
    fn compute_picks_assigns_descending_scores() {
        let candidates = vec![
            cand("ep-1", "pod-1", "A", 300),
            cand("ep-2", "pod-2", "B", 200),
            cand("ep-3", "pod-3", "C", 100),
        ];
        let picks = compute_picks(candidates);
        assert_eq!(picks.len(), 3);
        assert!((picks[0].pick_score - 1.0).abs() < 1e-6);
        assert!(picks[0].pick_score > picks[1].pick_score);
        assert!(picks[1].pick_score > picks[2].pick_score);
        // Even the last pick must be positive.
        assert!(picks.last().unwrap().pick_score > 0.0);
    }

    #[test]
    fn compute_picks_sets_reason_with_podcast_title() {
        let candidates = vec![cand("ep-1", "pod-1", "Stratechery", 1_000)];
        let picks = compute_picks(candidates);
        assert_eq!(picks.len(), 1);
        assert_eq!(picks[0].pick_reason, "New from Stratechery");
    }

    #[test]
    fn compute_picks_diversity_across_three_shows() {
        // A high-frequency show with 5 episodes, plus two single-episode
        // shows. The mono show contributes 2 (cap), the others 1 each.
        let mut candidates: Vec<CandidateEpisode> = (0..5)
            .map(|i| cand(&format!("daily-{i}"), "pod-daily", "Daily", 100 + i as i64))
            .collect();
        candidates.push(cand("solo-a", "pod-a", "Show A", 50));
        candidates.push(cand("solo-b", "pod-b", "Show B", 40));
        let picks = compute_picks(candidates);
        assert_eq!(picks.len(), 4); // 2 daily + 2 solo
        let daily_count = picks.iter().filter(|p| p.podcast_id == "pod-daily").count();
        assert_eq!(daily_count, PICKS_PER_SHOW_CAP);
    }
}
