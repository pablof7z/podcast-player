//! Actor-thread handlers for `podcast.player.*` actions.
//!
//! Extracted from `host_op_handler.rs` to keep that file under the 500-LOC
//! hard ceiling. Same lock discipline applies: release `PodcastStore` /
//! `PlayerActor` locks before dispatching to capabilities so snapshot reads
//! cannot deadlock against an in-flight `dispatch_capability` call.
//!
//! The audio-dispatch helper is parameterised as a closure so this module
//! doesn't need to know about `NmpApp` directly — `host_op_handler` passes
//! a tiny adapter that calls `self.dispatch_audio` with the live
//! correlation id.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};

use crate::capability::AudioCommand;
use crate::ffi::actions::player_module::PlayerAction;
use crate::player::PlayerActor;
use crate::store::PodcastStore;

/// Type alias for the audio-dispatch closure host handlers pass in.
///
/// Returns `Ok(())` on successful dispatch (the audio capability runs
/// asynchronously; an error here is a serialization failure, not a
/// playback failure), `Err(String)` otherwise.
pub type AudioDispatcher<'a> = dyn Fn(&AudioCommand) -> Result<(), String> + 'a;

/// Dispatch a `podcast.player.*` action.
pub fn handle_player_action(
    action: PlayerAction,
    store: &Arc<Mutex<PodcastStore>>,
    player_actor: &Arc<Mutex<PlayerActor>>,
    rev: &Arc<AtomicU64>,
    dispatch_audio: &AudioDispatcher<'_>,
) -> serde_json::Value {
    match action {
        PlayerAction::Play { episode_id } => {
            handle_play(episode_id, store, player_actor, rev, dispatch_audio)
        }
        PlayerAction::Pause => match dispatch_audio(&AudioCommand::Pause) {
            Ok(_) => serde_json::json!({"ok": true}),
            Err(e) => serde_json::json!({"ok": false, "error": e}),
        },
        PlayerAction::Seek { position_secs } => {
            match dispatch_audio(&AudioCommand::seek(position_secs)) {
                Ok(_) => serde_json::json!({"ok": true}),
                Err(e) => serde_json::json!({"ok": false, "error": e}),
            }
        }
        PlayerAction::SetSpeed { speed } => {
            if let Ok(mut a) = player_actor.lock() {
                a.set_speed(speed);
            }
            rev.fetch_add(1, Ordering::Relaxed);
            match dispatch_audio(&AudioCommand::SetSpeed { speed }) {
                Ok(_) => serde_json::json!({"ok": true}),
                Err(e) => serde_json::json!({"ok": false, "error": e}),
            }
        }
        PlayerAction::SetVolume { volume } => {
            if let Ok(mut a) = player_actor.lock() {
                a.set_volume(volume);
            }
            rev.fetch_add(1, Ordering::Relaxed);
            match dispatch_audio(&AudioCommand::SetVolume { volume }) {
                Ok(_) => serde_json::json!({"ok": true}),
                Err(e) => serde_json::json!({"ok": false, "error": e}),
            }
        }
        PlayerAction::SetSleepTimer { secs } => {
            if let Ok(mut a) = player_actor.lock() {
                match secs {
                    Some(s) if s > 0 => {
                        a.arm_sleep_timer(Duration::from_secs(s), SystemTime::now())
                    }
                    _ => a.cancel_sleep_timer(),
                }
            }
            rev.fetch_add(1, Ordering::Relaxed);
            match dispatch_audio(&AudioCommand::SetSleepTimer { secs }) {
                Ok(_) => serde_json::json!({"ok": true}),
                Err(e) => serde_json::json!({"ok": false, "error": e}),
            }
        }
        PlayerAction::Stop => match dispatch_audio(&AudioCommand::Stop) {
            Ok(_) => serde_json::json!({"ok": true}),
            Err(e) => serde_json::json!({"ok": false, "error": e}),
        },
        PlayerAction::Enqueue { episode_id } => {
            handle_enqueue(episode_id, store, player_actor, rev)
        }
        PlayerAction::Dequeue { episode_id } => handle_dequeue(episode_id, player_actor, rev),
        PlayerAction::ClearQueue => handle_clear_queue(player_actor, rev),
        PlayerAction::PlayNext => {
            handle_play_next(store, player_actor, rev, dispatch_audio)
        }
    }
}

