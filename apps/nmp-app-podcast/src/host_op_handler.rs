//! `PodcastHostOpHandler` — runs podcast and player actions on the actor thread.
//!
//! Installed by `nmp_app_podcast_register` via
//! `NmpApp::set_host_op_handler`. The actor dispatches
//! `ActorCommand::DispatchHostOp { action_json, correlation_id }` here
//! after `PodcastActionModule` or `PlayerActionModule::execute` routes the action.
//!
//! Each `handle` call receives the JSON-encoded action and returns a
//! `{"ok":true}` or `{"ok":false,"error":"..."}` envelope.
//!
//! ## Lock discipline
//!
//! MUST release ALL `PodcastStore` / `PlayerActor` locks BEFORE calling
//! `NmpApp::dispatch_capability` to prevent deadlock with the snapshot
//! path on the main thread.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};

use chrono::Utc;
use nmp_core::substrate::{CapabilityRequest, HostOpHandler};
use nmp_ffi::NmpApp;
use podcast_core::PodcastId;
use podcast_feeds::client::{build_feed_request, handle_feed_response, FeedResult};
use podcast_feeds::http::{HttpResult, HTTP_CAPABILITY_NAMESPACE};

use crate::capability::{AudioCommand, AUDIO_CAPABILITY_NAMESPACE};
use crate::ffi::actions::player_module::PlayerAction;
use crate::ffi::actions::podcast_module::PodcastAction;
use crate::player::PlayerActor;
use crate::store::PodcastStore;

pub struct PodcastHostOpHandler {
    app: *mut NmpApp,
    store: Arc<Mutex<PodcastStore>>,
    player_actor: Arc<Mutex<PlayerActor>>,
    rev: Arc<AtomicU64>,
}

// SAFETY: `app` is never mutated through this pointer (only read via
// `dispatch_capability(&self, ...)`). `PodcastHostOpHandler` is dropped only
// after `nmp_app_free` joins the actor thread, fencing any in-flight call.
unsafe impl Send for PodcastHostOpHandler {}
unsafe impl Sync for PodcastHostOpHandler {}

impl PodcastHostOpHandler {
    pub fn new(
        app: *mut NmpApp,
        store: Arc<Mutex<PodcastStore>>,
        player_actor: Arc<Mutex<PlayerActor>>,
        rev: Arc<AtomicU64>,
    ) -> Self {
        Self { app, store, player_actor, rev }
    }

    fn handle_subscribe(&self, feed_url: String, correlation_id: &str) -> serde_json::Value {
        let url = match url::Url::parse(&feed_url) {
            Ok(u) => u,
            Err(e) => {
                return serde_json::json!({"ok": false, "error": format!("bad url: {e}")})
            }
        };

        let http_req = build_feed_request(&url, None);
        let payload_json = match serde_json::to_string(&http_req) {
            Ok(j) => j,
            Err(e) => return serde_json::json!({"ok": false, "error": format!("encode: {e}")}),
        };

        let capability_req = CapabilityRequest {
            namespace: HTTP_CAPABILITY_NAMESPACE.to_owned(),
            correlation_id: correlation_id.to_owned(),
            payload_json,
        };

        // ALL store / actor locks MUST be released before dispatch_capability
        // to prevent deadlock with the snapshot path.
        let envelope = unsafe { &*self.app }.dispatch_capability(&capability_req);

        let http_result: HttpResult = match serde_json::from_str(&envelope.result_json) {
            Ok(r) => r,
            Err(e) => {
                return serde_json::json!({"ok": false, "error": format!("decode http result: {e}")})
            }
        };

        let podcast_id = PodcastId::generate();
        match handle_feed_response(&url, podcast_id, &http_result, None, Utc::now()) {
            Ok(FeedResult::Parsed { parsed, .. }) => {
                match self.store.lock() {
                    Ok(mut s) => {
                        s.subscribe(parsed.podcast, parsed.episodes);
                        self.rev.fetch_add(1, Ordering::Relaxed);
                        serde_json::json!({"ok": true})
                    }
                    Err(_) => serde_json::json!({"ok": false, "error": "store poisoned"}),
                }
            }
            Ok(FeedResult::NotModified { .. }) => {
                serde_json::json!({"ok": true, "not_modified": true})
            }
            Err(e) => serde_json::json!({"ok": false, "error": format!("{e:?}")}),
        }
    }

    // ── Audio command dispatch ───────────────────────────────────────────────

    /// Encode `cmd` as a `CapabilityRequest` and dispatch it to the audio
    /// capability synchronously. Locks MUST be released before calling this.
    fn dispatch_audio(&self, cmd: &AudioCommand, correlation_id: &str) -> Result<(), String> {
        let payload_json = serde_json::to_string(cmd).map_err(|e| e.to_string())?;
        let req = CapabilityRequest {
            namespace: AUDIO_CAPABILITY_NAMESPACE.to_owned(),
            correlation_id: correlation_id.to_owned(),
            payload_json,
        };
        // D6: ignore the response envelope; audio commands are fire-and-forget.
        let _ = unsafe { &*self.app }.dispatch_capability(&req);
        Ok(())
    }

