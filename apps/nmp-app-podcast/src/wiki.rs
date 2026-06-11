//! AI-wiki module — home of LLM synthesis helpers and `wiki_llm` re-exports.
//!
//! ## Migration note (Step 2)
//!
//! The free-function pair `handle_wiki_action` / `handle_wiki_action_inner`
//! and their slot parameters have been replaced by `WikiState::handle` in
//! `crate::state::wiki`.  This file now contains only the helper types that
//! other modules depend on and the module-level test for the collector
//! helper used by the LLM context path.
//!
//! The tests that previously exercised the free functions are superseded by
//! the `state::wiki` unit tests and the golden-snapshot integration test.
