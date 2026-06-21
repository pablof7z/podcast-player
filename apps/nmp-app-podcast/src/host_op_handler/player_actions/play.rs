use crate::ad_skip_handler::hydrate_actor_for_play;
use crate::capability::AudioCommand;
use crate::host_op_handler::PodcastHostOpHandler;

/// Format a playback position in seconds as `H:MM:SS` / `M:SS` for a
/// Diagnostics detail row. Negative / NaN positions clamp to `0:00`.
fn format_position(secs: f64) -> String {
    let total = if secs.is_finite() && secs > 0.0 {
        secs as u64
    } else {
        0
    };
    let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60);
    if h > 0 {
        format!("{h}:{m:02}:{s:02}")
    } else {
        format!("{m}:{s:02}")
    }
}

fn resolve_play_bounds(
    saved_position_secs: f64,
    start_secs: Option<f64>,
    end_secs: Option<f64>,
) -> Result<(f64, Option<f64>), String> {
    let start = match start_secs {
        Some(start) => {
            if !start.is_finite() {
                return Err("playback start must be finite".to_owned());
            }
            if start < 0.0 {
                return Err("playback start must be >= 0".to_owned());
            }
            start
        }
        None => saved_position_secs.max(0.0),
    };
    if !start.is_finite() {
        return Err("playback start must be finite".to_owned());
    }
    if let Some(end) = end_secs {
        if !end.is_finite() {
            return Err("playback end must be finite".to_owned());
        }
        if end <= start {
            return Err("playback end must be greater than start".to_owned());
        }
        Ok((start, Some(end)))
    } else {
        Ok((start, None))
    }
}

impl PodcastHostOpHandler {
    /// Record a `playback.started` event the first time an episode becomes the
    /// staged item — i.e. when `episode_id` differs from whatever the actor had
    /// loaded before. This dedups the common re-stage churn (the UI calls
    /// `load` on resume, mini-player restore, chapter seeks) so the log shows
    /// one "started listening" line per real session start, with the resume
    /// position. Best-effort: a poisoned store lock simply skips the line.
    fn record_playback_started_if_new(
        &self,
        episode_id: &str,
        position_secs: f64,
        prior_episode: Option<&str>,
    ) {
        if prior_episode == Some(episode_id) {
            return;
        }
        if let Ok(mut s) = self.state.library.store.lock() {
            let detail = if position_secs > 1.0 {
                crate::store::events::EventDetail::new(
                    "Resumed at",
                    format_position(position_secs),
                )
            } else {
                crate::store::events::EventDetail::new("From", "start")
            };
            s.emit_event(
                episode_id,
                crate::store::events::stage::PLAYBACK_STARTED,
                crate::store::events::EventSeverity::Info,
                "Playback started",
                vec![detail],
            );
        }
    }

    /// User intent to load/play an episode is also a rescue signal for AI Inbox
    /// triage. If the agent previously archived or inbox-ranked the episode,
    /// clear that decision in Rust so the next projection no longer treats it
    /// as hidden or pending.
    fn clear_triage_on_user_play(&self, episode_id: &str) -> bool {
        match self.state.library.store.lock() {
            Ok(mut s) => s.set_episode_triage(episode_id, "none", false, None),
            Err(_) => false,
        }
    }

