//! Clip-action `ActionModule` — routes all `"podcast.clip.*"` dispatches.
//!
//! Swift encodes every clip action as `{"op":"<variant>", ...fields}`. The
//! `#[serde(tag = "op", rename_all = "snake_case")]` discriminator maps the
//! string `op` value to the enum variant. The module's `execute` body
//! forwards the whole action as `ActorCommand::DispatchHostOp` so the
//! `PodcastHostOpHandler` (running on the actor thread) can mutate the
//! shared `Vec<ClipRecord>` via [`crate::clip_handler::ClipHandler`]
//! without the kernel naming podcast-domain nouns (D0).
//!
//! ## Wire shape
//!
//! ```text
//! podcast.clip.create     { episode_id, start_secs, end_secs, title? }
//! podcast.clip.delete     { clip_id }
//! podcast.clip.auto_snip  { episode_id, position_secs }
//! ```
//!
//! `create` and `auto_snip` return `{"ok":true,"clip_id":"<uuid>"}`;
//! `delete` returns `{"ok":true}` (success even when the id is unknown
//! — idempotent delete).

use serde::{Deserialize, Serialize};

use nmp_core::substrate::ActionModule;
use nmp_core::ActorCommand;

/// `podcast.clip.create` — create a user-defined clip from `[start, end]`.
pub const ACTION_CLIP_CREATE: &str = "podcast.clip.create";
/// `podcast.clip.delete` — remove a previously-created clip by id.
pub const ACTION_CLIP_DELETE: &str = "podcast.clip.delete";
/// `podcast.clip.auto_snip` — create a clip from `[position-30, position+30]`,
/// clamped to `[0, duration]` when the episode duration is known.
pub const ACTION_CLIP_AUTO_SNIP: &str = "podcast.clip.auto_snip";

/// Wire enum for all `"podcast.clip"` namespace actions.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum ClipAction {
    Create {
        episode_id: String,
        start_secs: f64,
        end_secs: f64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        title: Option<String>,
    },
    Delete {
        clip_id: String,
    },
    AutoSnip {
        episode_id: String,
        position_secs: f64,
    },
}

/// Action module for the `"podcast.clip"` namespace.
pub struct ClipActionModule;

impl ActionModule for ClipActionModule {
    const NAMESPACE: &'static str = "podcast.clip";

    type Action = ClipAction;

    fn is_async_completing() -> bool {
        false
    }

    fn execute(
        action: Self::Action,
        correlation_id: &str,
        send: &dyn Fn(ActorCommand),
    ) -> Result<(), String> {
        let action_json = serde_json::to_string(&action).map_err(|e| e.to_string())?;
        send(ActorCommand::DispatchHostOp {
            action_json,
            correlation_id: correlation_id.to_owned(),
        });
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn action_ids_match_documented_strings() {
        assert_eq!(ACTION_CLIP_CREATE, "podcast.clip.create");
        assert_eq!(ACTION_CLIP_DELETE, "podcast.clip.delete");
        assert_eq!(ACTION_CLIP_AUTO_SNIP, "podcast.clip.auto_snip");
    }

    #[test]
    fn create_action_round_trips_with_title() {
        let action = ClipAction::Create {
            episode_id: "ep-1".into(),
            start_secs: 10.0,
            end_secs: 70.0,
            title: Some("Marcus on retrieval".into()),
        };
        let json = serde_json::to_string(&action).expect("encode");
        assert!(json.contains(r#""op":"create""#));
        assert!(json.contains(r#""episode_id":"ep-1""#));
        assert!(json.contains(r#""start_secs":10.0"#));
        assert!(json.contains(r#""end_secs":70.0"#));
        assert!(json.contains(r#""title":"Marcus on retrieval""#));
        let decoded: ClipAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, action);
    }

    #[test]
    fn create_action_omits_none_title() {
        let action = ClipAction::Create {
            episode_id: "ep-1".into(),
            start_secs: 10.0,
            end_secs: 70.0,
            title: None,
        };
        let json = serde_json::to_string(&action).expect("encode");
        assert!(!json.contains("\"title\""));
        let decoded: ClipAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, action);
    }

    #[test]
    fn delete_action_round_trips() {
        let action = ClipAction::Delete {
            clip_id: "clip-1".into(),
        };
        let json = serde_json::to_string(&action).expect("encode");
        assert!(json.contains(r#""op":"delete""#));
        assert!(json.contains(r#""clip_id":"clip-1""#));
        let decoded: ClipAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, action);
    }

    #[test]
    fn auto_snip_action_round_trips() {
        let action = ClipAction::AutoSnip {
            episode_id: "ep-1".into(),
            position_secs: 100.0,
        };
        let json = serde_json::to_string(&action).expect("encode");
        assert!(json.contains(r#""op":"auto_snip""#));
        assert!(json.contains(r#""episode_id":"ep-1""#));
        assert!(json.contains(r#""position_secs":100.0"#));
        let decoded: ClipAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, action);
    }

    #[test]
    fn execute_emits_dispatch_host_op() {
        let action = ClipAction::Delete {
            clip_id: "clip-7".into(),
        };
        let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
        ClipActionModule::execute(action, "corr-1", &|cmd| {
            commands.lock().unwrap().push(cmd);
        })
        .expect("execute ok");
        let commands = commands.into_inner().unwrap();
        assert_eq!(commands.len(), 1);
        let ActorCommand::DispatchHostOp { action_json, correlation_id } = &commands[0] else {
            panic!("expected DispatchHostOp");
        };
        assert_eq!(correlation_id, "corr-1");
        let v: serde_json::Value = serde_json::from_str(action_json).expect("json");
        assert_eq!(v["op"], "delete");
        assert_eq!(v["clip_id"], "clip-7");
    }
}
