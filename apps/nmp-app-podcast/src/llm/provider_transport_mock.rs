//! `PODCAST_MOCK_LLM=1` canned results for [`super::complete`]/[`super::embed`].
//!
//! Split out of `provider_transport.rs` to keep the parent file under the
//! 500-line hard limit (AGENTS.md). Uses `super::*` for the shared
//! request/result types defined there.

use super::*;

/// Canned, network-free completion result for `PODCAST_MOCK_LLM=1`.
pub(super) fn mock_completion_result(intent: &CompletionIntent) -> CompletionResult {
    let text = if intent.response_format == ResponseFormat::JsonObject {
        r#"{"mock": true, "text": "Mock LLM response (PODCAST_MOCK_LLM is set)."}"#.to_owned()
    } else {
        "Mock LLM response (PODCAST_MOCK_LLM is set — no real backend was called).".to_owned()
    };
    CompletionResult {
        text,
        provider: "mock",
        model: intent.model.clone(),
        latency_ms: 0,
        usage: None,
        prompt_tokens: 0,
        completion_tokens: 0,
    }
}

/// Canned, network-free embedding result for `PODCAST_MOCK_LLM=1`. Vectors are
/// deterministic per input text (not semantically meaningful) so callers that
/// assert on shape/determinism still get consistent behavior across runs.
pub(super) fn mock_embedding_result(intent: &EmbeddingIntent) -> EmbeddingResult {
    let dim = intent.dimensions.unwrap_or(1024);
    let embeddings = intent
        .input
        .iter()
        .map(|text| deterministic_mock_embedding(text, dim))
        .collect();
    EmbeddingResult {
        embeddings,
        provider: "mock",
        model: intent.model.clone(),
        latency_ms: 0,
        usage: None,
        prompt_tokens: 0,
    }
}

/// A deterministic pseudo-embedding derived from a simple xorshift PRNG seeded
/// by `text`'s hash. Same input always yields the same vector, with no network
/// call and no real embedding model — only shape/determinism are load-bearing
/// for the mock, never the vector's semantic content.
fn deterministic_mock_embedding(text: &str, dim: usize) -> Vec<f32> {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut seed = {
        let mut hasher = DefaultHasher::new();
        text.hash(&mut hasher);
        hasher.finish()
    };
    if seed == 0 {
        seed = 0x9E3779B97F4A7C15; // xorshift needs a non-zero seed.
    }
    (0..dim)
        .map(|_| {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            ((seed % 2000) as f32 / 1000.0) - 1.0
        })
        .collect()
}
