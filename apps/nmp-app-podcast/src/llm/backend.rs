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

/// Env var that opts every LLM call site out of the real network backends.
/// Set `PODCAST_MOCK_LLM=1` (or `true`) to keep local dev/test runs off the
/// owner's Ollama server (and OpenRouter) entirely — `factory::backend_for`
/// checks this before selecting Local/Ollama/OpenRouter, and
/// `provider_transport::{complete, embed}` (the separate FFI-facing shell
/// dispatch path that does not go through [`LlmBackend`] at all) check it too.
pub fn mock_llm_enabled() -> bool {
    std::env::var("PODCAST_MOCK_LLM")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
}

/// Deterministic, network-free stand-in for a real LLM backend. Selected by
/// [`super::factory::backend_for`] whenever [`mock_llm_enabled`] is true.
///
/// Every `*_llm.rs` caller shares this one backend, so `complete` sniffs
/// `req.system` for the caller's known preamble text and returns a canned
/// reply shaped for that caller's parser (chapters JSON, picks JSON,
/// categorization JSON, …). Anything unrecognized (agent chat, wiki, …) gets
/// a canned plain-text reply, which every caller already treats as a valid
/// non-tool-call final answer.
pub struct MockLlmBackend;

#[async_trait]
impl LlmBackend for MockLlmBackend {
    async fn complete(&self, req: &LlmRequest) -> Result<String, LlmError> {
        Ok(mock_response_for(&req.system).to_owned())
    }
}

/// Pick the canned reply shape for a caller's system preamble. Order matters:
/// the FULL/ENRICH chapter-compile preambles and the chapters-only preamble
/// all mention "chapter", so the more specific substrings are checked first.
fn mock_response_for(system: &str) -> &'static str {
    if system.contains("podcast episode categorizer") {
        r#"["Technology"]"#
    } else if system.contains("podcast picks recommender") {
        r#"{"score": 0.75, "reason": "Mock LLM: matches your listening profile."}"#
    } else if system.contains("chapter boundaries, chapter summaries") {
        // FULL compile mode — parse_full requires >= 4 valid chapters.
        r#"{"chapters":[{"start":0,"title":"Mock Introduction","summary":"Mock intro summary."},{"start":120,"title":"Mock Segment Two","summary":"Mock summary two."},{"start":300,"title":"Mock Segment Three","summary":"Mock summary three."},{"start":480,"title":"Mock Closing","summary":"Mock closing summary."}],"ads":[]}"#
    } else if system.contains("already has chapter boundaries") {
        r#"{"summaries":[{"index":0,"summary":"Mock chapter summary."}],"ads":[]}"#
    } else if system.contains("\"start_secs\"") {
        // Chapters-only mode (Grounded or Simple prompt style).
        r#"[{"title":"Mock Introduction","start_secs":0.0},{"title":"Mock Main Discussion","start_secs":120.0},{"title":"Mock Closing Thoughts","start_secs":300.0}]"#
    } else if system.contains("Summarize this podcast episode") {
        "This is a mock episode summary generated without contacting Ollama."
    } else {
        "Mock LLM response (PODCAST_MOCK_LLM is set — no real backend was called)."
    }
}

/// Shared test-only support for exercising the `PODCAST_MOCK_LLM` switch.
///
/// `factory`, `provider_transport`, and `image_generation` each have their own
/// tests that flip this env var. Env vars are process-global, so any two such
/// tests racing on the same key — even across different test *files* in the
/// same test binary — will flake unless every one of them serializes through
/// the same lock. Route all of them through [`lock_env_test`] /
/// [`EnvVarGuard`] rather than defining a local copy per file.
#[cfg(test)]
pub(crate) mod test_support {
    use std::sync::{Mutex, MutexGuard};

    static ENV_TEST_LOCK: Mutex<()> = Mutex::new(());

    /// Must be held for the entire time an [`EnvVarGuard`] in any test file
    /// is alive.
    pub(crate) fn lock_env_test() -> MutexGuard<'static, ()> {
        ENV_TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// RAII guard that sets `key=value` for its lifetime and restores
    /// whatever was there before on drop (including panics). Callers must
    /// hold [`lock_env_test`] for as long as this guard is alive.
    pub(crate) struct EnvVarGuard {
        key: &'static str,
        previous: Option<String>,
    }

    impl EnvVarGuard {
        pub(crate) fn set(key: &'static str, value: &str) -> Self {
            let previous = std::env::var(key).ok();
            std::env::set_var(key, value);
            Self { key, previous }
        }
    }

    impl Drop for EnvVarGuard {
        fn drop(&mut self) {
            match &self.previous {
                Some(v) => std::env::set_var(self.key, v),
                None => std::env::remove_var(self.key),
            }
        }
    }
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
