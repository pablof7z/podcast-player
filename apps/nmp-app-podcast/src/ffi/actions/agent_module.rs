//! Agent-chat `ActionModule` — routes all `"podcast.agent.*"` dispatches.
//!
//! Swift encodes every agent action as `{"op":"<variant>", ...fields}`.
//! The `#[serde(tag = "op", rename_all = "snake_case")]` discriminator maps
//! the string `op` value to the enum variant. The module's `execute` body
//! forwards the whole action as `ActorCommand::DispatchHostOp` so the
//! `PodcastHostOpHandler` (running on the actor thread) can append to the
//! shared in-memory conversation without the kernel naming podcast-domain
//! nouns (D0).
//!
//! ## Wire shape
//!
//! ```text
//! podcast.agent.send  — AgentChatAction::Send  { message: String }
//! podcast.agent.clear — AgentChatAction::Clear
//! ```
//!
//! Feature #32 is a UI scaffold: the handler appends the user message and
//! a single canned assistant reply (`"I'm thinking about your question…"`)
//! to the conversation in-memory and returns `{"ok":true}`. Real LLM
//! integration replaces the canned reply with a streaming response in a
//! follow-up PR without changing this wire shape.
//!
//! ## Naming
//!
//! `AgentChatAction` (not `AgentAction`) so it doesn't collide with
//! `podcast_agent_core::AgentAction`-style names re-exported from the
//! agent-core crate. The two surfaces are intentionally separate: this
//! module owns the single-thread chat UI; `podcast-agent-core` owns the
//! multi-conversation `ConversationActor` model that the UI scaffold
//! doesn't depend on yet.

use serde::{Deserialize, Serialize};

use nmp_core::substrate::ActionModule;
use nmp_core::ActorCommand;

/// Wire enum for all `"podcast.agent"` namespace actions.
///
/// `#[serde(tag = "op", rename_all = "snake_case")]` makes the JSON
/// discriminator the lowercase snake-case variant name:
/// `send` → `{"op":"send","message":"..."}`,
/// `clear` → `{"op":"clear"}`.
#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum AgentChatAction {
    /// Append the user's `message` to the conversation transcript, then
    /// append a canned assistant reply. Returns `{"ok":true}`.
    Send { message: String },
    /// Wipe the in-memory transcript. Returns `{"ok":true}`. The
    /// snapshot builder keeps `agent` `Some` with an empty `messages`
    /// after this so the UI can distinguish "user explicitly cleared"
    /// from "agent never touched" (which would be `None`).
    Clear,
}

/// Action module for the `"podcast.agent"` namespace.
///
/// `execute` serializes the typed [`AgentChatAction`] back to JSON and
/// hands it to the actor as `ActorCommand::DispatchHostOp`. The installed
/// [`crate::host_op_handler::PodcastHostOpHandler`] deserializes it,
/// mutates the in-memory conversation on the handle, and returns
/// `{"ok":true}`. Pure routing; no policy in this module.
pub struct AgentActionModule;

impl ActionModule for AgentActionModule {
    const NAMESPACE: &'static str = "podcast.agent";

    type Action = AgentChatAction;

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
mod tests {
    use super::*;

    #[test]
    fn send_action_round_trips() {
        let action = AgentChatAction::Send {
            message: "What's new today?".into(),
        };
        let json = serde_json::to_string(&action).expect("encode");
        assert!(json.contains(r#""op":"send""#));
        assert!(json.contains(r#""message":"What's new today?""#));
        let decoded: AgentChatAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, action);
    }

    #[test]
    fn clear_action_round_trips() {
        let action = AgentChatAction::Clear;
        let json = serde_json::to_string(&action).expect("encode");
        assert_eq!(json, r#"{"op":"clear"}"#);
        let decoded: AgentChatAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, action);
    }

    #[test]
    fn namespace_is_podcast_agent() {
        assert_eq!(AgentActionModule::NAMESPACE, "podcast.agent");
    }

    #[test]
    fn execute_emits_dispatch_host_op() {
        let action = AgentChatAction::Send {
            message: "hi".into(),
        };
        let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
        AgentActionModule::execute(action, "corr-1", &|cmd| {
            commands.lock().unwrap().push(cmd);
        })
        .expect("execute ok");
        let commands = commands.into_inner().unwrap();
        assert_eq!(commands.len(), 1);
        let ActorCommand::DispatchHostOp { action_json, correlation_id } = &commands[0]
        else {
            panic!("expected DispatchHostOp");
        };
        assert_eq!(correlation_id, "corr-1");
        let v: serde_json::Value =
            serde_json::from_str(action_json).expect("json");
        assert_eq!(v["op"], "send");
        assert_eq!(v["message"], "hi");
    }
}
