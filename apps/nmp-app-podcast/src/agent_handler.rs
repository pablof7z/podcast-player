//! Agent-chat action handler — owns the in-memory conversation transcript
//! that `super::host_op_handler::PodcastHostOpHandler` routes
//! `podcast.agent.*` dispatches into.
//!
//! Extracted into its own module so `host_op_handler.rs` stays under the
//! 500-line hard limit (it already sits at 499 LOC on `main`). The shape
//! of this module deliberately mirrors the inline handler methods on
//! `PodcastHostOpHandler`: a small struct that holds the shared `Arc`s and
//! exposes one entry point per action variant, returning the
//! `{"ok":true}` envelope shape every action handler in this crate uses.
//!
//! Feature #32 is a UI scaffold — the handler appends the user message,
//! then appends a single canned assistant reply
//! (`"I'm thinking about your question…"`) so the iOS view has something
//! to render. Real LLM integration replaces the canned reply (and flips
//! `agent_busy` while streaming) in a follow-up PR without changing the
//! action wire shape or the projection wire shape.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use chrono::Utc;
use uuid::Uuid;

use crate::ffi::actions::AgentChatAction;
use crate::ffi::projections::AgentMessageSummary;

/// Owns the agent-chat conversation transcript and the `is_busy` /
/// "touched" flags. Held by `super::host_op_handler::PodcastHostOpHandler`
/// alongside the other domain handlers (audio, downloads, …) so all
/// state mutations happen on the actor thread.
pub struct AgentChatHandler {
    conversation: Arc<Mutex<Vec<AgentMessageSummary>>>,
    busy: Arc<AtomicBool>,
    touched: Arc<AtomicBool>,
    rev: Arc<AtomicU64>,
}

/// Canned assistant reply the scaffold appends after every user `Send`.
/// Real LLM integration replaces this with a streamed response.
pub const SCAFFOLD_ASSISTANT_REPLY: &str = "I'm thinking about your question…";

impl AgentChatHandler {
    pub fn new(
        conversation: Arc<Mutex<Vec<AgentMessageSummary>>>,
        busy: Arc<AtomicBool>,
        touched: Arc<AtomicBool>,
        rev: Arc<AtomicU64>,
    ) -> Self {
        Self { conversation, busy, touched, rev }
    }

    /// Route a typed [`AgentChatAction`] to the right entry point.
    pub fn handle(&self, action: AgentChatAction) -> serde_json::Value {
        match action {
            AgentChatAction::Send { message } => self.handle_send(message),
            AgentChatAction::Clear => self.handle_clear(),
        }
    }

    fn handle_send(&self, message: String) -> serde_json::Value {
        let trimmed = message.trim();
        if trimmed.is_empty() {
            return serde_json::json!({"ok": false, "error": "empty message"});
        }
        let now = Utc::now().timestamp();
        let user_msg = AgentMessageSummary {
            id: Uuid::new_v4().to_string(),
            role: "user".to_owned(),
            content: trimmed.to_owned(),
            created_at: now,
            is_generating: false,
        };
        // The scaffold reply is committed synchronously so the UI sees both
        // bubbles on the same snapshot tick. Real LLM integration will
        // insert a placeholder assistant row with `is_generating: true` and
        // flip `agent_busy` to `true` here, then mutate the row's content
        // + clear the flag from a streaming callback.
        let assistant_msg = AgentMessageSummary {
            id: Uuid::new_v4().to_string(),
            role: "assistant".to_owned(),
            content: SCAFFOLD_ASSISTANT_REPLY.to_owned(),
            created_at: now,
            is_generating: false,
        };
        match self.conversation.lock() {
            Ok(mut c) => {
                c.push(user_msg);
                c.push(assistant_msg);
            }
            Err(_) => return serde_json::json!({"ok": false, "error": "conversation poisoned"}),
        }
        self.touched.store(true, Ordering::Relaxed);
        self.busy.store(false, Ordering::Relaxed);
        self.rev.fetch_add(1, Ordering::Relaxed);
        serde_json::json!({"ok": true})
    }

