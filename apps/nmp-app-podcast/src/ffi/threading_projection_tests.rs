//! Tests for [super]'s rev-keyed `threading_projection_cache`.
//!
//! Regression guard for #755's residual launch hang: `HomeView`'s `.task`
//! blocks call into `threading_projection`/`threading_active_topics` several
//! times per launch as the library and categorizer cache settle. Each call
//! used to re-run `collect_thread_inputs` + `build_projection` from scratch
//! (a full library scan) even when nothing had changed since the last call.
//! These tests assert the cache actually short-circuits a same-rev repeat
//! call (`Arc::ptr_eq` on the cached value — a functional proof, not a
//! timing threshold) and correctly rebuilds once the rev advances.
//!
//! The cache is keyed off `domain_revs.library` (not the global
//! `state.infra.rev`) — see `projection_and_inputs_for_current_rev`'s doc
//! comment for why: the global rev also bumps on unrelated domains (e.g.
//! `Domain::Playback` position ticks at 4 Hz), which was invalidating an
//! already-fresh threading-projection cache on every tick. These tests drive
//! `domain_revs.library` directly to assert on cache hit vs. rebuild.

use super::*;
use crate::store::PodcastStore;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

/// Build a `PodcastHandle` with a NULL `app` pointer — these tests only
/// exercise the threading-projection path, which never touches `app`.
/// `Infra::for_test_with_library_rev` lets the test drive
/// `state.infra.domain_revs.library` directly so it can assert on cache hit
/// vs. rebuild.
fn make_handle(store: Arc<Mutex<PodcastStore>>, library_rev: Arc<AtomicU64>) -> Box<PodcastHandle> {
    let state = Arc::new(crate::state::PodcastAppState::new(
        crate::state::Infra::for_test_with_library_rev(library_rev),
        store,
    ));
    Box::new(PodcastHandle {
        app: std::ptr::null_mut(),
        state,
        responder_cache: Arc::new(Mutex::new(
            crate::store::agent_note_responder_cache::ResponderCache::default(),
        )),
        outbound_turn_cache: Arc::new(Mutex::new(
            crate::store::outbound_turn_cache::OutboundTurnCache::new(),
        )),
        approved_peer_store: Arc::new(Mutex::new(
            crate::store::approved_peer_store::ApprovedPeerStore::new(),
        )),
        snapshot_cache: Arc::new(Mutex::new(None)),
        threading_projection_cache: Arc::new(Mutex::new(None)),
        clean_html_cache: Arc::new(Mutex::new(HashMap::new())),
        ask_state: Arc::new(Mutex::new(crate::ffi::agent_ask::AgentAskState::default())),
        ask_callback: Arc::new(Mutex::new(
            crate::ffi::agent_ask::AgentAskCallbackState::default(),
        )),
    })
}

#[test]
fn same_rev_reuses_cached_projection_and_inputs() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let rev = Arc::new(AtomicU64::new(1));
    let handle = make_handle(store, rev);

    let (inputs_a, projection_a) =
        projection_and_inputs_for_current_rev(&handle).expect("first build");
    let (inputs_b, projection_b) =
        projection_and_inputs_for_current_rev(&handle).expect("cache hit");

    assert!(
        Arc::ptr_eq(&inputs_a, &inputs_b),
        "a same-rev repeat call must reuse the cached inputs instead of \
         re-scanning the library"
    );
    assert!(
        Arc::ptr_eq(&projection_a, &projection_b),
        "a same-rev repeat call must reuse the cached projection instead of \
         rebuilding it"
    );
}

#[test]
fn rev_bump_invalidates_the_cache() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let rev = Arc::new(AtomicU64::new(1));
    let handle = make_handle(store, rev.clone());

    let (_inputs_a, projection_a) =
        projection_and_inputs_for_current_rev(&handle).expect("first build");
    rev.fetch_add(1, Ordering::Relaxed);
    let (_inputs_b, projection_b) =
        projection_and_inputs_for_current_rev(&handle).expect("rebuild after bump");

    assert!(
        !Arc::ptr_eq(&projection_a, &projection_b),
        "a rev bump must force a fresh rebuild rather than reuse the stale cache"
    );
}

/// Regression guard for the fix that keys this cache off `domain_revs.library`
/// instead of the global `state.infra.rev`: a bump of the global rev alone
/// (e.g. the 4 Hz `Domain::Playback` position tick, or any other domain's
/// mutation) must NOT invalidate an already-fresh threading-projection
/// cache. Before this fix, a single playback tick during the ~1s cold build
/// on a real library could force a fresh full-library rebuild even though
/// nothing library-content-relevant had changed.
#[test]
fn unrelated_global_rev_bump_does_not_invalidate_the_cache() {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let library_rev = Arc::new(AtomicU64::new(1));
    let handle = make_handle(store, library_rev);

    let (inputs_a, projection_a) =
        projection_and_inputs_for_current_rev(&handle).expect("first build");
    // Bump ONLY the global rev — simulates an unrelated domain's mutation
    // (e.g. a playback position tick), not a library-content change.
    handle.state.infra.rev.fetch_add(1, Ordering::Relaxed);
    let (inputs_b, projection_b) =
        projection_and_inputs_for_current_rev(&handle).expect("cache hit");

    assert!(
        Arc::ptr_eq(&inputs_a, &inputs_b),
        "a global-rev-only bump must NOT force a rebuild of cached inputs"
    );
    assert!(
        Arc::ptr_eq(&projection_a, &projection_b),
        "a global-rev-only bump must NOT force a rebuild of the cached projection"
    );
}
