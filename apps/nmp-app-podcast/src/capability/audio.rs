//! Podcast-local audio capability contract — `nmp.audio.capability`.
//!
//! This is the schema the iOS executor (`Capabilities/AudioCapability.swift`,
//! landing in M3.C) implements and the Rust `PlayerActor` (see
//! [`crate::player`]) drives. Rust serializes an [`AudioCommand`]; iOS
//! executes it against `AVPlayer` and sends an [`AudioReport`] back.
//!
//! ## Doctrine
//!
//! * **D7 — capabilities report, never decide.** iOS plays exactly what
//!   Rust tells it to play and reports exactly what happens; it never
//!   decides what to do next on `Ended`, on a `SleepTimerFired`, or on
//!   a buffering stall. End-of-queue, sleep-timer cancellation, and
//!   retry policy all live in [`crate::player`].
//! * **D8 — bounded reactivity.** `Playing` reports carry the current
//!   `position_secs` at ≤4 Hz; the kernel collapses them into the next
//!   render tick (≤60 Hz). No per-frame churn.
//! * **D9 — kernel owns time.** Sleep-timer expiry is decided in
//!   [`crate::player`], not on the iOS side. The capability owns no
//!   timers beyond AVFoundation's intrinsic playback clock.
//!
//! ## Namespace
//!
//! The namespace string is `nmp.audio.capability` to match the existing
//! `HttpCapability::namespace` / `KeychainCapability` convention and the
//! active NMP feature-parity plan. (A podcast-prefixed
//! `pcst.audio.capability` was briefly under
//! consideration during M3.A drafting; the canonical nmp form won so
//! M3.B/C see the same string the broader plan uses.)
//!
//! ## Schema stability
//!
//! This is the M3.A skeleton — a podcast-local two-enum
//! Command/Report shape. The canonical `nmp-core::capability::audio`
//! uses a three-enum
//! `AudioRequest`/`Response`/`Event` split. When that lands in
//! `nostrmultiplatform`, M3.B/C will reconcile this contract against
//! the canonical one in a follow-up migration. The split here is
//! deliberately narrower so the iOS executor in M3.B has a stable target
//! to implement *now* without blocking on the cross-repo dependency.

use serde::{Deserialize, Serialize};

/// Capability namespace string. Mirrors `HttpCapability::namespace` /
/// `KeyringCapability::NAMESPACE` so the iOS-side router can dispatch by
/// the same string the broader capability plan uses.
pub const AUDIO_CAPABILITY_NAMESPACE: &str = "nmp.audio.capability";

// ---------------------------------------------------------------------------
// Rust → iOS: AudioCommand
// ---------------------------------------------------------------------------

/// Commands Rust dispatches to the iOS audio capability.
///
/// Wire form is `serde`-tagged on `"type"` (`snake_case`):
///
/// ```text
/// {"type":"load","url":"…","position_secs":12.5}
/// {"type":"play"}
/// {"type":"pause"}
/// {"type":"seek","position_secs":42.0}
/// {"type":"set_volume","volume":0.75}
/// {"type":"set_speed","speed":1.5}
/// {"type":"set_sleep_timer","secs":1800}
/// {"type":"set_sleep_timer","secs":null}
/// {"type":"stop"}
/// ```
///
/// **D7:** these are *imperative* actions on the player; the iOS side
/// runs each one against `AVPlayer` and reports the resulting state.
/// There is no `decide`-flavoured command — every variant maps to a
/// concrete AVFoundation call.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AudioCommand {
    /// Replace the current item with `url` and seek to `position_secs`.
    /// The iOS executor begins buffering immediately; explicit `Play`
    /// follows.
    Load {
        /// HTTP/HTTPS URL or local `file://` URL for the enclosure.
        url: String,
        /// Initial playhead, in seconds from the start of the track.
        position_secs: f64,
    },
    /// Begin playback at the current rate and volume.
    Play,
    /// Pause playback without releasing the audio session.
    Pause,
    /// Seek to absolute `position_secs` from the start of the track.
    Seek { position_secs: f64 },
    /// Set output volume (engine-level, not system-level). Clamped to
    /// `0.0..=1.0` by the executor.
    SetVolume { volume: f32 },
    /// Set playback rate. Clamped to `0.5..=3.0` by the executor.
    SetSpeed { speed: f32 },
    /// Arm or cancel a sleep timer.
    ///
    /// `Some(n)` arms a timer that fires after `n` seconds of wall
    /// time; the executor reports `SleepTimerFired` on expiry. `None`
    /// cancels any active timer.
    ///
    /// **D9:** the actual decision to stop on expiry lives in
    /// [`crate::player`]; this command only configures the
    /// system-level timer for fade-out / lock-screen UI purposes.
    SetSleepTimer {
        #[serde(default)]
        secs: Option<u64>,
    },
    /// Stop playback and tear down the current item. Releases the
    /// audio session.
    Stop,
}

impl AudioCommand {
    /// Convenience: construct a `Load` command from owned strings.
    #[must_use]
    pub fn load(url: impl Into<String>, position_secs: f64) -> Self {
        Self::Load {
            url: url.into(),
            position_secs,
        }
    }

    /// Convenience: construct a `Seek` command.
    #[must_use]
    pub fn seek(position_secs: f64) -> Self {
        Self::Seek { position_secs }
    }
}

// ---------------------------------------------------------------------------
// iOS → Rust: AudioReport
// ---------------------------------------------------------------------------

/// Events the iOS audio capability sends back to Rust.
///
/// Wire form is `serde`-tagged on `"type"` (`snake_case`).
///
/// **D7:** these are *observations* of what AVFoundation actually did,
/// not invitations for Rust to decide something. The iOS side never
/// includes a "you should do X" field; the kernel projects the report
/// into [`crate::player::PlayerState`] and emits any follow-up
/// [`AudioCommand`] from its own state.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AudioReport {
    /// AVPlayer is playing `url`. `position_secs` is the live playhead;
    /// `duration_secs` is the resolved track length (≤0 if unknown).
    ///
    /// **D8:** the iOS side throttles these to ≤4 Hz; the kernel
    /// collapses bursts into the next tick.
    Playing {
        url: String,
        position_secs: f64,
        duration_secs: f64,
    },
    /// AVPlayer paused at `position_secs`. Sent on user pause,
    /// interruption begin, or `Pause` command.
    Paused { url: String, position_secs: f64 },
    /// AVPlayer was stopped and the current item was torn down.
    Stopped,
    /// A `Load` or playback attempt failed. `error` is a human-readable
    /// diagnostic (NSError `localizedDescription` or similar).
    Failed { url: String, error: String },
    /// Buffering progress for the current item. `fraction` is the
    /// `0.0..=1.0` loaded-ahead ratio (per `loadedTimeRanges`).
    BufferingProgress { fraction: f32 },
    /// The system-level sleep timer the executor was holding fired.
    /// The player decides whether to stop, fade, or extend.
    SleepTimerFired,
    /// AVPlayer played the current item to its natural end
    /// (`AVPlayerItemDidPlayToEndTime`). Distinct from `Stopped`
    /// (user/command-initiated). The kernel uses this to mark the
    /// episode `played = true` and to auto-advance the queue.
    ItemEnd { url: String },
}

#[cfg(test)]
#[path = "audio_tests.rs"]
mod tests;
