//! Ollama LLM backend implementation.

use async_trait::async_trait;
use rig_core::client::CompletionClient;
use rig_core::completion::{Chat, Message};
use rig_core::providers::ollama;

use super::backend::{LlmBackend, LlmError, LlmRequest};

/// Ollama LLM backend.
pub struct OllamaBackend {
    pub base_url: String,
    pub api_key: Option<String>,
}

fn ollama_model_id(model: &str) -> &str {
    model.strip_prefix("ollama:").unwrap_or(model)
}

/// Convert stored `(role, content)` pairs into rig-core chat history.
/// The `Chat` trait prepends the new user turn itself — we only pass prior turns.
fn make_history(pairs: &[(String, String)]) -> Vec<Message> {
    pairs
        .iter()
        .map(|(role, content)| {
            if role == "user" {
                Message::user(content.as_str())
            } else {
                Message::assistant(content.as_str())
            }
        })
        .collect()
}

#[async_trait]
impl LlmBackend for OllamaBackend {
    async fn complete(&self, req: &LlmRequest) -> Result<String, LlmError> {
        // Build the Ollama client. If no API key is provided, use empty string.
        let api_key = self.api_key.as_deref().unwrap_or("");
        let client = ollama::Client::builder()
            .base_url(&self.base_url)
            .api_key(api_key)
            .build()
            .map_err(|e| LlmError::Unavailable(e.to_string()))?;

        // Build the agent with the system prompt.
        let agent = client
            .agent(ollama_model_id(&req.model))
            .preamble(&req.system)
            .build();

        // Convert history and chat.
        let mut history = make_history(&req.history);
        let result = agent.chat(req.user.as_str(), &mut history).await;
        result.map_err(|e| LlmError::Unavailable(e.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_make_history() {
        let pairs = vec![
            ("user".to_string(), "Hello".to_string()),
            ("assistant".to_string(), "Hi there".to_string()),
        ];
        let history = make_history(&pairs);
        assert_eq!(history.len(), 2);
    }

    #[test]
    fn test_ollama_model_id_strips_provider_prefix() {
        assert_eq!(
            ollama_model_id("ollama:gpt-oss:120b-cloud"),
            "gpt-oss:120b-cloud"
        );
        assert_eq!(
            ollama_model_id("deepseek-v4-pro:cloud"),
            "deepseek-v4-pro:cloud"
        );
    }
}
