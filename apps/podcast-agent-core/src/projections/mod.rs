//! Read- and write-side projections over the agent domain.
//!
//! [`ConversationActor`] is the canonical state owner; [`approvals`]
//! ships a side-helper for sorting + expiry filtering.

pub mod approvals;
pub mod conversations;

pub use approvals::sorted_active_approvals;
pub use conversations::ConversationActor;
