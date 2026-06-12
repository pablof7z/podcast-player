//! LLM-based episode categorization using rig-core + Ollama (M5.6).
//!
//! [`categorize_episode`] assigns 1–3 category tags to an episode by
//! prompting a local Ollama instance (default: `http://localhost:11434`)
//! and parsing the JSON-array reply against a fixed 15-item taxonomy.
//!
//! The function is synchronous at the call site — the caller supplies the
//! shared Tokio runtime (wrapped in `Arc`) and we use `block_on` so a
//! `spawn_blocking` worker can call it without being async itself. This
//! mirrors `inbox_llm` and `picks_llm`.
//!
//! ## Taxonomy enforcement
//!
//! The model is *told* to pick from the fixed list, but we never trust the
//! prompt: [`filter_taxonomy`] drops any off-list label, dedups, and caps
//! the result at [`MAX_CATEGORIES_PER_EPISODE`]. If nothing survives the
//! filter the function returns `Err` so the caller falls back to keyword
//! matching.
//!
//! ## Failure handling
//!
//! If Ollama is offline, the response is unparseable, or the filtered
//! result is empty, the function returns `Err(String)`. The caller
//! ([`crate::categorization`]) is expected to keep the keyword-matched tags
//! it already wrote and log the failure without surfacing it to the user.
//!
//! ## Cache-wipe note
//!
//! Categorization uses a single shared `categories` cache (unlike inbox's
//! two-tier projection). Each feed refresh's synchronous keyword pass
//! replaces the cache wholesale, transiently dropping the prior pass's
//! LLM-derived tags until the background pass below re-stamps them. With
//! the re-entrancy guard on the spawn this self-heals on the next refresh;
//! a two-tier projection would be over-engineering for the current scope.

use std::sync::{Arc, Mutex};

use tokio::runtime::Runtime;

use crate::ffi::actions::categorization_module::MAX_CATEGORIES_PER_EPISODE;
use crate::llm::complete_for_role;
use crate::store::PodcastStore;

const CATEGORIZE_MODEL: &str = "deepseek-v4-flash:cloud";

/// The fixed category taxonomy. The LLM is constrained to this list in the
/// system prompt, and its output is filtered against it (exact, title-case).
pub const TAXONOMY: &[&str] = &[
    "Technology",
    "Business",
    "Science",
    "Health",
    "Politics",
    "Culture",
    "Sports",
    "Education",
    "Entertainment",
    "History",
    "Philosophy",
    "True Crime",
    "Comedy",
    "Finance",
    "Spirituality",
];

const CATEGORIZE_PREAMBLE: &str = "You are a podcast episode categorizer. Given an episode title and description, output 1-3 category tags from this list: [Technology, Business, Science, Health, Politics, Culture, Sports, Education, Entertainment, History, Philosophy, True Crime, Comedy, Finance, Spirituality]. Output ONLY a JSON array of strings: [\"Category1\", \"Category2\"]. No other text.";

/// Score an episode's categories using the LLM.
///
/// Returns 1–3 taxonomy-valid tags, or `Err` if the LLM is unreachable, the
/// response is unparseable, or no in-taxonomy tags survive filtering.
pub fn categorize_episode(
    episode_title: &str,
    description: &str,
    runtime: &Arc<Runtime>,
    store: &Arc<Mutex<PodcastStore>>,
) -> Result<Vec<String>, String> {
    runtime.block_on(async {
        let truncated: String = description.chars().take(500).collect();
        let prompt = format!("Title: {episode_title}\nDescription: {truncated}");

        // Honor explicit provider-prefixed selections for the Categorization
        // role; otherwise keep the historical cloud categorize model.
        let cat_cfg = store
            .lock()
            .ok()
            .map(|s| s.categorization_model().to_owned())
            .unwrap_or_default();
        let response =
            complete_for_role(store, &cat_cfg, CATEGORIZE_MODEL, CATEGORIZE_PREAMBLE, &prompt)
                .await?;

        parse_category_array(&response)
    })
}

/// Parse an LLM response into a filtered, taxonomy-valid category list.
///
/// Extracts the first balanced `[…]` JSON array, parses it as
/// `Vec<String>`, then runs [`filter_taxonomy`]. Returns `Err` if no array
/// is present, the array doesn't parse, or nothing survives filtering.
///
/// Split out from the network call so the parsing logic is unit-testable
/// without a live Ollama.
pub fn parse_category_array(response: &str) -> Result<Vec<String>, String> {
    let json_str = extract_json_array(response)?;
    let raw: Vec<String> = serde_json::from_str(&json_str).map_err(|e| e.to_string())?;
    let filtered = filter_taxonomy(raw);
    if filtered.is_empty() {
        return Err("no in-taxonomy categories in LLM response".into());
    }
    Ok(filtered)
}

/// Filter a list of candidate labels to the fixed taxonomy.
///
/// Keeps only exact (title-case) taxonomy matches, dedups while preserving
/// first-seen order, and caps the result at [`MAX_CATEGORIES_PER_EPISODE`].
fn filter_taxonomy(candidates: Vec<String>) -> Vec<String> {
    let mut out: Vec<String> = Vec::with_capacity(MAX_CATEGORIES_PER_EPISODE);
    for label in candidates {
        let trimmed = label.trim();
        if TAXONOMY.contains(&trimmed) && !out.iter().any(|x| x == trimmed) {
            out.push(trimmed.to_owned());
            if out.len() == MAX_CATEGORIES_PER_EPISODE {
                break;
            }
        }
    }
    out
}

/// Extract the first balanced `[…]` JSON array from an arbitrary string.
///
/// Thin wrapper over [`crate::llm::extract_json_array`] that re-maps the
/// shared `Option` seam onto this module's historical `Result<String, String>`
/// error strings (which the parse tests assert on). The find-first-to-last
/// scan itself now lives once in the `llm` module.
fn extract_json_array(s: &str) -> Result<String, String> {
    if !s.contains('[') {
        return Err("no JSON array found in LLM response".into());
    }
    if !s.contains(']') {
        return Err("no closing bracket in LLM response".into());
    }
    crate::llm::extract_json_array(s)
        .map(str::to_owned)
        .ok_or_else(|| "malformed JSON: closing bracket before opening bracket".into())
}

#[cfg(test)]
#[path = "categorization_llm_tests.rs"]
mod tests;
