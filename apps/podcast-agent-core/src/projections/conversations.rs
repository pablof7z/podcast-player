//! In-memory state machine for agent-chat conversations + approvals.
//!
//! [`ConversationActor`] is the pure-data owner of every active
//! [`NostrConversation`] and outstanding [`PendingApproval`]. It exposes
//! a narrow imperative API the kernel-side `ActionModule` impls invoke
//! when an agent action lands; persistence + FFI snapshot serialization
//! live one layer up (M7.B for the action modules, this milestone for
//! the snapshot dataclass).
//!
//! ## Doctrine
//!
//! * **Pure** — no async, no network, no `Utc::now()` inside mutating
//!   methods that take their timestamps from the caller. Tests can drive
//!   the state machine deterministically.
//! * **Borrow-free outputs** — every accessor returns either an owned
//!   value or a `Vec<Owned>`, so the projection layer can hand results
//!   to serde without lifetime juggling.

use std::collections::HashMap;

use uuid::Uuid;

use crate::types::{
    ApprovalDecision, NostrConversation, NostrConversationTurn, PendingApproval,
};

/// State machine for active conversations and pending approvals.
#[derive(Clone, Debug, Default)]
pub struct ConversationActor {
    conversations: HashMap<Uuid, NostrConversation>,
    pending_approvals: HashMap<Uuid, PendingApproval>,
    /// Most recently touched conversation id — surfaced into the
    /// snapshot so the UI can highlight "active" without re-sorting
    /// every tick.
    latest_conversation_id: Option<Uuid>,
}

impl ConversationActor {
    pub fn new() -> Self {
        Self::default()
    }

    // ── conversations ────────────────────────────────────────────────

    /// Mint a fresh empty conversation and return its id. The actor
    /// keeps the resulting [`NostrConversation`] in its store.
    pub fn new_conversation(&mut self) -> Uuid {
        let convo = NostrConversation::new();
        let id = convo.id;
        self.conversations.insert(id, convo);
        self.latest_conversation_id = Some(id);
        id
    }

    /// Append `turn` to `conversation_id`. Silently no-ops when the
    /// conversation isn't known — the kernel-side action module is
    /// responsible for minting before send.
    pub fn add_turn(&mut self, conversation_id: Uuid, turn: NostrConversationTurn) {
        if let Some(c) = self.conversations.get_mut(&conversation_id) {
            c.push(turn);
            self.latest_conversation_id = Some(conversation_id);
        }
    }

    /// Set a conversation's `title` if it exists. No-op on miss.
    pub fn set_title(&mut self, conversation_id: Uuid, title: impl Into<String>) {
        if let Some(c) = self.conversations.get_mut(&conversation_id) {
            c.title = Some(title.into());
        }
    }

    /// Drop every turn but keep the [`NostrConversation`] row (id +
    /// timestamps remain so the UI can reuse the slot).
    pub fn clear_conversation(&mut self, conversation_id: Uuid) {
        if let Some(c) = self.conversations.get_mut(&conversation_id) {
            c.turns.clear();
            c.title = None;
        }
    }

    /// Return the last `max_turns` turns of `conversation_id`, in
    /// timestamp order. Returns an empty `Vec` when the conversation
    /// isn't known.
    pub fn conversation_context(
        &self,
        id: Uuid,
        max_turns: usize,
    ) -> Vec<NostrConversationTurn> {
        let Some(c) = self.conversations.get(&id) else {
            return Vec::new();
        };
        if max_turns == 0 || c.turns.is_empty() {
            return Vec::new();
        }
        let start = c.turns.len().saturating_sub(max_turns);
        c.turns[start..].to_vec()
    }

    /// Snapshot accessor: how many conversations live in the store.
    pub fn active_count(&self) -> usize {
        self.conversations.len()
    }

    /// Snapshot accessor: most recently touched conversation id (if any).
    pub fn latest_conversation_id(&self) -> Option<Uuid> {
        self.latest_conversation_id
    }

    /// Borrowing accessor used by the snapshot builder. Returns
    /// `None` when the conversation has been cleared/dropped.
    pub fn conversation(&self, id: Uuid) -> Option<&NostrConversation> {
        self.conversations.get(&id)
    }

    // ── approvals ────────────────────────────────────────────────────

    /// Park a new pending approval. If an approval with the same id was
    /// already parked it gets replaced (the kernel layer guards against
    /// id collisions; the actor itself is tolerant).
    pub fn add_approval(&mut self, approval: PendingApproval) {
        self.pending_approvals.insert(approval.id, approval);
    }

    /// Resolve a pending approval and return the recorded decision. The
    /// approval is removed from the pending set regardless of decision —
    /// the caller is responsible for fanning out the side effect.
    /// Returns `None` if the approval id wasn't pending.
    pub fn decide_approval(
        &mut self,
        approval_id: Uuid,
        decision: ApprovalDecision,
    ) -> Option<(PendingApproval, ApprovalDecision)> {
        self.pending_approvals
            .remove(&approval_id)
            .map(|a| (a, decision))
    }

    /// Read-only iteration over outstanding approvals, in insertion-
    /// undefined order. Callers that need stable ordering should sort by
    /// `requested_at`.
    pub fn pending_approvals(&self) -> Vec<PendingApproval> {
        self.pending_approvals.values().cloned().collect()
    }

