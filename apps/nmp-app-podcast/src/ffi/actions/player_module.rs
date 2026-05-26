//! Player-action `ActionModule` — routes all `"podcast.player.*"` dispatches.
//!
//! Swift encodes every player action as `{"op":"<variant>", ...fields}`.
//! The `#[serde(tag = "op", rename_all = "snake_case")]` discriminator maps
//! the string `op` value to the enum variant. The module's `execute` body
//! forwards the whole action as `ActorCommand::DispatchHostOp` so the
//! `PodcastHostOpHandler` (running on the actor thread) can dispatch audio
//! capability commands without the kernel naming podcast-domain nouns (D0).

use serde::{Deserialize, Serialize};

use nmp_core::substrate::ActionModule;
use nmp_core::ActorCommand;

use crate::player::AdSegment;

/// Wire enum for all `"podcast.player"` namespace actions.
///
/// `#[serde(tag = "op", rename_all = "snake_case")]` makes the JSON
/// discriminator the lowercase snake-case variant name:
/// `play` → `{"op":"play","episode_id":"..."}`.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum PlayerAction {
    Play { episode_id: String },
    Pause,
    Seek { position_secs: f64 },
    SetSpeed { speed: f32 },
    SetVolume { volume: f32 },
    SetSleepTimer {
        #[serde(default)]
        secs: Option<u64>,
    },
    Stop,
    /// Append `episode_id` to the end of the playback queue if not
    /// already present (dedup by id). Kernel-owned ordered list of
    /// episode ids surfaced via `PodcastUpdate.queue`.
    Enqueue { episode_id: String },
    /// Remove the first occurrence of `episode_id` from the queue.
    Dequeue { episode_id: String },
    /// Empty the entire playback queue.
    ClearQueue,
    /// Pop the front of the queue and `Play` it. No-op when the queue
    /// is empty.
    PlayNext,
    /// Set the ad-break list for `episode_id`. Stored in the side-map
    /// on `PodcastStore` and (when the episode is the one currently
    /// loaded) pushed into the player actor so auto-skip can fire on
    /// the next `Playing` tick.
    ///
    /// Carries the full vec rather than incrementally adding so the
    /// caller (an ingest pipeline upstream) is the single owner of
    /// the segment list — re-running detection always emits the
    /// canonical replacement, never a diff.
    SetAdSegments {
        episode_id: String,
        segments: Vec<AdSegment>,
    },
    /// Advance the playhead by `secs` seconds from the current position.
    /// The kernel reads the live `PlayerActor` position so the iOS/Android
    /// shell never needs to know the current time (D0 — policy in Rust).
    SkipForward { secs: f64 },
    /// Step the playhead back by `secs` seconds (clamped to 0).
    SkipBackward { secs: f64 },
    /// Enqueue an episode audio file for offline download.
    Download { episode_id: String, url: String },
    /// Cancel an active, paused, or queued download.
    CancelDownload { episode_id: String },
    /// Pause an active download while retaining resume data.
    PauseDownload { episode_id: String },
    /// Resume a paused download.
    ResumeDownload { episode_id: String },
    /// Cancel every active, paused, and queued download.
    CancelAllDownloads,
}

/// Action module for the `"podcast.player"` namespace.
///
/// `execute` serializes the typed `PlayerAction` back to JSON and hands it
/// to the actor as `ActorCommand::DispatchHostOp`. The installed
/// `PodcastHostOpHandler` deserializes it, dispatches the matching
/// `AudioCommand` to the audio capability, and returns a `{"ok":true}` envelope.
pub struct PlayerActionModule;

impl ActionModule for PlayerActionModule {
    const NAMESPACE: &'static str = "podcast.player";

    type Action = PlayerAction;

    fn is_async_completing() -> bool {
        false
    }

