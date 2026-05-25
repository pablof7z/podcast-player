//! `podcast-agent-core` — agent-chat domain layer.
//!
//! Types, actions, and a pure-data conversation state machine for the
//! podcast agent. This is the M7.A skeleton: the agent loop, tool
//! dispatcher, scheduled-task runner, and LLM provider wiring all land
//! in subsequent M7 milestones (B–G).
//!
//! ## Scope
//!
//! * Domain: [`NostrConversation`], [`PendingApproval`], [`AgentTask`],
//!   [`AgentMemory`] — port of the legacy Swift `Domain/Agent*` files
//!   into Rust, retagged for the LLM-chat model. Peer-Nostr types belong
//!   to the future `podcast-peer` crate.
//! * Actions: [`SendAgentMessageAction`], [`ApproveAction`],
//!   [`DenyAction`], [`ClearConversationAction`] plus their stable
//!   `podcast.agent.*` ids.
//! * Projection: [`ConversationActor`] — synchronous state machine that
//!   the kernel-side `ActionModule` impls will call into in M7.B.
//!
//! ## Doctrine
//!
//! * **Pure** — no async, no I/O, no kernel deps. Tests drive the actor
//!   deterministically.
//! * **D6 alignment** — every type is `Serialize` + `Deserialize`; the
//!   snapshot serializer in `nmp-app-podcast` re-exports the wire shapes.
//! * **300 LOC soft / 500 LOC hard** per file (matches AGENTS.md).

pub mod actions;
pub mod projections;
pub mod types;

pub use actions::{
    ApproveAction, ClearConversationAction, DenyAction, SendAgentMessageAction,
    ACTION_AGENT_APPROVE, ACTION_AGENT_CLEAR, ACTION_AGENT_DENY, ACTION_AGENT_SEND,
};
pub use projections::{sorted_active_approvals, ConversationActor};
pub use types::{
    AgentMemory, AgentTask, ApprovalDecision, ConversationRole, MemoryKind, NostrConversation,
    NostrConversationTurn, PendingApproval, TaskKind, TaskStatus, TurnMetadata,
};
