//! AI chapter `ActionModule` — routes all `"podcast.chapters.*"` dispatches.
//!
//! Sibling to [`super::player_module`] / [`super::podcast_module`]; lives
//! in its own namespace so the iOS shell can dispatch
//! `podcast.chapters.compile` literally (matching the legacy
//! `App/Sources/Services/AIChapterCompiler.swift` mental model) without
//! piggy-backing on the broader `podcast.*` action enum.
//!
//! The kernel-side body of `compile` lives in [`crate::ai_chapters`]; this
//! file is pure routing (D7 — the action module decides nothing).
//!
//! ## Wire shape
//!
//! `podcast.chapters.compile { episode_id }` — synthesize equal-length
//! stub chapters from the cached transcript for `episode_id`. Returns
//! `{"ok":true,"status":"compiling","chapter_count":<n>}` on success,
//! `{"ok":true,"status":"already_has_chapters"}` when the episode
//! already has chapters (RSS or prior compile), or
//! `{"ok":false,"error":"no_transcript"|"no_duration"|…}` on the
//! gate-failure cases. See [`crate::ai_chapters::handle_compile_chapters`].

use serde::{Deserialize, Serialize};

use nmp_core::substrate::ActionModule;
use nmp_core::ActorCommand;

/// Wire enum for all `"podcast.chapters"` namespace actions.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum ChaptersAction {
    /// Synthesize AI chapters for an episode that has a cached
    /// transcript but no RSS / Podcasting 2.0 chapters yet.
    Compile { episode_id: String },
}

/// Action module for the `"podcast.chapters"` namespace.
pub struct ChaptersActionModule;

impl ActionModule for ChaptersActionModule {
    const NAMESPACE: &'static str = "podcast.chapters";

    type Action = ChaptersAction;

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
    fn compile_action_round_trips() {
        let action = ChaptersAction::Compile { episode_id: "ep-1".into() };
        let json = serde_json::to_string(&action).expect("encode");
        assert!(json.contains(r#""op":"compile""#));
        assert!(json.contains(r#""episode_id":"ep-1""#));
        let decoded: ChaptersAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, action);
    }

    #[test]
    fn execute_emits_dispatch_host_op_with_payload() {
        let action = ChaptersAction::Compile { episode_id: "ep-2".into() };
        let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
        ChaptersActionModule::execute(action, "corr-1", &|cmd| {
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
        assert_eq!(v["op"], "compile");
        assert_eq!(v["episode_id"], "ep-2");
    }
}
