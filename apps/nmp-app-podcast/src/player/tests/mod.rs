//! Unit tests for [`super::PlayerActor`].
//!
//! Split by concern so each module stays comfortably under the 300-LOC
//! soft cap:
//!
//! * [`reports`] — AudioReport-by-variant projection tests
//!   (`Playing`, `Paused`, `Stopped`, `Failed`, `BufferingProgress`).
//! * [`sleep_timer`] — D9 sleep-timer expiry semantics
//!   (arming, expiry mid-Playing, `SleepTimerFired`, cancel).
//! * [`mutators`] — Direct state mutators
//!   (`stage_load`, `set_speed`, `set_volume`) and default constructors.
//! * [`ad_skip`] — Auto ad-skip session bookkeeping.
//!
//! The playback queue ("Up Next") lives on the canonical
//! [`crate::queue::PlaybackQueue`], not on `PlayerActor`; its unit tests
//! are in `crate::queue::tests` and the `podcast.player` queue-op routing
//! is covered by `crate::host_op_handler::player_actions::tests`.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

mod ad_skip;
mod mutators;
mod reports;
mod sleep_timer;

/// A fixed instant used as `now` in every test where the absolute value
/// doesn't matter — only the relative offsets to the sleep-timer
/// deadline.
pub(super) fn t0() -> SystemTime {
    UNIX_EPOCH + Duration::from_secs(1_700_000_000)
}
