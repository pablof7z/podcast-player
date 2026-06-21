use std::time::{Duration, SystemTime};

use crate::ad_skip_handler::handle_set_ad_segments;
use crate::capability::{AudioCommand, DownloadCommand};
use crate::ffi::actions::player_module::PlayerAction;
use crate::host_op_handler::PodcastHostOpHandler;

// Convenience aliases so reader can track which slot is being accessed.
// Step 14: player, queue, and download_queue are now sourced from
// `self.state.playback.*` instead of god-struct fields.

mod play;
mod queue;
mod skip;

impl PodcastHostOpHandler {
    pub(super) fn handle_player_action(
        &self,
        action: PlayerAction,
        correlation_id: &str,
    ) -> serde_json::Value {
        match action {
            PlayerAction::Play {
                episode_id,
                start_secs,
                end_secs,
            } => self.handle_play(episode_id, start_secs, end_secs, correlation_id),
            PlayerAction::Load {
                episode_id,
                start_secs,
                end_secs,
            } => self.handle_load(episode_id, start_secs, end_secs, correlation_id),
            PlayerAction::Resume => self.dispatch_audio_json(AudioCommand::Play, correlation_id),
            PlayerAction::Pause => self.dispatch_audio_json(AudioCommand::Pause, correlation_id),
            PlayerAction::Seek { position_secs } => {
                let target = match self.state.playback.player.lock() {
                    Ok(mut a) => {
                        if a.state().episode_id.is_none() {
                            return serde_json::json!({"ok": false, "error": "nothing is currently loaded"});
                        }
                        a.seek_target(position_secs)
                    }
                    Err(_) => {
                        return serde_json::json!({"ok": false, "error": "player_actor poisoned"})
                    }
                };
                self.bump_domain(crate::state::Domain::Playback);
                self.dispatch_audio_json(AudioCommand::seek(target), correlation_id)
            }
            PlayerAction::SetSpeed { speed } => {
                if let Ok(mut a) = self.state.playback.player.lock() {
                    a.set_speed(speed);
                }
                // Persist the chosen rate so it survives cold relaunch.
                // `default_playback_rate` is written to podcasts.json via
                // `set_default_playback_rate`, which the kernel reloads at
                // `set_data_dir` time. The Swift shell's `applyPreferences`
                // then reads it from the `settings` snapshot and applies it to
                // `AudioEngine.rate` before the first episode is loaded, so
                // `play()` → `playImmediately(atRate:)` uses the persisted value.
                if let Ok(mut s) = self.state.library.store.lock() {
                    s.set_default_playback_rate(speed as f64);
                }
                self.bump_domain(crate::state::Domain::Playback);
                // Bump Domain::Settings so the next kernel snapshot carries the
                // updated `default_playback_rate` to Swift immediately. Without
                // this, the settings domain is only re-emitted on the next
                // unrelated settings mutation, so `onChange(of: store.state.settings)`
                // in RootView never fires with the new rate in the same session.
                self.bump_domain(crate::state::Domain::Settings);
                self.dispatch_audio_json(AudioCommand::SetSpeed { speed }, correlation_id)
            }
            PlayerAction::SetVolume { volume } => {
                if let Ok(mut a) = self.state.playback.player.lock() {
                    a.set_volume(volume);
                }
                self.bump_domain(crate::state::Domain::Playback);
                self.dispatch_audio_json(AudioCommand::SetVolume { volume }, correlation_id)
            }
            PlayerAction::SetSleepTimer {
                secs,
                end_of_episode,
            } => {
                if let Ok(mut a) = self.state.playback.player.lock() {
                    match (end_of_episode, secs) {
                        (true, _) => a.arm_sleep_timer_end_of_episode(),
                        (false, Some(s)) if s > 0 => {
                            a.arm_sleep_timer(Duration::from_secs(s), SystemTime::now())
                        }
                        _ => a.cancel_sleep_timer(),
                    }
                }
                self.bump_domain(crate::state::Domain::Playback);
                let native_secs = if end_of_episode { None } else { secs };
                self.dispatch_audio_json(
                    AudioCommand::SetSleepTimer { secs: native_secs },
                    correlation_id,
                )
            }
            PlayerAction::Stop => self.dispatch_audio_json(AudioCommand::Stop, correlation_id),
            PlayerAction::Enqueue { episode_id } => self.handle_enqueue(episode_id),
            PlayerAction::EnqueueNext { episode_id } => self.handle_enqueue_next(episode_id),
            PlayerAction::EnqueueSegment {
                episode_id,
                start_secs,
                end_secs,
            } => self.handle_enqueue_segment(episode_id, start_secs, end_secs, false),
            PlayerAction::EnqueueSegmentNext {
                episode_id,
                start_secs,
                end_secs,
            } => self.handle_enqueue_segment(episode_id, start_secs, end_secs, true),
            PlayerAction::Dequeue { episode_id } => self.handle_dequeue(episode_id),
            PlayerAction::DequeueSlot { queue_slot_id } => {
                self.handle_dequeue_slot(queue_slot_id)
            }
            PlayerAction::ReorderQueue { queue_slot_ids } => {
                self.handle_reorder_queue(queue_slot_ids)
            }
            PlayerAction::ClearQueue => self.handle_clear_queue(),
            PlayerAction::PlayNext => self.handle_play_next(correlation_id),
            PlayerAction::SetAdSegments {
                episode_id,
                segments,
            } => handle_set_ad_segments(
                &self.state.library.store,
                &self.state.playback.player.share(),
                &self.state.infra.rev,
                episode_id,
                segments,
            ),
            PlayerAction::SkipForward { secs } => {
                let resolved = secs.unwrap_or_else(|| {
                    self.state
                        .library
                        .store
                        .lock()
                        .map(|s| s.skip_forward_secs())
                        .unwrap_or(30.0)
                });
                self.handle_skip(resolved, correlation_id)
            }
            PlayerAction::SkipBackward { secs } => {
                let resolved = secs.unwrap_or_else(|| {
                    self.state
                        .library
                        .store
                        .lock()
                        .map(|s| s.skip_backward_secs())
                        .unwrap_or(15.0)
                });
                self.handle_skip(-resolved, correlation_id)
            }
            PlayerAction::Download { episode_id, url } => {
                self.handle_player_download(episode_id, url, correlation_id)
            }
            PlayerAction::CancelDownload { episode_id } => {
                self.handle_download_command(|q| q.cancel(&episode_id), correlation_id)
            }
            PlayerAction::PauseDownload { episode_id } => {
                self.handle_download_command(|q| q.pause(&episode_id), correlation_id)
            }
            PlayerAction::ResumeDownload { episode_id } => {
                self.handle_download_command(|q| q.resume(&episode_id), correlation_id)
            }
            PlayerAction::CancelAllDownloads => {
                self.handle_download_command(|q| q.cancel_all(), correlation_id)
            }
            PlayerAction::ResetProgress { episode_id } => match self.state.library.store.lock() {
                Ok(mut s) => {
                    s.reset_episode_progress(&episode_id);
                    self.bump_domain(crate::state::Domain::Playback);
                    serde_json::json!({"ok": true})
                }
                Err(_) => serde_json::json!({"ok": false, "error": "store poisoned"}),
            },
            PlayerAction::Advance => self.handle_play_next(correlation_id),
            PlayerAction::PersistPosition {
                episode_id,
                position_secs,
            } => match self.state.library.store.lock() {
                Ok(mut s) => {
                    s.set_episode_position(&episode_id, position_secs);
                    s.flush_positions();
                    self.bump_domain(crate::state::Domain::Playback);
                    serde_json::json!({"ok": true})
                }
                Err(_) => serde_json::json!({"ok": false, "error": "store poisoned"}),
            },
        }
    }

    /// Dispatch an [`AudioCommand`] and return a uniform `{"ok":…}` JSON value.
    /// Called from `handle_player_action` (mod.rs), `handle_play`/`handle_load`
    /// (play.rs), and `handle_skip` (skip.rs).
    fn dispatch_audio_json(
        &self,
        cmd: AudioCommand,
        correlation_id: &str,
    ) -> serde_json::Value {
        match self.dispatch_audio(&cmd, correlation_id) {
            Ok(_) => serde_json::json!({"ok": true}),
            Err(e) => serde_json::json!({"ok": false, "error": e}),
        }
    }

    /// Dispatch a [`DownloadCommand`] and return a uniform `{"ok":…}` JSON value.
    /// Called from `handle_download_command` (skip.rs).
    fn dispatch_download_json(
        &self,
        cmd: DownloadCommand,
        correlation_id: &str,
    ) -> serde_json::Value {
        match self.dispatch_download(&cmd, correlation_id) {
            Ok(_) => serde_json::json!({"ok": true}),
            Err(e) => serde_json::json!({"ok": false, "error": e}),
        }
    }
}

#[cfg(test)]
#[path = "../player_actions_tests.rs"]
mod tests;