    /// Play an episode: stage-load the actor, dispatch Load+Play audio commands,
    /// and enqueue a background download when the episode is not yet local.
    /// Called from `handle_player_action` (mod.rs) and `handle_play_next`
    /// (queue.rs) — hence `pub(super)`.
    pub(super) fn handle_play(
        &self,
        episode_id: String,
        start_secs: Option<f64>,
        end_secs: Option<f64>,
        correlation_id: &str,
    ) -> serde_json::Value {
        let (canonical_id, podcast_id, url, position_secs, needs_download) = {
            match self.state.library.store.lock() {
                Ok(s) => match s.episode_playback_info(&episode_id) {
                    Some((canon_id, pod_id, ep_url, pos)) => {
                        let downloaded = s.episode_is_downloaded(&episode_id);
                        (canon_id, pod_id, ep_url, pos, !downloaded)
                    }
                    None => {
                        return serde_json::json!({
                            "ok": false,
                            "error": format!("episode not found: {episode_id}")
                        })
                    }
                },
                Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
            }
        };
        let (position_secs, segment_end_secs) =
            match resolve_play_bounds(position_secs, start_secs, end_secs) {
                Ok(bounds) => bounds,
                Err(error) => return serde_json::json!({"ok": false, "error": error}),
        };
        // Rebind to the store's canonical (lowercase) id. iOS dispatches the
        // UPPERCASE `UUID.uuidString`; staging the canonical form keeps the
        // actor's `episode_id` exact-matchable by the widget library lookup and
        // the position writeback (both `==` against the lowercase store id).
        let episode_id = canonical_id;
        let triage_cleared = self.clear_triage_on_user_play(&episode_id);
        let player = self.state.playback.player.share();
        let prior_episode = if let Ok(mut actor) = player.lock() {
            let prior = actor.state().episode_id.clone();
            actor.stage_load(&episode_id, Some(podcast_id), &url, position_secs);
            actor.set_segment_end_secs(segment_end_secs);
            prior
        } else {
            None
        };
        self.record_playback_started_if_new(&episode_id, position_secs, prior_episode.as_deref());
        if triage_cleared {
            self.bump_domain(crate::state::Domain::Library);
        }
        // Push the persisted ad segments + global toggle into the
        // freshly-staged actor so auto-skip can fire on the very first
        // `Playing` report (no extra round-trip via iOS).
        hydrate_actor_for_play(&self.state.library.store, &player, &episode_id);
        self.bump_domain(crate::state::Domain::Playback);
        if let Err(e) = self.dispatch_audio(
            &AudioCommand::load_with_id(&url, position_secs, &episode_id),
            correlation_id,
        ) {
            return serde_json::json!({"ok": false, "error": e});
        }
        if let Err(e) = self.dispatch_audio(&AudioCommand::Play, correlation_id) {
            return serde_json::json!({"ok": false, "error": e});
        }
        // Enqueue a background download for episodes played from remote URL.
        // `DownloadQueue::enqueue` is idempotent: returns `None` (no dispatch)
        // when the item is already queued or in a non-terminal state.
        if needs_download {
            let dl_id = episode_id.clone();
            let dl_url = url.clone();
            self.handle_download_command(|q| q.enqueue(dl_id, dl_url), correlation_id);
        }
        serde_json::json!({"ok": true})
    }

    /// Stage-load an episode without dispatching Play. iOS calls Resume when the
    /// user taps play. Also enqueues a background download for streamed episodes.
    pub(super) fn handle_load(
        &self,
        episode_id: String,
        start_secs: Option<f64>,
        end_secs: Option<f64>,
        correlation_id: &str,
    ) -> serde_json::Value {
        let (canonical_id, podcast_id, url, position_secs, needs_download) = {
            match self.state.library.store.lock() {
                Ok(s) => match s.episode_playback_info(&episode_id) {
                    Some((canon_id, pod_id, ep_url, pos)) => {
                        let downloaded = s.episode_is_downloaded(&episode_id);
                        (canon_id, pod_id, ep_url, pos, !downloaded)
                    }
                    None => {
                        return serde_json::json!({
                            "ok": false,
                            "error": format!("episode not found: {episode_id}")
                        })
                    }
                },
                Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
            }
        };
        let (position_secs, segment_end_secs) =
            match resolve_play_bounds(position_secs, start_secs, end_secs) {
                Ok(bounds) => bounds,
                Err(error) => return serde_json::json!({"ok": false, "error": error}),
        };
        // Rebind to the store's canonical (lowercase) id — see `handle_play`.
        let episode_id = canonical_id;
        let triage_cleared = self.clear_triage_on_user_play(&episode_id);
        let player = self.state.playback.player.share();
        let prior_episode = if let Ok(mut actor) = player.lock() {
            let prior = actor.state().episode_id.clone();
            actor.stage_load(&episode_id, Some(podcast_id), &url, position_secs);
            actor.set_segment_end_secs(segment_end_secs);
            prior
        } else {
            None
        };
        self.record_playback_started_if_new(&episode_id, position_secs, prior_episode.as_deref());
        if triage_cleared {
            self.bump_domain(crate::state::Domain::Library);
        }
        hydrate_actor_for_play(&self.state.library.store, &player, &episode_id);
        self.bump_domain(crate::state::Domain::Playback);
        // Dispatch Load only — no Play. iOS calls Resume when the user taps play.
        let dispatch = self.dispatch_audio(
            &AudioCommand::load_with_id(&url, position_secs, &episode_id),
            correlation_id,
        );
        if let Err(e) = dispatch {
            return serde_json::json!({"ok": false, "error": e});
        }
        // Enqueue a background download for streamed episodes. The UI's play
        // path dispatches `load` (not `play`), and restored mini-player plays
        // skip the Swift-side enqueue, so owning the download-on-play rule here
        // keeps it consistent across every play entry point. Idempotent.
        if needs_download {
            let dl_id = episode_id.clone();
            let dl_url = url.clone();
            self.handle_download_command(|q| q.enqueue(dl_id, dl_url), correlation_id);
        }
        serde_json::json!({"ok": true})
    }
}
