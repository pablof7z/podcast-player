//! Ollama LLM backend implementation.

use async_trait::async_trait;
use serde::{Deserialize, Serialize};

use super::backend::{LlmBackend, LlmError, LlmRequest};

const REQUEST_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(45);
const JOIN_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(50);

/// Ollama LLM backend.
pub struct OllamaBackend {
    pub base_url: String,
    pub api_key: Option<String>,
}

fn ollama_model_id(model: &str) -> &str {
    model.strip_prefix("ollama:").unwrap_or(model)
}

fn ollama_chat_url(base_url: &str) -> String {
    let trimmed = base_url.trim().trim_end_matches('/');
    let url = if trimmed.is_empty() {
        "http://127.0.0.1:11434/api/chat".to_owned()
    } else if trimmed.ends_with("/api/chat") {
        trimmed.to_owned()
    } else {
        format!("{trimmed}/api/chat")
    };
    if let Some(rest) = url.strip_prefix("http://localhost:") {
        format!("http://127.0.0.1:{rest}")
    } else {
        url
    }
}

fn ollama_messages(req: &LlmRequest) -> Vec<OllamaMessage> {
    let mut messages = Vec::with_capacity(req.history.len() + 2);
    messages.push(OllamaMessage {
        role: "system".to_owned(),
        content: req.system.clone(),
    });
    messages.extend(req.history.iter().map(|(role, content)| OllamaMessage {
        role: if role == "user" {
            "user".to_owned()
        } else {
            "assistant".to_owned()
        },
        content: content.clone(),
    }));
    messages.push(OllamaMessage {
        role: "user".to_owned(),
        content: req.user.clone(),
    });
    messages
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct OllamaMessage {
    role: String,
    content: String,
}

#[derive(Debug, Serialize)]
struct OllamaChatRequest {
    model: String,
    messages: Vec<OllamaMessage>,
    stream: bool,
    think: bool,
}

#[derive(Debug, Deserialize)]
struct OllamaChatResponse {
    message: Option<OllamaMessage>,
    error: Option<String>,
}

/// Convert stored `(role, content)` pairs into Ollama chat messages.
#[cfg(test)]
fn make_history(pairs: &[(String, String)]) -> Vec<OllamaMessage> {
    pairs
        .iter()
        .map(|(role, content)| {
            if role == "user" {
                OllamaMessage {
                    role: "user".to_owned(),
                    content: content.clone(),
                }
            } else {
                OllamaMessage {
                    role: "assistant".to_owned(),
                    content: content.clone(),
                }
            }
        })
        .collect()
}

#[async_trait]
impl LlmBackend for OllamaBackend {
    async fn complete(&self, req: &LlmRequest) -> Result<String, LlmError> {
        let body = OllamaChatRequest {
            model: ollama_model_id(&req.model).to_owned(),
            messages: ollama_messages(req),
            stream: false,
            think: false,
        };
        let chat_url = ollama_chat_url(&self.base_url);
        let api_key = self.api_key.clone();
        let task = tokio::task::spawn_blocking(move || complete_blocking(chat_url, api_key, body));

        match tokio::time::timeout(JOIN_TIMEOUT, task).await {
            Ok(Ok(result)) => result,
            Ok(Err(e)) => Err(LlmError::Unavailable(e.to_string())),
            Err(_) => Err(LlmError::Unavailable(format!(
                "request exceeded {}s budget",
                JOIN_TIMEOUT.as_secs()
            ))),
        }
    }
}

fn complete_blocking(
    chat_url: String,
    api_key: Option<String>,
    body: OllamaChatRequest,
) -> Result<String, LlmError> {
    let client = reqwest::blocking::Client::builder()
        .timeout(REQUEST_TIMEOUT)
        .build()
        .map_err(|e| LlmError::Unavailable(e.to_string()))?;
    let mut request = client.post(chat_url).json(&body);
    if let Some(api_key) = api_key.as_deref().filter(|key| !key.is_empty()) {
        request = request.bearer_auth(api_key);
    }

    let response = request
        .send()
        .map_err(|e| LlmError::Unavailable(e.to_string()))?;
    let status = response.status();
    let text = response
        .text()
        .map_err(|e| LlmError::Unavailable(e.to_string()))?;
    if !status.is_success() {
        return Err(LlmError::Provider(text));
    }
    let response: OllamaChatResponse =
        serde_json::from_str(&text).map_err(|e| LlmError::Provider(e.to_string()))?;
    if let Some(error) = response.error {
        return Err(LlmError::Provider(error));
    }
    response
        .message
        .map(|message| message.content)
        .filter(|content| !content.trim().is_empty())
        .ok_or_else(|| LlmError::Provider("Ollama response missing content".to_owned()))
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
        assert_eq!(history[0].role, "user");
        assert_eq!(history[1].role, "assistant");
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

    #[test]
    fn test_ollama_chat_url_appends_api_chat() {
        assert_eq!(
            ollama_chat_url("http://localhost:11434"),
            "http://127.0.0.1:11434/api/chat"
        );
        assert_eq!(
            ollama_chat_url("http://localhost:11434/api/chat"),
            "http://127.0.0.1:11434/api/chat"
        );
    }

    #[tokio::test]
    #[ignore]
    async fn live_glm_cloud_completes_with_tool_prompt() {
        let backend = OllamaBackend {
            base_url: "http://localhost:11434".to_owned(),
            api_key: None,
        };
        let req = LlmRequest {
            system: format!(
                "{}\n\n{}",
                crate::agent_llm::AGENT_SYSTEM_PROMPT,
                crate::agent_tools::TOOL_INSTRUCTIONS
            ),
            history: Vec::new(),
            user: "In one short sentence, confirm this live TUI agent model call succeeded using GLM 5.1 cloud.".to_owned(),
            model: "ollama:glm-5.1:cloud".to_owned(),
        };

        let result = backend.complete(&req).await.expect("live Ollama call");
        eprintln!("{result}");
        assert!(result.to_lowercase().contains("succeeded"));
    }
}
