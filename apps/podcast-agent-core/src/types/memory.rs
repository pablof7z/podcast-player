//! Agent memory domain.
//!
//! The agent keeps a long-lived store of [`AgentMemory`] entries — facts,
//! preferences, and observations it has been instructed to remember
//! between conversations. This is a thin Rust port of the legacy
//! `Domain/AgentMemory.swift` type, extended with a [`MemoryKind`] tag so
//! the future M7.B retrieval layer can filter by category without
//! string-sniffing the content.
//!
//! Memories are append-only at the storage layer; deletions are
//! represented as a `deleted: true` flag (soft delete) so a memory can
//! be resurrected by toggling the bit, mirroring the legacy contract.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// What kind of long-lived knowledge the memory represents.
///
/// `Fact` covers everything by default — the legacy Swift store didn't
/// distinguish kinds, so older persisted memories serde-decode into
/// [`MemoryKind::Fact`] via [`Default`].
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum MemoryKind {
    /// Plain factual statement ("user prefers 1.5× playback").
    #[default]
    Fact,
    /// Stated user preference (`"summaries should be ≤200 words"`).
    Preference,
    /// Recurring task or routine (`"every Monday: weekend digest"`).
    Routine,
    /// Free-form note the user typed into the memories sheet.
    Note,
}

/// One row in the agent's long-lived memory store.
///
/// The shape mirrors the legacy `AgentMemory` (`id`, `content`,
/// `createdAt`, `deleted`) plus the new [`MemoryKind`] tag. `deleted` is
/// retained as a soft-delete flag for parity with the existing
/// persistence layer.
#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct AgentMemory {
    pub id: Uuid,
    pub content: String,
    pub created_at: DateTime<Utc>,
    pub deleted: bool,
    /// Tag the retrieval layer can filter on. Optional only for
    /// forward-compat with persisted Swift JSON that predates this
    /// field — a missing value decodes as [`MemoryKind::Fact`].
    #[serde(default)]
    pub kind: MemoryKind,
}

impl AgentMemory {
    /// Mint a fresh memory of `kind` with the supplied `content`.
    pub fn new(kind: MemoryKind, content: impl Into<String>) -> Self {
        Self {
            id: Uuid::new_v4(),
            content: content.into(),
            created_at: Utc::now(),
            deleted: false,
            kind,
        }
    }

    /// `true` iff the memory is still "live" (i.e. not soft-deleted).
    pub fn is_active(&self) -> bool {
        !self.deleted
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn memory_kind_default_is_fact() {
        assert_eq!(MemoryKind::default(), MemoryKind::Fact);
    }

    #[test]
    fn memory_kind_round_trips() {
        let cases = [
            MemoryKind::Fact,
            MemoryKind::Preference,
            MemoryKind::Routine,
            MemoryKind::Note,
        ];
        for k in cases {
            let j = serde_json::to_string(&k).expect("encode");
            let d: MemoryKind = serde_json::from_str(&j).expect("decode");
            assert_eq!(d, k);
        }
    }

    #[test]
    fn agent_memory_round_trips() {
        let m = AgentMemory {
            id: Uuid::nil(),
            content: "user likes 1.5x".into(),
            created_at: DateTime::<Utc>::from_timestamp(1_700_000_000, 0).unwrap(),
            deleted: false,
            kind: MemoryKind::Preference,
        };
        let j = serde_json::to_string(&m).expect("encode");
        let d: AgentMemory = serde_json::from_str(&j).expect("decode");
        assert_eq!(d, m);
    }

    #[test]
    fn agent_memory_missing_kind_decodes_as_fact() {
        // Forward-compat with legacy persisted JSON predating `kind`.
        let payload = r#"{"id":"00000000-0000-0000-0000-000000000000","content":"x","created_at":"2024-01-01T00:00:00Z","deleted":false}"#;
        let d: AgentMemory = serde_json::from_str(payload).expect("decode");
        assert_eq!(d.kind, MemoryKind::Fact);
    }

    #[test]
    fn is_active_tracks_deleted_flag() {
        let mut m = AgentMemory::new(MemoryKind::Fact, "x");
        assert!(m.is_active());
        m.deleted = true;
        assert!(!m.is_active());
    }
}
