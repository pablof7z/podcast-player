//! AI-wiki ActionModule — routes all `"podcast.wiki.*"` dispatches.
//!
//! Swift encodes every wiki action as `{"op":"<variant>", ...fields}`.
//! The `#[serde(tag = "op", rename_all = "snake_case")]` discriminator maps
//! the string `op` value to the enum variant. The module's `execute` body
//! forwards the whole action as `ActorCommand::DispatchHostOp` so the
//! `PodcastHostOpHandler` (running on the actor thread) can mutate the
//! `wiki_articles` / `wiki_search_results` slots on the handle without the
//! kernel naming podcast-domain nouns (D0).
//!
//! ## Scaffold scope (PR #39)
//!
//! `generate` produces a stub `WikiArticle` with a placeholder summary —
//! the iOS reader can render the full UI without real LLM synthesis. The
//! follow-up swap-in replaces only the summary-building path on the kernel
//! side; the wire shape stays stable.

use serde::{Deserialize, Serialize};

use nmp_core::substrate::ActionModule;
use nmp_core::ActorCommand;

/// Wire enum for all `"podcast.wiki"` namespace actions.
///
/// `#[serde(tag = "op", rename_all = "snake_case")]` makes the JSON
/// discriminator the lowercase snake-case variant name:
/// `generate` → `{"op":"generate","podcast_id":"...","topic":"..."}`.
#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum WikiAction {
    /// Create a new wiki article for `(podcast_id, topic)`.
    ///
    /// Returns `{"ok":true,"article_id":"<uuid>"}` with the freshly
    /// generated UUID so the caller can navigate straight to the new
    /// article without polling the snapshot.
    Generate { podcast_id: String, topic: String },
    /// Remove an article from `wiki_articles` by id.
    Delete { article_id: String },
    /// Filter `wiki_articles` by a case-insensitive substring match on
    /// `topic` and stash the result in `wiki_search_results`. Empty
    /// `query` clears the search results.
    Search { query: String },
}

/// Action module for the `"podcast.wiki"` namespace.
///
/// `execute` serializes the typed `WikiAction` back to JSON and hands it
/// to the actor as `ActorCommand::DispatchHostOp`. The installed
/// `PodcastHostOpHandler` deserializes it, mutates the wiki slots on the
/// handle, and returns the `{"ok":true,...}` envelope.
pub struct WikiActionModule;

impl ActionModule for WikiActionModule {
    const NAMESPACE: &'static str = "podcast.wiki";

    type Action = WikiAction;

    fn is_async_completing() -> bool {
        false
    }

    fn execute(
        action: Self::Action,
        correlation_id: &str,
        send: &dyn Fn(ActorCommand),
    ) -> Result<(), String> {
        crate::ffi::actions::dispatch_host_op(Self::NAMESPACE, &action, correlation_id, send)
    }
}

#[cfg(test)]
#[path = "wiki_module_tests.rs"]
mod tests;