pub fn handle_play(
    episode_id: String,
    store: &Arc<Mutex<PodcastStore>>,
    player_actor: &Arc<Mutex<PlayerActor>>,
    rev: &Arc<AtomicU64>,
    dispatch_audio: &AudioDispatcher<'_>,
) -> serde_json::Value {
    let (podcast_id, url, position_secs) = match store.lock() {
        Ok(s) => match s.episode_playback_info(&episode_id) {
            Some(info) => info,
            None => {
                return serde_json::json!({"ok": false, "error": format!("episode not found: {episode_id}")})
            }
        },
        Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
    };
    if let Ok(mut actor) = player_actor.lock() {
        actor.stage_load(&episode_id, Some(podcast_id), &url, position_secs);
    }
    rev.fetch_add(1, Ordering::Relaxed);
    let load_cmd = AudioCommand::load(&url, position_secs);
    if let Err(e) = dispatch_audio(&load_cmd) {
        return serde_json::json!({"ok": false, "error": e});
    }
    if let Err(e) = dispatch_audio(&AudioCommand::Play) {
        return serde_json::json!({"ok": false, "error": e});
    }
    serde_json::json!({"ok": true})
}

fn handle_enqueue(
    episode_id: String,
    store: &Arc<Mutex<PodcastStore>>,
    player_actor: &Arc<Mutex<PlayerActor>>,
    rev: &Arc<AtomicU64>,
) -> serde_json::Value {
    let exists = match store.lock() {
        Ok(s) => s.episode_playback_info(&episode_id).is_some(),
        Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
    };
    if !exists {
        return serde_json::json!({"ok": false, "error": format!("episode not found: {episode_id}")});
    }
    match player_actor.lock() {
        Ok(mut a) => {
            a.enqueue(&episode_id);
            rev.fetch_add(1, Ordering::Relaxed);
            serde_json::json!({"ok": true})
        }
        Err(_) => serde_json::json!({"ok": false, "error": "player_actor poisoned"}),
    }
}

fn handle_dequeue(
    episode_id: String,
    player_actor: &Arc<Mutex<PlayerActor>>,
    rev: &Arc<AtomicU64>,
) -> serde_json::Value {
    match player_actor.lock() {
        Ok(mut a) => {
            a.dequeue(&episode_id);
            rev.fetch_add(1, Ordering::Relaxed);
            serde_json::json!({"ok": true})
        }
        Err(_) => serde_json::json!({"ok": false, "error": "player_actor poisoned"}),
    }
}

fn handle_clear_queue(
    player_actor: &Arc<Mutex<PlayerActor>>,
    rev: &Arc<AtomicU64>,
) -> serde_json::Value {
    match player_actor.lock() {
        Ok(mut a) => {
            a.clear_queue();
            rev.fetch_add(1, Ordering::Relaxed);
            serde_json::json!({"ok": true})
        }
        Err(_) => serde_json::json!({"ok": false, "error": "player_actor poisoned"}),
    }
}

fn handle_play_next(
    store: &Arc<Mutex<PodcastStore>>,
    player_actor: &Arc<Mutex<PlayerActor>>,
    rev: &Arc<AtomicU64>,
    dispatch_audio: &AudioDispatcher<'_>,
) -> serde_json::Value {
    let next_id = match player_actor.lock() {
        Ok(mut a) => a.pop_next(),
        Err(_) => return serde_json::json!({"ok": false, "error": "player_actor poisoned"}),
    };
    match next_id {
        Some(id) => handle_play(id, store, player_actor, rev, dispatch_audio),
        None => serde_json::json!({"ok": false, "error": "queue is empty"}),
    }
}
