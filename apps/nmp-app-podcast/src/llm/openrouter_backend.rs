//! OpenRouter LLM backend implementation.

use async_trait::async_trait;
use rig_core::client::CompletionClient;
use rig_core::completion::{Chat, Message};
use rig_core::providers::openrouter;

use super::backend::{LlmBackend, LlmError, LlmRequest};

/// OpenRouter LLM backend.
pub struct OpenRouterBackend {
    pub base_url: String,
    pub api_key: String,
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
impl LlmBackend for OpenRouterBackend {
    async fn complete(&self, req: &LlmRequest) -> Result<String, LlmError> {
        // Check for missing credential upfront.
        if self.api_key.is_empty() {
            return Err(LlmError::MissingCredential(
                "OpenRouter API key is empty".to_string(),
            ));
        }

        // Build the OpenRouter client.
        let client = openrouter::Client::builder()
            .api_key(&self.api_key)
            .base_url(&self.base_url)
            .build()
            .map_err(|e| {
                // Build failure may be due to missing/invalid credential.
                if e.to_string().contains("api_key") {
                    LlmError::MissingCredential(e.to_string())
                } else {
                    LlmError::Unavailable(e.to_string())
                }
            })?;

        // Build the agent with the system prompt.
        let agent = client.agent(&req.model).preamble(&req.system).build();

        // Convert history and chat.
        let mut history = make_history(&req.history);
        let result = agent.chat(req.user.as_str(), &mut history).await;
        result.map_err(|e| {
            let err_str = e.to_string();
            // Check if it's a provider refusal (non-2xx status or explicit refusal).
            if err_str.contains("400")
                || err_str.contains("401")
                || err_str.contains("403")
                || err_str.contains("429")
                || err_str.contains("500")
            {
                LlmError::Provider(err_str)
            } else {
                // Generic transport failure.
                LlmError::Unavailable(err_str)
            }
        })
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
}
