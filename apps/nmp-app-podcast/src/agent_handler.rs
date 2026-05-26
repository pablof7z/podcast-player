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
#[path = "agent_handler_tests.rs"]
mod tests;
