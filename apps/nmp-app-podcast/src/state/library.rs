//! `LibraryState` — canonical persisted root (step 15).
//!
//! Owns the two outermost persisted slots:
//!
//! - `store`:    `Arc<Mutex<PodcastStore>>` — the whole podcast library, episode
//!               list, positions, settings, and memory facts.  Every other
//!               substate holds a **clone** of this same `Arc`; this is the
//!               **owner** copy that lives in `PodcastAppState`.
//!
//! - `identity`: `Arc<Mutex<IdentityStore>>` — the user's NIP-01 keypair.
//!               Accessed by CommentsState (author check), the agent-notes
//!               observer, and the identity action handler.
//!
//! ## Lock-order note (§6.2)
//!
//! `store` is the outermost lock in the canonical hierarchy.  Never hold
//! `store` while taking an inner substate slot lock.

use std::sync::{Arc, Mutex};

use crate::store::identity::IdentityStore;
use crate::store::PodcastStore;

/// Owns the canonical persisted root of the podcast app.
///
/// Introduced in step 15 of the god-root consolidation; relocates the owner
/// copy of `store` and `identity` from `register.rs` locals into the composed
/// `PodcastAppState` tree.  All other substates continue to hold their existing
/// `Arc` clones — the lock topology is unchanged.
pub struct LibraryState {
    /// The canonical persisted library (podcasts, episodes, positions, settings,
    /// memory facts, triage state, ad-segments, …).  Every other substate that
    /// reads or writes persisted data holds a **clone of this same `Arc`** —
    /// `LibraryState` is merely the tree-level owner so the Arc is reachable as
    /// `state.library.store` without a separate register.rs local.
    pub store: Arc<Mutex<PodcastStore>>,

    /// The user's NIP-01 keypair.  Persisted to `identity.json` via
    /// `IdentityStore::set_data_dir` (called from `nmp_app_podcast_set_data_dir`).
    pub identity: Arc<Mutex<IdentityStore>>,
}

impl LibraryState {
    pub fn new(
        store: Arc<Mutex<PodcastStore>>,
        identity: Arc<Mutex<IdentityStore>>,
    ) -> Self {
        Self { store, identity }
    }
}
