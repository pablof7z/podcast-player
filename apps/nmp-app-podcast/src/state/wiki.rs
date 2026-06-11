//! Wiki substate — Step 2 of the god-root consolidation.
//!
//! Owns the two slots that were previously mirrored between
//! `PodcastHandle` and `PodcastHostOpHandler`:
//!
//! * `articles` — session-only cache of all AI-wiki articles the user
//!   has generated.  **Session** durability.
//! * `search_results` — transient result of the most recent
//!   `podcast.wiki.search`.  **Session** durability.
//!
//! Also holds a shared `Arc<Mutex<KnowledgeStore>>` (reused from
//! `KnowledgeState` — NOT a second store) for RAG context in Generate.
//!
//! The free-function pair `handle_wiki_action` / `handle_wiki_action_with_signal`
//! in `crate::wiki` is replaced by `WikiState::handle`.  The
//! `_with_signal` / non-signal fork disappears: `infra.bump()` unifies both.
//!
//! ## File-length ceiling
//!
//! AGENTS.md hard limit is 500 lines.  Split into `wiki_actions.rs` before
//! reaching the 300-line soft limit if new actions are added.

use std::sync::{Arc, Mutex};

use podcast_knowledge::KnowledgeStore;

use crate::ffi::actions::wiki_module::WikiAction;
use crate::ffi::projections::WikiArticle;
use crate::state::slot::Session;
use crate::state::{Infra, Slot};
use crate::store::PodcastStore;

/// Wiki feature substate.
///
/// Constructed once in `PodcastAppState::new` and referenced via
/// `state.wiki` on both seams.  All methods are `&self`.
pub struct WikiState {
    /// All AI-wiki articles the user has generated.  Session durability.
    pub articles: Slot<Vec<WikiArticle>, Session>,
    /// Transient result of the most recent `podcast.wiki.search`.
    /// Session durability.
    pub search_results: Slot<Vec<WikiArticle>, Session>,
    /// Shared RAG chunk index — same `Arc` as `KnowledgeState.index`.
    /// Wiki uses it for context in Generate; it does NOT own the index.
    knowledge_index: Arc<Mutex<KnowledgeStore>>,
    /// Rev + signal + runtime (cloned from `PodcastAppState::infra`).
    infra: Infra,
    /// The canonical persisted library.  Wiki reads podcast/episode data
    /// for LLM context.
    store: Arc<Mutex<PodcastStore>>,
}

impl WikiState {
    /// Production constructor — called from `PodcastAppState::new`.
    pub fn new(
        infra: Infra,
        store: Arc<Mutex<PodcastStore>>,
        knowledge_index: Arc<Mutex<KnowledgeStore>>,
    ) -> Self {
        Self {
            articles: Slot::new(Vec::new()),
            search_results: Slot::new(Vec::new()),
            knowledge_index,
            infra,
            store,
        }
    }

    /// Test constructor — builds a `WikiState` without an `NmpApp`.
    #[cfg(test)]
    pub fn for_test(
        store: Arc<Mutex<PodcastStore>>,
        knowledge_index: Arc<Mutex<KnowledgeStore>>,
    ) -> Self {
        Self::new(Infra::for_test(), store, knowledge_index)
    }

    // ── Snapshot projections ──────────────────────────────────────────────

    /// Clone current articles for the snapshot projection.
    pub fn articles_snapshot(&self) -> Vec<WikiArticle> {
        self.articles.lock().ok().map(|w| w.clone()).unwrap_or_default()
    }

    /// Clone current search results for the snapshot projection.
    pub fn search_results_snapshot(&self) -> Vec<WikiArticle> {
        self.search_results
            .lock()
            .ok()
            .map(|w| w.clone())
            .unwrap_or_default()
    }

    // ── Action handler ────────────────────────────────────────────────────

    /// Route a single `podcast.wiki.*` action.
    ///
    /// Replaces the `handle_wiki_action` / `handle_wiki_action_with_signal`
    /// free-function pair.  The signal-vs-no-signal fork disappears:
    /// `infra.bump()` handles both.
    pub fn handle(&self, action: WikiAction) -> serde_json::Value {
        match action {
            WikiAction::Generate { podcast_id, topic } => {
                self.handle_generate(podcast_id, topic)
            }
            WikiAction::Delete { article_id } => self.handle_delete(article_id),
            WikiAction::Search { query } => self.handle_search(query),
        }
    }

    // ── Private action bodies ─────────────────────────────────────────────

