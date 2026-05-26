//! Siri-action `ActionModule` — routes all `"podcast.siri.*"` dispatches.
//!
//! Episode-selection policy lives here in Rust (D0, D7): Swift only names
//! the intent, the kernel decides which episode to play.

use serde::{Deserialize, Serialize};

use nmp_core::substrate::ActionModule;
use nmp_core::ActorCommand;

/// Wire enum for all `"podcast.siri"` namespace actions.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum SiriAction {
    /// Play the latest unplayed episode from the whole library, or from a
    /// specific podcast when `podcast_id` is supplied.
    PlayLatest {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        podcast_id: Option<String>,
    },
    /// Resume the episode that was last playing. If no episode is loaded,
    /// falls back to the same selection as `PlayLatest`.
    Resume,
}

/// Action module for the `"podcast.siri"` namespace.
pub struct SiriActionModule;

impl ActionModule for SiriActionModule {
    const NAMESPACE: &'static str = "podcast.siri";

    type Action = SiriAction;

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

// Siri action id constants (M11 platform-integration contract)
//
// These ids are dispatched by iOS `AppIntents` performers and by Siri shortcut
// donations. Per D7 the iOS side only dispatches the intent; the kernel decides
// what "play latest" means (which podcast, which episode, what to do if nothing
// is queued). The intent performers carry no policy.

/// `podcast.siri.play_latest` — play the latest episode for the
/// optionally-supplied podcast (or across the whole library when omitted).
pub const ACTION_SIRI_PLAY_LATEST: &str = "podcast.siri.play_latest";
/// `podcast.siri.resume` — resume whatever was last playing.
pub const ACTION_SIRI_RESUME: &str = "podcast.siri.resume";

// ---------------------------------------------------------------------------
// Siri standalone payload structs
// ---------------------------------------------------------------------------

/// Payload for [`ACTION_SIRI_PLAY_LATEST`].
///
/// `podcast_id` is optional: when set, plays the latest episode for that
/// podcast; when omitted, picks across the whole library.
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Eq, Serialize)]
pub struct SiriPlayLatestAction {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub podcast_id: Option<String>,
}

/// Payload for [`ACTION_SIRI_RESUME`]. Empty — resume always targets the
/// most-recently-active episode.
#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Eq, Serialize)]
pub struct SiriResumeAction;

#[cfg(test)]
#[path = "siri_module_tests.rs"]
mod tests;
