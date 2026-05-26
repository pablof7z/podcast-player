//! Briefing action payloads + stable string ids.
//!
//! Stable string ids the iOS shell encodes alongside JSON payloads when
//! it dispatches a briefing action through the kernel. The `ActionModule`
//! impls that actually mutate state arrive in M9.B; M9.A only fixes the
//! wire shape so the Swift bridge has a contract to encode against.
//!
//! ## Wire shape
//!
//! ```text
//! podcast.briefing.request   — RequestBriefingAction
//! podcast.briefing.schedule  — ScheduleBriefingAction  { schedule }
//! podcast.briefing.cancel    — CancelBriefingAction
//! ```

use serde::{Deserialize, Serialize};

use crate::types::BriefingSchedule;

/// `podcast.briefing.request` — kick off a one-shot briefing
/// generation outside the regular schedule (e.g. "Generate now"
/// button in Settings).
pub const ACTION_BRIEFING_REQUEST: &str = "podcast.briefing.request";

/// `podcast.briefing.schedule` — set or replace the user-configured
/// briefing schedule.
pub const ACTION_BRIEFING_SCHEDULE: &str = "podcast.briefing.schedule";

/// `podcast.briefing.cancel` — cancel the in-flight briefing (when
/// pending/generating/ready). Idempotent: a no-op once delivered.
pub const ACTION_BRIEFING_CANCEL: &str = "podcast.briefing.cancel";

/// Payload for [`ACTION_BRIEFING_REQUEST`]. Empty — the kernel mints
/// a fresh `Briefing::pending` from the current schedule (or the
/// scheduler's default schedule if none is set) and dispatches the
/// composer.
#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Eq, Serialize)]
pub struct RequestBriefingAction;

/// Payload for [`ACTION_BRIEFING_SCHEDULE`].
#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct ScheduleBriefingAction {
    pub schedule: BriefingSchedule,
}

/// Payload for [`ACTION_BRIEFING_CANCEL`]. Empty — cancellation
/// always targets the in-flight briefing.
#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Eq, Serialize)]
pub struct CancelBriefingAction;

#[cfg(test)]
#[path = "actions_tests.rs"]
mod tests;
