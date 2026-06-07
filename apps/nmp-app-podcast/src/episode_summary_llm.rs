//! LLM-based episode summarization using rig-core + Ollama.
//!
//! [`summarize_episode`] produces a concise 2–3 sentence summary of a podcast
//! episode by prompting a local Ollama instance (default
//! `http://localhost:11434`) with the episode title, description, and — when one
//! has been fetched — the transcript. It mirrors [`crate::categorization_llm`]:
//! a synchronous call site supplies the shared Tokio runtime (wrapped in `Arc`)
//! and we `block_on` so a `spawn_blocking` worker can call it without being
//! async itself.
//!
//! ## Input budget
//!
//! When a transcript is present it is the richest source, so we prefer it and
//! cap it at [`MAX_BODY_CHARS`] to keep the prompt budget sane (mirrors the
//! 16k-char cap the deleted Swift `LiveEpisodeSummarizerAdapter` used). Without
//! a transcript we fall back to the publisher description.
//!
//! ## Failure handling
//!
//! If Ollama is offline or the response is empty the function returns
//! `Err(String)`. The caller ([`crate::episode_summary`]) logs the failure and
//! leaves the episode's `summary` untouched — unlike categorization there is no
//! cheap heuristic fallback to stamp, and stamping the raw description as a
//! "summary" would poison the persisted field. The iOS agent tool degrades to
//! the publisher description on its side instead.

use std::sync::{Arc, Mutex};

use tokio::runtime::Runtime;

use crate::llm::{LlmRequest, backend_for, role_model_or_default, validate_model_credentials};
use crate::store::PodcastStore;

const SUMMARIZE_MODEL: &str = "deepseek-v4-flash:cloud";

/// Upper bound on the episode body fed to the model. Mirrors the 16k cap the
/// deleted Swift adapter applied to transcript / show-note text.
const MAX_BODY_CHARS: usize = 16_000;

const SUMMARIZE_PREAMBLE: &str = "Summarize this podcast episode in 2-3 sentences. Be concise and factual. \
     Do not invent facts not present in the supplied content. Output only the \
     summary text, with no preamble, labels, or markdown.";

/// Summarize an episode using the LLM.
///
/// Prefers `transcript` (capped at [`MAX_BODY_CHARS`]) when present, otherwise
/// summarizes from `title` + `description`. Returns `Err` when the LLM is
/// unreachable or the response is empty.
pub fn summarize_episode(
    title: &str,
    description: &str,
    transcript: Option<&str>,
    runtime: &Arc<Runtime>,
    store: &Arc<Mutex<PodcastStore>>,
) -> Result<String, String> {
    let prompt = build_prompt(title, description, transcript);
    runtime.block_on(async {
        // Episode summaries are prose synthesis, so they share the visible
        // Wiki model setting instead of hiding another model choice.
        let summary_cfg = store
            .lock()
            .ok()
            .map(|s| s.wiki_model().to_owned())
            .unwrap_or_default();
        let summary_model = role_model_or_default(&summary_cfg, SUMMARIZE_MODEL);
        validate_model_credentials(store, &summary_model).map_err(|e| e.to_string())?;
        let backend = backend_for(store, &summary_model);
        let req = LlmRequest {
            system: SUMMARIZE_PREAMBLE.to_owned(),
            history: Vec::new(),
            user: prompt,
            model: summary_model,
        };

        let response: String = backend.complete(&req).await?;

        clean_summary(&response)
    })
}

/// Assemble the user prompt from the available episode text.
///
/// Transcript wins when present (richest signal); otherwise we fall back to the
/// description. The body is truncated to [`MAX_BODY_CHARS`] on a char boundary.
/// Split out from the network call so it is unit-testable without a live
/// Ollama.
fn build_prompt(title: &str, description: &str, transcript: Option<&str>) -> String {
    let body_source = match transcript {
        Some(t) if !t.trim().is_empty() => t,
        _ => description,
    };
    let body: String = body_source.chars().take(MAX_BODY_CHARS).collect();
    format!("Episode title: {title}\n\nEpisode content (transcript or show notes):\n{body}")
}

/// Normalize an LLM summary reply: trim surrounding whitespace and reject an
/// empty result. Kept separate so the trimming/validation is unit-testable.
fn clean_summary(response: &str) -> Result<String, String> {
    let trimmed = response.trim();
    if trimmed.is_empty() {
        return Err("empty summary from LLM".into());
    }
    Ok(trimmed.to_owned())
}

#[cfg(test)]
#[path = "episode_summary_llm_tests.rs"]
mod tests;