    // ── Player action handlers ───────────────────────────────────────────────

    fn handle_play(&self, episode_id: String, correlation_id: &str) -> serde_json::Value {
        // 1. Resolve episode URL + position. Release store lock before dispatch.
        let (podcast_id, url, position_secs) = {
            match self.store.lock() {
                Ok(s) => match s.episode_playback_info(&episode_id) {
                    Some(info) => info,
                    None => {
                        return serde_json::json!({"ok": false, "error": format!("episode not found: {episode_id}")})
                    }
                },
                Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
            }
        };

        // 2. Stage load in PlayerActor (sets episode_id in the snapshot).
        // Lock released before dispatch_audio below.
        {
            if let Ok(mut actor) = self.player_actor.lock() {
                actor.stage_load(&episode_id, Some(podcast_id), &url, position_secs);
            }
        }
        self.rev.fetch_add(1, Ordering::Relaxed);

        // 3. Dispatch Load + Play commands to the iOS audio capability.
        let load_cmd = AudioCommand::load(&url, position_secs);
        if let Err(e) = self.dispatch_audio(&load_cmd, correlation_id) {
            return serde_json::json!({"ok": false, "error": e});
        }
        if let Err(e) = self.dispatch_audio(&AudioCommand::Play, correlation_id) {
            return serde_json::json!({"ok": false, "error": e});
        }
        serde_json::json!({"ok": true})
    }

    fn handle_player_action(&self, action: PlayerAction, correlation_id: &str) -> serde_json::Value {
        match action {
            PlayerAction::Play { episode_id } => self.handle_play(episode_id, correlation_id),

            PlayerAction::Pause => {
                match self.dispatch_audio(&AudioCommand::Pause, correlation_id) {
                    Ok(_) => serde_json::json!({"ok": true}),
                    Err(e) => serde_json::json!({"ok": false, "error": e}),
                }
            }

            PlayerAction::Seek { position_secs } => {
                match self.dispatch_audio(&AudioCommand::seek(position_secs), correlation_id) {
                    Ok(_) => serde_json::json!({"ok": true}),
                    Err(e) => serde_json::json!({"ok": false, "error": e}),
                }
            }

            PlayerAction::SetSpeed { speed } => {
                {
                    if let Ok(mut actor) = self.player_actor.lock() {
                        actor.set_speed(speed);
                    }
                }
                self.rev.fetch_add(1, Ordering::Relaxed);
                match self.dispatch_audio(&AudioCommand::SetSpeed { speed }, correlation_id) {
                    Ok(_) => serde_json::json!({"ok": true}),
                    Err(e) => serde_json::json!({"ok": false, "error": e}),
                }
            }

            PlayerAction::SetVolume { volume } => {
                {
                    if let Ok(mut actor) = self.player_actor.lock() {
                        actor.set_volume(volume);
                    }
                }
                self.rev.fetch_add(1, Ordering::Relaxed);
                match self.dispatch_audio(&AudioCommand::SetVolume { volume }, correlation_id) {
                    Ok(_) => serde_json::json!({"ok": true}),
                    Err(e) => serde_json::json!({"ok": false, "error": e}),
                }
            }

            PlayerAction::SetSleepTimer { secs } => {
                {
                    if let Ok(mut actor) = self.player_actor.lock() {
                        match secs {
                            Some(s) if s > 0 => {
                                actor.arm_sleep_timer(Duration::from_secs(s), SystemTime::now());
                            }
                            _ => actor.cancel_sleep_timer(),
                        }
                    }
                }
                self.rev.fetch_add(1, Ordering::Relaxed);
                match self.dispatch_audio(&AudioCommand::SetSleepTimer { secs }, correlation_id) {
                    Ok(_) => serde_json::json!({"ok": true}),
                    Err(e) => serde_json::json!({"ok": false, "error": e}),
                }
            }

            PlayerAction::Stop => {
                {
                    // cancel_sleep_timer is called inside PlayerActor on Stop report;
                    // no need to pre-cancel here — dispatch the command and let the
                    // Stopped report come back and update state.
                }
                match self.dispatch_audio(&AudioCommand::Stop, correlation_id) {
                    Ok(_) => serde_json::json!({"ok": true}),
                    Err(e) => serde_json::json!({"ok": false, "error": e}),
                }
            }
        }
    }
}

impl HostOpHandler for PodcastHostOpHandler {
    fn handle(&self, action_json: &str, correlation_id: &str) -> serde_json::Value {
        // Try podcast actions first (subscribe, refresh, …).
        if let Ok(action) = serde_json::from_str::<PodcastAction>(action_json) {
            return match action {
                PodcastAction::Subscribe { feed_url } => {
                    self.handle_subscribe(feed_url, correlation_id)
                }
            };
        }

        // Fall through to player actions (play, pause, seek, …).
        if let Ok(action) = serde_json::from_str::<PlayerAction>(action_json) {
            return self.handle_player_action(action, correlation_id);
        }

        serde_json::json!({"ok": false, "error": format!("unknown action: {action_json}")})
    }
}
