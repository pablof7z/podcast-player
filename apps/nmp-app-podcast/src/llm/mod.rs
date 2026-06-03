//! Provider-blind LLM dispatch layer.
//!
//! Abstracts over multiple LLM providers (Ollama, OpenRouter) via a single
//! [`LlmBackend`] trait. Callers select a backend via [`backend_for`] based on
//! the model string and stored credential state, then invoke [`LlmBackend::complete`]
//! for a single async turn.

pub mod backend;
pub mod ollama_backend;
pub mod openrouter_backend;
pub mod factory;

pub use backend::{LlmBackend, LlmRequest, LlmError};
pub use factory::backend_for;