    /// How many approvals are currently parked.
    pub fn pending_count(&self) -> usize {
        self.pending_approvals.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{ConversationRole, NostrConversationTurn, PendingApproval};
    use chrono::{DateTime, Utc};

    fn ts(secs: i64) -> DateTime<Utc> {
        DateTime::<Utc>::from_timestamp(secs, 0).unwrap()
    }

    fn turn(role: ConversationRole, content: &str, secs: i64) -> NostrConversationTurn {
        NostrConversationTurn {
            id: Uuid::new_v4(),
            role,
            content: content.to_owned(),
            timestamp: ts(secs),
            metadata: None,
        }
    }

    #[test]
    fn add_turn_grows_conversation() {
        let mut actor = ConversationActor::new();
        let id = actor.new_conversation();

        actor.add_turn(id, turn(ConversationRole::User, "hello", 1));
        actor.add_turn(id, turn(ConversationRole::Assistant, "hi there", 2));

        let convo = actor.conversation(id).expect("convo exists");
        assert_eq!(convo.turns.len(), 2);
        assert_eq!(convo.turns[0].content, "hello");
        assert_eq!(convo.turns[1].content, "hi there");
        assert_eq!(convo.updated_at, ts(2));
    }

    #[test]
    fn add_turn_on_unknown_conversation_noops() {
        let mut actor = ConversationActor::new();
        let ghost = Uuid::new_v4();
        actor.add_turn(ghost, turn(ConversationRole::User, "x", 1));
        assert_eq!(actor.active_count(), 0);
        assert!(actor.conversation(ghost).is_none());
    }

    #[test]
    fn conversation_context_returns_last_three_of_ten() {
        let mut actor = ConversationActor::new();
        let id = actor.new_conversation();
        for i in 0..10 {
            actor.add_turn(
                id,
                turn(ConversationRole::User, &format!("turn {i}"), i + 1),
            );
        }
        let ctx = actor.conversation_context(id, 3);
        assert_eq!(ctx.len(), 3);
        assert_eq!(ctx[0].content, "turn 7");
        assert_eq!(ctx[1].content, "turn 8");
        assert_eq!(ctx[2].content, "turn 9");
    }

    #[test]
    fn conversation_context_handles_edges() {
        let mut actor = ConversationActor::new();
        let id = actor.new_conversation();

        // Empty conversation → empty context regardless of max_turns.
        assert!(actor.conversation_context(id, 5).is_empty());

        // max_turns=0 always empty.
        actor.add_turn(id, turn(ConversationRole::User, "x", 1));
        assert!(actor.conversation_context(id, 0).is_empty());

        // max_turns > len returns everything.
        let ctx = actor.conversation_context(id, 99);
        assert_eq!(ctx.len(), 1);

        // Unknown id returns empty.
        assert!(actor
            .conversation_context(Uuid::new_v4(), 3)
            .is_empty());
    }

    #[test]
    fn clear_conversation_drops_turns_keeps_row() {
        let mut actor = ConversationActor::new();
        let id = actor.new_conversation();
        actor.set_title(id, "Old chat");
        actor.add_turn(id, turn(ConversationRole::User, "x", 1));
        actor.clear_conversation(id);

        let c = actor.conversation(id).expect("row still present");
        assert!(c.turns.is_empty());
        assert!(c.title.is_none());
    }

    #[test]
    fn latest_conversation_id_tracks_most_recent_touch() {
        let mut actor = ConversationActor::new();
        let a = actor.new_conversation();
        let b = actor.new_conversation();
        assert_eq!(actor.latest_conversation_id(), Some(b));

        actor.add_turn(a, turn(ConversationRole::User, "x", 1));
        assert_eq!(actor.latest_conversation_id(), Some(a));
    }

    #[test]
    fn decide_approval_removes_from_pending() {
        let mut actor = ConversationActor::new();
        let convo = actor.new_conversation();
        let ap = PendingApproval::new(convo, "publish");
        let ap_id = ap.id;
        actor.add_approval(ap);
        assert_eq!(actor.pending_count(), 1);

        let result = actor.decide_approval(ap_id, ApprovalDecision::Approved);
        assert!(result.is_some());
        assert_eq!(result.unwrap().1, ApprovalDecision::Approved);
        assert_eq!(actor.pending_count(), 0);

        // Second decide is a no-op.
        assert!(actor
            .decide_approval(ap_id, ApprovalDecision::Approved)
            .is_none());
    }

    #[test]
    fn decide_approval_with_denial_carries_reason() {
        let mut actor = ConversationActor::new();
        let convo = actor.new_conversation();
        let ap = PendingApproval::new(convo, "publish");
        let ap_id = ap.id;
        actor.add_approval(ap);

        let decision = ApprovalDecision::Denied {
            reason: Some("not yet".into()),
        };
        let (taken, recorded) = actor
            .decide_approval(ap_id, decision.clone())
            .expect("decision");
        assert_eq!(taken.id, ap_id);
        assert_eq!(recorded, decision);
    }

    #[test]
    fn pending_approvals_listing_reflects_state() {
        let mut actor = ConversationActor::new();
        let convo = actor.new_conversation();
        let ap1 = PendingApproval::new(convo, "publish");
        let ap2 = PendingApproval::new(convo, "delete");
        actor.add_approval(ap1.clone());
        actor.add_approval(ap2.clone());
        assert_eq!(actor.pending_approvals().len(), 2);

        actor.decide_approval(ap1.id, ApprovalDecision::Approved);
        let remaining = actor.pending_approvals();
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].id, ap2.id);
    }
}
