//! Local on-device LLM backend implementation via host callback sink.
//!
//! This backend delegates to a local LiteRT-LM or similar on-device model
//! registered from the iOS side through the app-owned UniFFI facade. Rust calls
//! the sink with a JSON prompt and receives a JSON response back.

use async_trait::async_trait;
use std::sync::{Arc, Mutex, OnceLock};

use super::backend::{LlmBackend, LlmError, LlmRequest};

pub trait LocalLlmSink: Send + Sync {
    fn infer_local_llm(&self, prompt_json: String) -> String;
}

/// Global callback socket (OnceLock for init-once semantics).
static LOCAL_LLM: OnceLock<Mutex<Option<Arc<dyn LocalLlmSink>>>> = OnceLock::new();

/// Return the global local LLM registration slot.
pub(crate) fn slot() -> &'static Mutex<Option<Arc<dyn LocalLlmSink>>> {
    LOCAL_LLM.get_or_init(|| Mutex::new(None))
}

/// Register or clear the global local LLM sink.
pub(crate) fn set_registration(reg: Option<Arc<dyn LocalLlmSink>>) {
    if let Ok(mut slot_guard) = slot().lock() {
        *slot_guard = reg;
    }
}

/// Local on-device LLM backend.
///
/// Holds the model ID and delegates to the registered global callback when `complete` is called.
/// If the callback slot is empty (not registered), returns `Unavailable`.
pub struct LocalModelBackend {
    pub model_id: String,
}

#[async_trait]
impl LlmBackend for LocalModelBackend {
    async fn complete(&self, req: &LlmRequest) -> Result<String, LlmError> {
        // Build the prompt JSON exactly per spec:
        // {"system":..,"history":[[role,content],..],"user":..,"model":self.model_id}
        let prompt_json = serde_json::json!({
            "system": req.system,
            "history": req.history.iter().map(|(role, content)| {
                vec![serde_json::Value::String(role.clone()), serde_json::Value::String(content.clone())]
            }).collect::<Vec<_>>(),
            "user": req.user,
            "model": self.model_id,
        });

        let prompt_json_str = prompt_json.to_string();
        // Lock the slot only long enough to clone the sink. The sink may call
        // back into Swift and block while local inference runs.
        let sink = match slot().lock() {
            Ok(guard) => guard.clone(),
            Err(_) => {
                return Err(LlmError::Unavailable(
                    "Failed to acquire callback slot lock".into(),
                ))
            }
        };

        let sink = match sink {
            Some(r) => r,
            None => return Err(LlmError::Unavailable("Local model not loaded".into())),
        };

        let response_json = sink.infer_local_llm(prompt_json_str);

        // Parse the response JSON: {"text":..} or {"error":..}
        match serde_json::from_str::<serde_json::Value>(&response_json) {
            Ok(json) => {
                if let Some(text) = json.get("text").and_then(|v| v.as_str()) {
                    Ok(text.to_string())
                } else if let Some(error) = json.get("error").and_then(|v| v.as_str()) {
                    // Treat model errors as Unavailable (model-not-loaded is unavailable, not provider error).
                    Err(LlmError::Unavailable(error.to_string()))
                } else {
                    Err(LlmError::Unavailable(
                        "Local model response missing 'text' or 'error'".into(),
                    ))
                }
            }
            Err(_) => Err(LlmError::Unavailable(
                "Failed to parse local model response JSON".into(),
            )),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_local_backend_unavailable_when_not_registered() {
        let backend = LocalModelBackend {
            model_id: "test-model".to_string(),
        };

        let req = LlmRequest {
            system: "You are helpful.".to_string(),
            history: vec![],
            user: "Hello".to_string(),
            model: "unused".to_string(),
        };

        let result = backend.complete(&req).await;
        assert!(result.is_err());
        if let Err(LlmError::Unavailable(msg)) = result {
            assert!(msg.contains("Local model not loaded"));
        } else {
            panic!("Expected Unavailable error");
        }
    }
}
