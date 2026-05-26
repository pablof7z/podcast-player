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

#[cfg(test)]
#[path = "siri_module_tests.rs"]
mod tests;
