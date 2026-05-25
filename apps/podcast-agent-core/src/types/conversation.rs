//! Agent-chat conversation domain.
//!
//! A conversation is an ordered sequence of [`NostrConversationTurn`]s the
//! podcast agent has produced together with the user. Despite the historical
//! `Nostr-` prefix the model is **LLM-chat**, not peer Nostr: turns carry an
//! [`ConversationRole`] (User/Assistant/System), not a Nostr counterparty.
//! Peer Nostr threads live in the future `podcast-peer` crate (M10).
//!
//! The shape is intentionally narrow — `id`, ordered `turns`, timestamps,
//! optional `title`. Persistence keys off `id`; the title is a human-readable
//! caption populated lazily by [`crate::types::agent_task::TaskKind`] runs.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Who produced a [`NostrConversationTurn`].
///
/// `User` covers anything the human typed or spoke; `Assistant` covers the
/// agent's textual replies; `System` is reserved for prompt/preamble turns
/// the orchestration layer injects (system prompts, tool-call results that
/// the UI should attribute to "the agent" rather than the assistant
/// persona itself).
#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ConversationRole {
    User,
    Assistant,
    System,
}

/// Optional structured metadata attached to a single turn.
///
/// Kept as a generic JSON blob here so callers can record provider id,
/// model name, token counts, or tool-call traces without forcing every
/// turn through a fixed schema. Strongly-typed sub-fields land alongside
/// their producer (e.g. the LLM provider crate in M7.B will export a
/// concrete `LlmTurnMetadata`).
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
pub struct TurnMetadata {
    /// Free-form provider tag (`"openrouter"`, `"ollama"`, …).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider: Option<String>,
    /// Free-form model identifier (`"anthropic/claude-3.7-sonnet"`, …).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    /// Provider-reported token count for this turn, when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tokens: Option<u32>,
    /// Catch-all for additional structured fields the producer wants to
    /// stash. M7.A keeps this field present so future serde-decoders read
    /// older persisted turns without a schema bump.
    #[serde(default, skip_serializing_if = "serde_json::Value::is_null")]
    pub extra: serde_json::Value,
}

/// One ordered entry in a conversation transcript.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct NostrConversationTurn {
    pub id: Uuid,
    pub role: ConversationRole,
    pub content: String,
    pub timestamp: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub metadata: Option<TurnMetadata>,
}

impl NostrConversationTurn {
    /// Build a turn that stamps `id` with a fresh v4 UUID and `timestamp`
    /// with the current wall clock. Tests that need determinism should
    /// build the struct literally.
    pub fn new(role: ConversationRole, content: impl Into<String>) -> Self {
        Self {
            id: Uuid::new_v4(),
            role,
            content: content.into(),
            timestamp: Utc::now(),
            metadata: None,
        }
    }

    /// Builder-style metadata setter — convenient for tests and for the
    /// LLM provider crate that wraps a finished generation.
    pub fn with_metadata(mut self, metadata: TurnMetadata) -> Self {
        self.metadata = Some(metadata);
        self
    }
}

/// A whole agent conversation: ordered turns plus housekeeping timestamps.
///
/// `id` is a v4 UUID minted by the [`crate::projections::ConversationActor`].
/// `title` is initially `None` and gets populated by a downstream titler
/// (the legacy `AgentChatTitleGenerator`); rendering layers fall back to
/// a turn-derived caption when `title` is absent.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct NostrConversation {
    pub id: Uuid,
    pub turns: Vec<NostrConversationTurn>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
}

impl NostrConversation {
    /// Fresh empty conversation; both timestamps stamped to `now`.
    pub fn new() -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            turns: Vec::new(),
            created_at: now,
            updated_at: now,
            title: None,
        }
    }

    /// Append a turn and advance `updated_at` to the turn's timestamp.
    ///
    /// The projection layer (`ConversationActor::add_turn`) is the
    /// canonical caller; this helper exists so unit tests and the future
    /// LLM-streaming projection can mutate a conversation in-place
    /// without re-wrapping the actor.
    pub fn push(&mut self, turn: NostrConversationTurn) {
        self.updated_at = turn.timestamp;
        self.turns.push(turn);
    }
}

impl Default for NostrConversation {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn turn_round_trips_through_serde() {
        let t = NostrConversationTurn {
            id: Uuid::nil(),
            role: ConversationRole::Assistant,
            content: "hello".into(),
            timestamp: DateTime::<Utc>::from_timestamp(1_700_000_000, 0).unwrap(),
            metadata: None,
        };
        let j = serde_json::to_string(&t).expect("encode");
        let d: NostrConversationTurn = serde_json::from_str(&j).expect("decode");
        assert_eq!(d, t);
    }

    #[test]
    fn turn_role_serializes_snake_case() {
        let t = NostrConversationTurn::new(ConversationRole::User, "hi");
        let j = serde_json::to_string(&t).expect("encode");
        assert!(j.contains("\"role\":\"user\""));
    }

    #[test]
    fn turn_with_metadata_round_trips() {
        let meta = TurnMetadata {
            provider: Some("openrouter".into()),
            model: Some("anthropic/claude".into()),
            tokens: Some(123),
            extra: serde_json::json!({"latency_ms": 42}),
        };
        let t = NostrConversationTurn::new(ConversationRole::Assistant, "ok")
            .with_metadata(meta.clone());
        let j = serde_json::to_string(&t).expect("encode");
        let d: NostrConversationTurn = serde_json::from_str(&j).expect("decode");
        assert_eq!(d.metadata, Some(meta));
    }

    #[test]
    fn conversation_push_advances_updated_at() {
        let mut c = NostrConversation::new();
        let ts = DateTime::<Utc>::from_timestamp(1_800_000_000, 0).unwrap();
        let turn = NostrConversationTurn {
            id: Uuid::nil(),
            role: ConversationRole::User,
            content: "yo".into(),
            timestamp: ts,
            metadata: None,
        };
        c.push(turn);
        assert_eq!(c.turns.len(), 1);
        assert_eq!(c.updated_at, ts);
    }

    #[test]
    fn conversation_omits_none_title() {
        let c = NostrConversation::new();
        let j = serde_json::to_string(&c).expect("encode");
        assert!(!j.contains("\"title\""));
    }
}