    fn handle_generate(&self, podcast_id: String, topic: String) -> serde_json::Value {
        use crate::knowledge::collect_chunk_texts_for_topic;
        use crate::wiki_llm;
        use chrono::Utc;

        /// RAG context chunks pulled into the wiki prompt per generate.
        const WIKI_CONTEXT_CHUNK_LIMIT: usize = 5;

        let topic_trimmed = topic.trim().to_owned();
        if topic_trimmed.is_empty() {
            return serde_json::json!({"ok": false, "error": "topic is empty"});
        }
        if podcast_id.trim().is_empty() {
            return serde_json::json!({"ok": false, "error": "podcast_id is empty"});
        }

        // Collect podcast title + stored transcripts + episode ids for LLM
        // context. Store lock dropped before the chunk lookup.
        let (podcast_title, transcripts, episode_ids) = {
            match self.store.lock() {
                Ok(s) => {
                    use podcast_core::PodcastId;
                    use uuid::Uuid;
                    let pid = Uuid::parse_str(&podcast_id).ok().map(PodcastId::new);
                    let title = pid
                        .and_then(|id| s.podcast(id))
                        .map(|p| p.title.clone())
                        .unwrap_or_else(|| podcast_id.clone());
                    let eps = pid
                        .map(|id| s.episodes_for(id).to_vec())
                        .unwrap_or_default();
                    let ep_ids: Vec<String> =
                        eps.iter().map(|ep| ep.id.0.to_string()).collect();
                    let txs: Vec<String> = eps
                        .iter()
                        .filter_map(|ep| {
                            s.transcript_for(&ep.id.0.to_string()).map(|t| t.to_owned())
                        })
                        .filter(|t| !t.is_empty())
                        .collect();
                    (title, txs, ep_ids)
                }
                Err(_) => (podcast_id.clone(), Vec::new(), Vec::new()),
            }
        };

        // Pull the most relevant indexed transcript chunks for the topic.
        // Lock dropped before spawn.
        let chunk_hits: Vec<(String, String)> = match self.knowledge_index.lock() {
            Ok(ks) => collect_chunk_texts_for_topic(
                &ks,
                &topic_trimmed,
                &episode_ids,
                WIKI_CONTEXT_CHUNK_LIMIT,
            ),
            Err(_) => Vec::new(),
        };

        // M9 source attribution: contributing episode ids.
        let source_episode_ids: Vec<String> = {
            let mut ids: Vec<String> = chunk_hits.iter().map(|(ep, _)| ep.clone()).collect();
            ids.sort();
            ids.dedup();
            ids
        };
        let context_chunks: Vec<String> =
            chunk_hits.into_iter().map(|(_, text)| text).collect();

        let article_id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now().timestamp();

        // Insert a placeholder immediately (is_generating=true) so the iOS
        // snapshot shows the article card while synthesis runs off-thread.
        let placeholder_article = WikiArticle {
            id: article_id.clone(),
            podcast_id: podcast_id.clone(),
            topic: topic_trimmed.clone(),
            summary: format!("Generating an article about '{topic_trimmed}'…"),
            source_episode_ids,
            last_updated_at: now,
            is_generating: true,
            generation_error: None,
        };
        match self.articles.lock() {
            Ok(mut w) => w.push(placeholder_article),
            Err(_) => return serde_json::json!({"ok": false, "error": "wiki_articles poisoned"}),
        }
        // Bump before spawning — drop guard above first (lock-order §6.2).
        self.infra.bump();

        // Spawn synthesis off the actor thread.
        let articles_arc = self.articles.share();
        let store_c = Arc::clone(&self.store);
        let runtime_c = Arc::clone(&self.infra.runtime);
        let infra_c = self.infra.clone();
        let article_id_c = article_id.clone();
        let placeholder_fallback = format!(
            "Could not generate an article about '{topic_trimmed}'. Check that the LLM is running."
        );

        self.infra.runtime.spawn(async move {
            let result = tokio::task::spawn_blocking(move || {
                wiki_llm::synthesize_summary(
                    &topic_trimmed,
                    &podcast_title,
                    &transcripts,
                    &context_chunks,
                    &runtime_c,
                    &store_c,
                )
            })
            .await;

            let (summary, error) = match result {
                Ok(Ok(body)) => (body, None),
                Ok(Err(e)) => (placeholder_fallback, Some(e)),
                Err(_) => (
                    placeholder_fallback,
                    Some("synthesis task panicked".to_owned()),
                ),
            };

            if let Ok(mut w) = articles_arc.lock() {
                if let Some(a) = w.iter_mut().find(|a| a.id == article_id_c) {
                    a.summary = summary;
                    a.is_generating = false;
                    a.generation_error = error;
                    a.last_updated_at = Utc::now().timestamp();
                }
            }
            // Drop guard before bump (§6.2).
            infra_c.bump();
        });

        serde_json::json!({"ok": true, "article_id": article_id})
    }

    fn handle_delete(&self, article_id: String) -> serde_json::Value {
        let removed = match self.articles.lock() {
            Ok(mut w) => {
                let before = w.len();
                w.retain(|a| a.id != article_id);
                before != w.len()
            }
            Err(_) => {
                return serde_json::json!({"ok": false, "error": "wiki_articles poisoned"})
            }
        };
        // Also drop the article from any active search result.
        if let Ok(mut s) = self.search_results.lock() {
            s.retain(|a| a.id != article_id);
        }
        // Drop guards before bump.
        self.infra.bump_if(removed);
        serde_json::json!({"ok": true})
    }

