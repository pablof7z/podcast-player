//! Tests for `provider_transport` — split out to keep the parent file under
//! the 500-line hard limit (AGENTS.md). Uses `super::*` for the shared
//! types/functions defined there.

use super::*;
use crate::llm::backend::test_support::{lock_env_test, EnvVarGuard};

#[tokio::test]
async fn complete_returns_mock_without_network_when_env_set() {
    let _lock = lock_env_test();
    let _guard = EnvVarGuard::set("PODCAST_MOCK_LLM", "1");
    // No OLLAMA_API_KEY loaded and the base URL defaults to Ollama
    // Cloud — this would normally fail credential validation before
    // ever reaching the network. The mock short-circuits before that
    // check even runs.
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let intent = CompletionIntent {
        provider: ProviderKind::Ollama,
        model: "gpt-oss:120b-cloud".to_owned(),
        system: "sys".to_owned(),
        user: "usr".to_owned(),
        response_format: ResponseFormat::Text,
    };

    let result = complete(store, intent).await.unwrap();
    assert_eq!(result.provider, "mock");
    assert!(result.text.contains("Mock LLM response"));
}

#[tokio::test]
async fn embed_returns_deterministic_mock_vectors_without_network_when_env_set() {
    let _lock = lock_env_test();
    let _guard = EnvVarGuard::set("PODCAST_MOCK_LLM", "1");
    let store = Arc::new(Mutex::new(PodcastStore::new()));

    let make_intent = || EmbeddingIntent {
        provider: ProviderKind::Ollama,
        model: "embed-model".to_owned(),
        input: vec!["hello".to_owned(), "world".to_owned()],
        dimensions: Some(8),
    };

    let first = embed(Arc::clone(&store), make_intent()).await.unwrap();
    assert_eq!(first.provider, "mock");
    assert_eq!(first.embeddings.len(), 2);
    assert!(first.embeddings.iter().all(|v| v.len() == 8));

    // Same input text -> same vectors, every time, with no network call.
    let second = embed(store, make_intent()).await.unwrap();
    assert_eq!(first.embeddings, second.embeddings);
}

#[test]
fn completion_intent_decodes_json_format() {
    let intent: CompletionIntent = serde_json::from_value(json!({
        "provider": "openrouter",
        "model": "openai/gpt-4o-mini",
        "system": "sys",
        "user": "usr",
        "response_format": "json_object"
    }))
    .unwrap();
    assert_eq!(intent.provider, ProviderKind::OpenRouter);
    assert_eq!(intent.response_format, ResponseFormat::JsonObject);
}