    fn handle_clear(&self) -> serde_json::Value {
        match self.conversation.lock() {
            Ok(mut c) => c.clear(),
            Err(_) => return serde_json::json!({"ok": false, "error": "conversation poisoned"}),
        }
        // Keep `touched = true` so the snapshot surfaces an empty `agent`
        // (cleared) rather than reverting to `None` (never touched).
        self.busy.store(false, Ordering::Relaxed);
        self.rev.fetch_add(1, Ordering::Relaxed);
        serde_json::json!({"ok": true})
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_handler() -> AgentChatHandler {
        AgentChatHandler::new(
            Arc::new(Mutex::new(Vec::new())),
            Arc::new(AtomicBool::new(false)),
            Arc::new(AtomicBool::new(false)),
            Arc::new(AtomicU64::new(0)),
        )
    }

    #[test]
    fn send_appends_user_and_assistant() {
        let h = fresh_handler();
        let res = h.handle(AgentChatAction::Send {
            message: "Hello there".into(),
        });
        assert_eq!(res["ok"], true);

        let c = h.conversation.lock().unwrap();
        assert_eq!(c.len(), 2);
        assert_eq!(c[0].role, "user");
        assert_eq!(c[0].content, "Hello there");
        assert!(!c[0].is_generating);
        assert_eq!(c[1].role, "assistant");
        assert_eq!(c[1].content, SCAFFOLD_ASSISTANT_REPLY);
        assert!(!c[1].is_generating);

        assert!(h.touched.load(Ordering::Relaxed));
        assert!(!h.busy.load(Ordering::Relaxed));
        assert!(h.rev.load(Ordering::Relaxed) >= 1);
    }

    #[test]
    fn send_trims_input_and_rejects_empty() {
        let h = fresh_handler();
        let res = h.handle(AgentChatAction::Send {
            message: "   ".into(),
        });
        assert_eq!(res["ok"], false);
        assert_eq!(res["error"], "empty message");
        assert!(h.conversation.lock().unwrap().is_empty());

        let res = h.handle(AgentChatAction::Send {
            message: "  what's new?  ".into(),
        });
        assert_eq!(res["ok"], true);
        let c = h.conversation.lock().unwrap();
        assert_eq!(c[0].content, "what's new?");
    }

    #[test]
    fn clear_wipes_transcript_but_keeps_touched() {
        let h = fresh_handler();
        let _ = h.handle(AgentChatAction::Send {
            message: "hi".into(),
        });
        assert_eq!(h.conversation.lock().unwrap().len(), 2);

        let res = h.handle(AgentChatAction::Clear);
        assert_eq!(res["ok"], true);

        assert!(h.conversation.lock().unwrap().is_empty());
        // Touched stays true so the projection emits an empty `Some(agent)`
        // rather than reverting to `None`.
        assert!(h.touched.load(Ordering::Relaxed));
    }

    #[test]
    fn message_ids_are_unique() {
        let h = fresh_handler();
        for _ in 0..3 {
            let _ = h.handle(AgentChatAction::Send {
                message: "ping".into(),
            });
        }
        let c = h.conversation.lock().unwrap();
        let mut ids: Vec<&str> = c.iter().map(|m| m.id.as_str()).collect();
        let total = ids.len();
        ids.sort();
        ids.dedup();
        assert_eq!(ids.len(), total, "every message must have a unique id");
    }

    #[test]
    fn rev_bumps_on_each_mutation() {
        let h = fresh_handler();
        let start = h.rev.load(Ordering::Relaxed);
        let _ = h.handle(AgentChatAction::Send {
            message: "first".into(),
        });
        let after_send = h.rev.load(Ordering::Relaxed);
        let _ = h.handle(AgentChatAction::Clear);
        let after_clear = h.rev.load(Ordering::Relaxed);
        assert!(after_send > start);
        assert!(after_clear > after_send);
    }
}
