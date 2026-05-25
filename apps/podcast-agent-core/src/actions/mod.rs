//! Action payloads + stable string ids for podcast-agent intents.

pub mod agent;

pub use agent::{
    ApproveAction, ClearConversationAction, DenyAction, SendAgentMessageAction,
    ACTION_AGENT_APPROVE, ACTION_AGENT_CLEAR, ACTION_AGENT_DENY, ACTION_AGENT_SEND,
};
