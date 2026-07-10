//! Compound categorization ActionModule — routes all `"podcast.categorize.*"`
//! dispatches.
//!
//! The categorizer is intentionally *heuristic* for now: each episode's
//! `title + description` is tokenized and matched against keyword sets per
//! category (Technology, Science, Business, etc.). An episode picks up at
//! most three category labels, in priority order of keyword-match count.
//! Real LLM-driven classification is a follow-up; this module exists so
//! the UI has a stable contract + a stable on-snapshot projection to
//! render against today.
//!
//! Per D7 the iOS side only **dispatches** the request; the kernel decides
//! which categories exist, which keywords map to which category, and how
//! many labels to assign. Swift never names a category string of its own.
//!
//! ## Wire shape
//!
//! ```text
//! podcast.categorize.run                 — RunCategorization
//! podcast.categorize.categorize_episode  — CategorizeEpisode { episode_id }
//! ```
//!
//! `run` re-categorizes the whole library (called automatically at the
//! end of every successful feed refresh — see [`crate::host_op_handler`]).
//! `categorize_episode` rescans a single episode (useful when the iOS
//! shell wants to refresh one row without rebuilding the projection).

use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;

use serde::{Deserialize, Serialize};

use nmp_core::substrate::ActionModule;
use nmp_core::actor::ActorCommand;

pub use super::categorization_keywords::CATEGORY_KEYWORDS;

/// Wire enum for all `"podcast.categorize"` namespace actions.
///
/// `#[serde(tag = "op", rename_all = "snake_case")]` maps the JSON
/// discriminator to the lowercase snake-case variant name:
/// `run` → `{"op":"run"}`,
/// `categorize_episode` → `{"op":"categorize_episode","episode_id":"…"}`.
#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum CategorizationAction {
    /// Re-run the heuristic categorizer over every episode in the
    /// kernel-side store. Returns `{"ok":true}` once the projection
    /// cache has been replaced.
    Run,
    /// Re-categorize a single episode. Returns
    /// `{"ok":true,"categories":[...]}` with the labels assigned to
    /// the episode. Useful for the iOS shell to refresh one row
    /// without rebuilding the whole projection.
    CategorizeEpisode { episode_id: String },
}

/// `podcast.categorize.run` action id.
pub const ACTION_CATEGORIZE_RUN: &str = "podcast.categorize.run";

/// `podcast.categorize.categorize_episode` action id.
pub const ACTION_CATEGORIZE_EPISODE: &str = "podcast.categorize.categorize_episode";

/// Single action module for the whole `"podcast.categorize"` namespace.
///
/// `execute` serializes the typed [`CategorizationAction`] back to JSON
/// and forwards the whole action through `ActorCommand::DispatchHostOp`,
/// matching the pattern used by [`super::podcast_module::PodcastActionModule`].
pub struct CategorizationModule;

impl ActionModule for CategorizationModule {
    const NAMESPACE: nmp_core::substrate::DeclaredActionNamespace =
        nmp_core::substrate::DeclaredActionNamespace::app_owned("podcast.categorize");

    type Action = CategorizationAction;

    fn is_async_completing() -> bool {
        false
    }

    fn execute(
        &self,
        _ctx: &nmp_core::substrate::ActionContext,
        action: Self::Action,
        correlation_id: &str,
        send: &dyn Fn(ActorCommand),
    ) -> Result<(), String> {
        crate::ffi::actions::dispatch_host_op(Self::NAMESPACE.as_str(), &action, correlation_id, send)
    }

    fn decode_payload(
        bytes: &[u8],
    ) -> Option<Result<Self::Action, nmp_core::substrate::ActionPayloadDecodeError>> {
        crate::action_payload::decode_podcast_payload(bytes)
    }
}

// ---------------------------------------------------------------------------
// Heuristic categorizer
// ---------------------------------------------------------------------------

/// Maximum number of category labels assigned to a single episode.
pub const MAX_CATEGORIES_PER_EPISODE: usize = 3;