    fn execute(
        action: Self::Action,
        correlation_id: &str,
        send: &dyn Fn(ActorCommand),
    ) -> Result<(), String> {
        let action_json =
            serde_json::to_string(&action).map_err(|e| e.to_string())?;
        send(ActorCommand::DispatchHostOp {
            action_json,
            correlation_id: correlation_id.to_owned(),
        });
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Player / download action id constants (kernel ↔ shell contract)
// ---------------------------------------------------------------------------

/// `podcast.player.play` — begin playback of `episode_id`.
pub const ACTION_PLAYER_PLAY: &str = "podcast.player.play";
/// `podcast.player.pause` — pause the active episode.
pub const ACTION_PLAYER_PAUSE: &str = "podcast.player.pause";
/// `podcast.player.seek` — seek the active episode.
pub const ACTION_PLAYER_SEEK: &str = "podcast.player.seek";
/// `podcast.player.set_speed` — change playback rate.
pub const ACTION_PLAYER_SET_SPEED: &str = "podcast.player.set_speed";
/// `podcast.player.set_volume` — change engine-level volume.
pub const ACTION_PLAYER_SET_VOLUME: &str = "podcast.player.set_volume";
/// `podcast.player.set_sleep_timer` — arm / cancel sleep timer.
pub const ACTION_PLAYER_SET_SLEEP_TIMER: &str = "podcast.player.set_sleep_timer";
/// `podcast.player.stop` — tear down the active episode.
pub const ACTION_PLAYER_STOP: &str = "podcast.player.stop";
/// `podcast.player.download` — enqueue an episode for background download.
pub const ACTION_PLAYER_DOWNLOAD: &str = "podcast.player.download";
/// `podcast.player.cancel_download` — cancel an active or queued download.
pub const ACTION_PLAYER_CANCEL_DOWNLOAD: &str = "podcast.player.cancel_download";
/// `podcast.player.pause_download` — pause an active download.
pub const ACTION_PLAYER_PAUSE_DOWNLOAD: &str = "podcast.player.pause_download";
/// `podcast.player.resume_download` — resume a paused download.
pub const ACTION_PLAYER_RESUME_DOWNLOAD: &str = "podcast.player.resume_download";
/// `podcast.player.cancel_all_downloads` — cancel every in-flight + queued download.
pub const ACTION_PLAYER_CANCEL_ALL_DOWNLOADS: &str = "podcast.player.cancel_all_downloads";
/// `podcast.player.skip_forward` — relative seek forward by `secs` seconds.
pub const ACTION_PLAYER_SKIP_FORWARD: &str = "podcast.player.skip_forward";
/// `podcast.player.skip_backward` — relative seek back by `secs` seconds (clamped to 0).
pub const ACTION_PLAYER_SKIP_BACKWARD: &str = "podcast.player.skip_backward";

// ---------------------------------------------------------------------------
// Player / download action payload structs (standalone wire format)
// ---------------------------------------------------------------------------
//
// These are the per-action structs used when the shell dispatches a single
// action type directly (not through the tagged-enum `PlayerAction`).
// Both wire formats are supported; the tagged enum is newer and preferred
// for new callers.

/// Payload for [`ACTION_PLAYER_PLAY`].
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct PlayAction {
    pub episode_id: String,
}

/// Payload for [`ACTION_PLAYER_PAUSE`]. Empty — pause always targets the active episode.
#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Serialize)]
pub struct PauseAction;

/// Payload for [`ACTION_PLAYER_SEEK`].
#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Serialize)]
pub struct SeekAction {
    pub position_secs: f64,
}

/// Payload for [`ACTION_PLAYER_SET_SPEED`]. Clamped to `0.5..=3.0`.
#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Serialize)]
pub struct SetSpeedAction {
    pub speed: f32,
}

/// Payload for [`ACTION_PLAYER_SET_VOLUME`]. Clamped to `0.0..=1.0`.
#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Serialize)]
pub struct SetVolumeAction {
    pub volume: f32,
}

/// Payload for [`ACTION_PLAYER_SET_SLEEP_TIMER`]. `Some(n)` arms a timer of
/// `n` seconds; `None` cancels any active timer.
#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Serialize)]
pub struct SetSleepTimerAction {
    #[serde(default)]
    pub secs: Option<u64>,
}

/// Payload for [`ACTION_PLAYER_STOP`]. Empty — stop always targets the active episode.
#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Serialize)]
pub struct StopAction;

/// Payload for [`ACTION_PLAYER_DOWNLOAD`].
#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct DownloadEpisodeAction {
    pub episode_id: String,
    pub url: String,
}

/// Payload for [`ACTION_PLAYER_CANCEL_DOWNLOAD`].
#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct CancelDownloadAction {
    pub episode_id: String,
}

/// Payload for [`ACTION_PLAYER_PAUSE_DOWNLOAD`].
#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct PauseDownloadAction {
    pub episode_id: String,
}

/// Payload for [`ACTION_PLAYER_RESUME_DOWNLOAD`].
#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct ResumeDownloadAction {
    pub episode_id: String,
}

/// Payload for [`ACTION_PLAYER_CANCEL_ALL_DOWNLOADS`]. Empty.
#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Eq, Serialize)]
pub struct CancelAllDownloadsAction;

#[cfg(test)]
#[path = "player_module_tests.rs"]
mod tests;
