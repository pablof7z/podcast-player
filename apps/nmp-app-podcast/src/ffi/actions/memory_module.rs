//! Compound memory ActionModule — routes all `"podcast.memory.*"` dispatches.
//!
//! Agent memory (feature #33) is a flat key→value bag the AI agent and the
//! user can write to. The Rust kernel owns the durable store
//! ([`crate::store::PodcastStore::set_memory_fact`] + siblings); this module
//! routes the iOS wire shape into [`ActorCommand::DispatchHostOp`] so the
//! `PodcastHostOpHandler` can mutate the store and bump `rev`.
//!
//! Wire shape (matches the other `podcast.*` modules — `op` discriminator
//! drives the variant):
//!
//! ```text
//! podcast.memory.remember     { key: String, value: String, source: Option<String> }
//! podcast.memory.forget       { key: String }
//! podcast.memory.forget_all   {}
//! ```
//!
//! `source` defaults to `"user"` when absent so hand-rolled dispatches
//! (Settings → Add Memory) stay terse. The agent writes `source: "agent"`
//! when recording facts mid-conversation.

use serde::{Deserialize, Serialize};

use nmp_core::substrate::ActionModule;
use nmp_core::ActorCommand;

/// Wire enum for all `"podcast.memory"` namespace actions.
///
/// Same shape as [`super::podcast_module::PodcastAction`]:
/// `#[serde(tag = "op", rename_all = "snake_case")]` makes the JSON
/// discriminator the lowercase snake-case variant name.
#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum MemoryAction {
    /// Upsert a fact. When a fact with the same key already exists it is
    /// replaced in-place (the original `id` + `created_at` are preserved
    /// by the store — see `PodcastStore::set_memory_fact`).
    Remember {
        key: String,
        value: String,
        /// `"user"` or `"agent"`. Optional on the wire so hand-rolled
        /// Settings calls stay terse; defaults to `"user"` when absent.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        source: Option<String>,
    },
    /// Delete a fact by key. Silent no-op when no fact with that key
    /// exists.
    Forget { key: String },
    /// Wipe every fact in the bag. Used by the Settings "Clear All"
    /// confirmation.
    ForgetAll,
}

/// Single action module for the whole `"podcast.memory"` namespace.
///
/// `execute` serializes the typed `MemoryAction` back to JSON and hands it
/// to the actor as `ActorCommand::DispatchHostOp`. The installed
/// `PodcastHostOpHandler` (extended in `memory_handler.rs`) deserializes
/// it, runs the op (store write), and returns a `{"ok":true}` envelope.
/// All policy lives in the handler; the action module is pure routing.
pub struct MemoryActionModule;

impl ActionModule for MemoryActionModule {
    const NAMESPACE: &'static str = "podcast.memory";

    type Action = MemoryAction;

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
    fn remember_action_round_trips_with_explicit_source() {
        let a = MemoryAction::Remember {
            key: "preferred_genre".into(),
            value: "technology".into(),
            source: Some("agent".into()),
        };
        let json = serde_json::to_string(&a).expect("encode");
        assert!(json.contains(r#""op":"remember""#));
        assert!(json.contains(r#""source":"agent""#));
        let decoded: MemoryAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, a);
    }

    #[test]
    fn remember_action_omits_none_source_on_wire() {
        let a = MemoryAction::Remember {
            key: "k".into(),
            value: "v".into(),
            source: None,
        };
        let json = serde_json::to_string(&a).expect("encode");
        // `skip_serializing_if = "Option::is_none"` keeps the wire shape
        // narrow when the caller wants the default.
        assert!(!json.contains("source"));
        let decoded: MemoryAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, a);
    }

    #[test]
    fn remember_action_decodes_without_source_field() {
        // A hand-written call from Settings doesn't include `source`.
        let json = r#"{"op":"remember","key":"k","value":"v"}"#;
        let decoded: MemoryAction = serde_json::from_str(json).expect("decode");
        assert_eq!(
            decoded,
            MemoryAction::Remember {
                key: "k".into(),
                value: "v".into(),
                source: None,
            }
        );
    }

    #[test]
    fn forget_action_round_trips() {
        let a = MemoryAction::Forget {
            key: "preferred_genre".into(),
        };
        let json = serde_json::to_string(&a).expect("encode");
        assert!(json.contains(r#""op":"forget""#));
        assert!(json.contains(r#""key":"preferred_genre""#));
        let decoded: MemoryAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, a);
    }

    #[test]
    fn forget_all_action_round_trips_as_bare_op() {
        let a = MemoryAction::ForgetAll;
        let json = serde_json::to_string(&a).expect("encode");
        assert_eq!(json, r#"{"op":"forget_all"}"#);
        let decoded: MemoryAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, a);
    }

    #[test]
    fn execute_emits_dispatch_host_op() {
        let action = MemoryAction::Remember {
            key: "k".into(),
            value: "v".into(),
            source: None,
        };
        let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
        MemoryActionModule::execute(action, "corr-7", &|cmd| {
            commands.lock().unwrap().push(cmd);
        })
        .expect("execute ok");
        let commands = commands.into_inner().unwrap();
        assert_eq!(commands.len(), 1);
        let ActorCommand::DispatchHostOp { action_json, correlation_id } = &commands[0] else {
            panic!("expected DispatchHostOp");
        };
        assert_eq!(correlation_id, "corr-7");
        let v: serde_json::Value = serde_json::from_str(action_json).expect("json");
        assert_eq!(v["op"], "remember");
    }
}