/// Heuristically categorize one episode by `title + description`.
///
/// Returns up to [`MAX_CATEGORIES_PER_EPISODE`] labels, ordered by
/// keyword-match count (highest first). Categories with zero matches
/// are dropped. Ties resolved by [`CATEGORY_KEYWORDS`] order (the
/// stable sort below preserves the canonical order on equal counts).
///
/// Cost is **one linear pass over the haystack**, not one pass per
/// keyword. The naive "scan the whole haystack once per keyword"
/// approach this replaced was O(keywords × haystack length) *per
/// episode* — cheap for a single episode in isolation, but pathological
/// once run synchronously over a freshly-synced library on app launch
/// (see #755: it burned 32s of CPU on the main thread and tripped the
/// scene-create watchdog). [`keyword_tokens`] is built once and reused,
/// so the keyword set is never rescanned per call.
pub fn categorize_text(title: &str, description: &str) -> Vec<String> {
    let haystack = format!("{} {}", title, description).to_ascii_lowercase();
    if haystack.trim().is_empty() {
        return Vec::new();
    }

    let words: Vec<&str> = tokenize_words(&haystack).collect();
    if words.is_empty() {
        return Vec::new();
    }

    let index = keyword_tokens();
    // matched[cat_idx] holds the keyword indices already found for that
    // category, so a phrase repeated many times in the text is still
    // counted once — same semantics as the old per-keyword `.count()`.
    let mut matched: Vec<HashSet<usize>> = vec![HashSet::new(); CATEGORY_KEYWORDS.len()];

    for start in 0..words.len() {
        let Some(candidates) = index.by_first_token.get(words[start]) else {
            continue;
        };
        for &(cat_idx, kw_idx) in candidates {
            if matched[cat_idx].contains(&kw_idx) {
                continue;
            }
            let kw_tokens = &index.tokens[cat_idx][kw_idx];
            let end = start + kw_tokens.len();
            if end <= words.len() && words[start..end].iter().eq(kw_tokens.iter()) {
                matched[cat_idx].insert(kw_idx);
            }
        }
    }

    let mut hits: Vec<(usize, &str, usize)> = CATEGORY_KEYWORDS
        .iter()
        .enumerate()
        .map(|(idx, (category, _))| (idx, *category, matched[idx].len()))
        .filter(|(_, _, count)| *count > 0)
        .collect();

    // Stable sort: ties keep the canonical CATEGORY_KEYWORDS order.
    hits.sort_by(|a, b| b.2.cmp(&a.2).then(a.0.cmp(&b.0)));

    hits.into_iter()
        .take(MAX_CATEGORIES_PER_EPISODE)
        .map(|(_, cat, _)| cat.to_owned())
        .collect()
}

/// Split `s` into lowercase word tokens using the same word-boundary
/// rule the matcher relies on: a run of ASCII alphanumerics/underscore
/// is a word, everything else (spaces, hyphens, punctuation) is a
/// delimiter. Treating hyphens as delimiters too means a keyword phrase
/// like `"open source"` matches both "open source" and "open-source" in
/// free text without needing a second literal entry.
fn tokenize_words(s: &str) -> impl Iterator<Item = &str> {
    s.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
        .filter(|w| !w.is_empty())
}

/// One-time tokenized index over [`CATEGORY_KEYWORDS`]: `tokens[cat][kw]`
/// is that keyword's token sequence, and `by_first_token` maps a token to
/// every `(category, keyword)` pair whose phrase starts with it. Built
/// once via [`OnceLock`] — [`categorize_text`] never re-tokenizes or
/// re-scans the keyword set on a per-call basis.
struct KeywordTokens {
    tokens: Vec<Vec<Vec<&'static str>>>,
    by_first_token: HashMap<&'static str, Vec<(usize, usize)>>,
}

fn keyword_tokens() -> &'static KeywordTokens {
    static INDEX: OnceLock<KeywordTokens> = OnceLock::new();
    INDEX.get_or_init(|| {
        let mut tokens = Vec::with_capacity(CATEGORY_KEYWORDS.len());
        let mut by_first_token: HashMap<&'static str, Vec<(usize, usize)>> = HashMap::new();
        for (cat_idx, (_, keywords)) in CATEGORY_KEYWORDS.iter().enumerate() {
            let mut cat_tokens = Vec::with_capacity(keywords.len());
            for (kw_idx, kw) in keywords.iter().enumerate() {
                let kw_tokens: Vec<&'static str> = tokenize_words(kw).collect();
                if let Some(&first) = kw_tokens.first() {
                    by_first_token.entry(first).or_default().push((cat_idx, kw_idx));
                }
                cat_tokens.push(kw_tokens);
            }
            tokens.push(cat_tokens);
        }
        KeywordTokens { tokens, by_first_token }
    })
}

#[cfg(test)]
#[path = "categorization_module_tests.rs"]
mod tests;
