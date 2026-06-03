//! Trait definition and types for the provider-blind LLM backend.

use async_trait::async_trait;

/// A provider-agnostic single-turn completion request.
/// `history` is prior (role, content) pairs ("user"/"assistant"); the
/// new `user` turn is NOT included in `history`.
#[derive(Debug, Clone)]
pub struct LlmRequest {
    pub system: String,
    pub history: Vec<(String, String)>,
    pub user: String,
    pub model: String,
}

/// Typed failure. Keeps the transport-unreachable distinction that
/// ai_chapters.rs relies on (do NOT collapse to a flat string).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LlmError {
    /// Endpoint unreachable, client build failed, or request timed out —
    /// the model is definitively absent. Maps to SynthError::Unavailable.
    Unavailable(String),
    /// The provider answered with an error status / refused the request.
    Provider(String),
    /// No usable credential resolved for the selected provider.
    MissingCredential(String),
}

impl std::fmt::Display for LlmError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LlmError::Unavailable(msg) => write!(f, "LLM unavailable: {}", msg),
            LlmError::Provider(msg) => write!(f, "LLM provider error: {}", msg),
            LlmError::MissingCredential(msg) => write!(f, "Missing credential: {}", msg),
        }
    }
}

impl LlmError {
    pub fn is_unavailable(&self) -> bool {
        matches!(self, LlmError::Unavailable(_))
    }
}

impl From<LlmError> for String {
    fn from(err: LlmError) -> Self {
        err.to_string()
    }
}

/// One async completion primitive. Every blocking caller wraps a call to
/// `complete` in its own `runtime.block_on(...)`. Object-safe via async-trait
/// so the factory can return `Box<dyn LlmBackend>`.
#[async_trait]
pub trait LlmBackend: Send + Sync {
    async fn complete(&self, req: &LlmRequest) -> Result<String, LlmError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Fake LLM backend returning a canned string. Proves object-safety and
    /// `Box<dyn LlmBackend>` works.
    struct FakeLlmBackend;

    #[async_trait]
    impl LlmBackend for FakeLlmBackend {
        async fn complete(&self, _req: &LlmRequest) -> Result<String, LlmError> {
            Ok("Fake response".to_string())
        }
    }

    #[tokio::test]
    async fn test_object_safety() {
        let backend: Box<dyn LlmBackend> = Box::new(FakeLlmBackend);
        let req = LlmRequest {
            system: "You are a helpful assistant.".to_string(),
            history: vec![],
            user: "Hello".to_string(),
            model: "test".to_string(),
        };
        let result = backend.complete(&req).await;
        assert_eq!(result.unwrap(), "Fake response");
    }

    #[test]
    fn test_llm_error_display() {
        let unavailable = LlmError::Unavailable("connection refused".to_string());
        assert!(unavailable.to_string().contains("unavailable"));

        let provider = LlmError::Provider("invalid request".to_string());
        assert!(provider.to_string().contains("provider error"));

        let missing = LlmError::MissingCredential("api key".to_string());
        assert!(missing.to_string().contains("Missing credential"));
    }

    #[test]
    fn test_is_unavailable() {
        assert!(LlmError::Unavailable("down".to_string()).is_unavailable());
        assert!(!LlmError::Provider("error".to_string()).is_unavailable());
        assert!(!LlmError::MissingCredential("key".to_string()).is_unavailable());
    }
}