    fn handle_search(&self, query: String) -> serde_json::Value {
        let q = query.trim().to_lowercase();
        let snapshot = match self.articles.lock() {
            Ok(w) => w.clone(),
            Err(_) => return serde_json::json!({"ok": false, "error": "wiki_articles poisoned"}),
        };
        let results: Vec<WikiArticle> = if q.is_empty() {
            Vec::new()
        } else {
            snapshot
                .into_iter()
                .filter(|a| a.topic.to_lowercase().contains(&q))
                .collect()
        };
        match self.search_results.lock() {
            Ok(mut s) => {
                *s = results;
                drop(s);
                self.infra.bump();
                serde_json::json!({"ok": true})
            }
            Err(_) => {
                serde_json::json!({"ok": false, "error": "wiki_search_results poisoned"})
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use podcast_knowledge::KnowledgeStore;

    use crate::ffi::actions::wiki_module::WikiAction;
    use crate::store::PodcastStore;

    use super::*;

    fn make_state() -> WikiState {
        WikiState::for_test(
            Arc::new(Mutex::new(PodcastStore::new())),
            Arc::new(Mutex::new(KnowledgeStore::new())),
        )
    }

    #[test]
    fn generate_inserts_placeholder_and_primes_rev() {
        let state = make_state();
        let rev0 = state.infra.rev();
        let out = state.handle(WikiAction::Generate {
            podcast_id: "pod-1".into(),
            topic: "Bitcoin halvings".into(),
        });
        assert_eq!(out["ok"], true);
        let article_id = out["article_id"].as_str().unwrap().to_owned();
        assert!(!article_id.is_empty());
        let stored = state.articles_snapshot();
        assert_eq!(stored.len(), 1);
        assert_eq!(stored[0].topic, "Bitcoin halvings");
        assert!(stored[0].is_generating);
        assert!(state.infra.rev() > rev0, "must bump rev");
    }

    #[test]
    fn generate_rejects_empty_topic() {
        let state = make_state();
        let out = state.handle(WikiAction::Generate {
            podcast_id: "pod-1".into(),
            topic: "   ".into(),
        });
        assert_eq!(out["ok"], false);
        assert!(state.articles_snapshot().is_empty());
    }

    #[test]
    fn generate_rejects_empty_podcast_id() {
        let state = make_state();
        let out = state.handle(WikiAction::Generate {
            podcast_id: "".into(),
            topic: "Topic".into(),
        });
        assert_eq!(out["ok"], false);
    }

    #[test]
    fn delete_removes_article_and_clears_search_row() {
        let state = make_state();
        let out = state.handle(WikiAction::Generate {
            podcast_id: "pod-1".into(),
            topic: "Topic".into(),
        });
        let article_id = out["article_id"].as_str().unwrap().to_owned();
        // Manually populate search results.
        {
            let snap = state.articles_snapshot();
            *state.search_results.lock().unwrap() = snap;
        }
        let rev_before = state.infra.rev();
        let out2 = state.handle(WikiAction::Delete {
            article_id: article_id.clone(),
        });
        assert_eq!(out2["ok"], true);
        assert!(state.articles_snapshot().is_empty());
        assert!(state.search_results_snapshot().is_empty());
        assert!(state.infra.rev() > rev_before, "delete must bump rev");
    }

    #[test]
    fn delete_unknown_id_does_not_bump_rev() {
        let state = make_state();
        let rev_before = state.infra.rev();
        let out = state.handle(WikiAction::Delete {
            article_id: "does-not-exist".into(),
        });
        assert_eq!(out["ok"], true);
        assert_eq!(state.infra.rev(), rev_before);
    }

    #[test]
    fn search_filters_by_topic_substring_case_insensitive() {
        let state = make_state();
        state.handle(WikiAction::Generate {
            podcast_id: "pod-1".into(),
            topic: "Bitcoin Halvings".into(),
        });
        state.handle(WikiAction::Generate {
            podcast_id: "pod-1".into(),
            topic: "Lightning Network".into(),
        });
        let out = state.handle(WikiAction::Search {
            query: "lightning".into(),
        });
        assert_eq!(out["ok"], true);
        let hits = state.search_results_snapshot();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].topic, "Lightning Network");
    }

    #[test]
    fn search_with_empty_query_clears_results() {
        let state = make_state();
        state.handle(WikiAction::Generate {
            podcast_id: "pod-1".into(),
            topic: "Topic".into(),
        });
        state.handle(WikiAction::Search { query: "to".into() });
        assert_eq!(state.search_results_snapshot().len(), 1);
        state.handle(WikiAction::Search { query: "  ".into() });
        assert!(state.search_results_snapshot().is_empty());
    }
}
