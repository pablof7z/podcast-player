//! Domain types for the podcast agent — conversations, approvals, tasks,
//! and long-lived memory. No I/O, no async; pure data + small helpers.

pub mod agent_task;
pub mod approval;
pub mod conversation;
pub mod memory;

pub use agent_task::{AgentTask, TaskKind, TaskStatus};
pub use approval::{ApprovalDecision, PendingApproval};
pub use conversation::{ConversationRole, NostrConversation, NostrConversationTurn, TurnMetadata};
pub use memory::{AgentMemory, MemoryKind};
