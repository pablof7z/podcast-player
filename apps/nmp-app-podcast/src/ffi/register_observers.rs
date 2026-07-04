//! Reactive observer wiring for [`super::register::register_podcast_app`]
//! (pablof7z/podcast-player#690).
//!
//! The deleted blanket `NmpApp::register_event_observer` raw tap is replaced by
//! declarative `open_observed_projection(ObservedProjection::from_kinds(..))`
//! registrations. Each sink is an [`nmp_core::ObservedProjectionSink`] whose
//! declared kind/scope shape mirrors the observer's prior interest scope; the
//! kernel replays cached matching events on open and delivers future ones via
//! `notify_observers` (fired after every `EventStore::insert`), so a sink is
//! notified for any accepted event of its shape regardless of which interest
//! opened the subscription.

use std::sync::{Arc, Mutex};

use nmp_core::substrate::{ObservedProjection, ObservedProjectionRegistrar};
use nmp_native_runtime::NmpApp;
use nmp_nip02::ActiveFollowSet;

use crate::snapshot_signal::SnapshotUpdateSignal;
use crate::state::PodcastAppState;
use crate::store::agent_note_responder_cache::ResponderCache;
use crate::store::approved_peer_store::ApprovedPeerStore;
use crate::store::identity::IdentityStore;
use crate::store::outbound_turn_cache::OutboundTurnCache;
use crate::store::PodcastStore;

/// Shared context the observer registrations borrow from `register`.
///
/// All fields are constructed in `register.rs` before `app_state` is sealed and
/// the handle is built; the observers `.share()` the same slots the snapshot
/// reads, and clone the caches the handle also owns.
pub(super) struct ObserverWiring<'a> {
    /// Raw handle for capability dispatch (agent-note auto-responder).
    pub app: *mut NmpApp,
    /// Shared borrow used to open observed projections and identity hooks.
    pub app_ref: &'a NmpApp,
    pub app_state: &'a Arc<PodcastAppState>,
    pub snapshot_signal: &'a SnapshotUpdateSignal,
    pub store: &'a Arc<Mutex<PodcastStore>>,
    pub identity: &'a Arc<Mutex<IdentityStore>>,
    pub active_follow_set: &'a Arc<ActiveFollowSet>,
    pub approved_peer_store: &'a Arc<Mutex<ApprovedPeerStore>>,
    pub responder_cache: &'a Arc<Mutex<ResponderCache>>,
    pub outbound_turn_cache: &'a Arc<Mutex<OutboundTurnCache>>,
}

/// Register the five reactive observers on the observed-projection seam.
pub(super) fn register_reactive_observers(w: ObserverWiring<'_>) {
    let ObserverWiring {
        app,
        app_ref,
        app_state,
        snapshot_signal,
        store,
        identity,
        active_follow_set,
        approved_peer_store,
        responder_cache,
        outbound_turn_cache,
    } = w;

    // NIP-F4 discovery observer. The `podcast.discover_nostr` action emits
    // `ActorCommand::Interests(InterestsCommand::EnsureInterest)` for
    // `kind:10154`; NMP core opens the subscription through its own relay pool
    // (no iOS WebSocket — D7) and every inbound show event fires this observer,
    // which writes the projected show onto the same `nostr_results` slot the
    // snapshot reads. The returned id is dropped: the observer lives for the
    // app's lifetime (mirrors the snapshot projection), and `nmp_app_free`
    // joins the actor before dropping the slot.
    //
    // Shape: a Global, kind:10154-only shape (no author filter — discovery is a
    // browse across all published shows), mirroring the `nostr_discovery_interest()`
    // sweep this observer already consumes historical shows from.
    let _discovery_observer_id = app_ref.open_observed_projection(ObservedProjection::from_kinds(
        std::sync::Arc::new(
            crate::discover_nostr::NostrDiscoveryObserver::new(
                app_state.discovery.nostr_results.share(),
                app_state.infra.rev.clone(),
            )
            .with_snapshot_signal(snapshot_signal.clone()),
        ),
        "podcast.discover_nostr.observer",
        1, // Global — discovery is not tied to the active account.
        [crate::discover_nostr::KIND_NIP_F4_SHOW],
        crate::discover_nostr::NOSTR_DISCOVERY_LIMIT as usize,
    ));

    // kind:1111 comments observer — receives events from push_interest_via_nmp
    // subscriptions opened by handle_fetch_comments. No iOS WebSocket. Shares
    // the cache from state.comments.cache.
    //
    // Shape: a Global, kind:1111-only shape (comments are anchored by episode
    // `#i` tag, not by account) — the observer itself already narrows to the
    // anchor it cares about per inbound event.
    let _comments_observer_id = app_ref.open_observed_projection(ObservedProjection::from_kinds(
        std::sync::Arc::new(
            crate::comments_handler::CommentsObserver::new(
                store.clone(),
                app_state.comments.cache.share(),
                app_state.infra.rev.clone(),
            )
            .with_snapshot_signal(snapshot_signal.clone()),
        ),
        "podcast.comments.observer",
        1, // Global — comment anchors are not account-scoped.
        [1111u32],
        256,
    ));

    // ── Reactive social-graph observers ──────────────────────────────────────
    //
    // `active_follow_set` was constructed in `register` (before sealing
    // `app_state`) and injected into SocialState. Here it is registered as an
    // ObservedProjectionSink so kind:3 events keep it current, and an
    // identity-change hook resets all per-account social state on switch.
    //
    // Account-change hook: `register_identity_change_observer` fires on the
    // update-listener thread whenever the active pubkey changes (sign-in /
    // switch / logout). It:
    //   1. `notify_account_changed` — clears the stale follow set and re-seeds
    //      the new account's own pubkey (self-inclusion).
    //   2. `clear_for_account_switch` — empties `social_slot` + `agent_notes`
    //      so A's following list and A's notes don't bleed into B's session
    //      (cross-account leak fix).
    {
        let afs = Arc::clone(active_follow_set);
        let state_for_switch = app_state.clone();
        app_ref.register_identity_change_observer(move |_| {
            afs.notify_account_changed();
            state_for_switch.social.clear_for_account_switch();
        });
    }
    // Clone as the concrete type, then let the fn-arg position coerce
    // Arc<ActiveFollowSet> → Arc<dyn ObservedProjectionSink> (unsizing).
    //
    // Shape: an ActiveAccount-scoped, kind:3-only shape — `ActiveFollowSet::on_kernel_event`
    // itself gates on `event.author == active account`, so an unrelated kind:3
    // is a cheap no-op rather than a filter miss.
    let _follow_set_observer_id = app_ref.open_observed_projection(ObservedProjection::from_kinds(
        active_follow_set.clone(),
        "podcast.social.active_follow_set",
        0, // ActiveAccount — re-routes to the new account's kind:3 on switch.
        [3u32],
        16,
    ));

    // FollowListObserver: materialises a SocialSnapshot from the inner
    // FollowListProjection on every kind:3 push frame and writes it to
    // state.social.social_slot.
    //
    // `with_social_infra` wires the Domain::Social-scoped Infra so every kind:3
    // mutation bumps `domain_revs.social` (driving the podcast.social sidecar
    // re-emit) AND the global rev/signal. `FollowListProjection` (the observer's
    // inner read-model) is a thin read-model over the canonical event store via
    // `LatestKind3FollowSet` (replaces the deleted `ContactsLookup` cache).
    //
    // Shape: the same ActiveAccount-scoped kind:3 shape as `active_follow_set`.
    let _follow_list_observer_id = app_ref.open_observed_projection(ObservedProjection::from_kinds(
        std::sync::Arc::new(
            crate::social_handler::FollowListObserver::new(
                app_ref.active_account_handle(),
                nmp_nip02::LatestKind3FollowSet::new(app_ref.event_store_handle()),
                app_state.social.social_slot.share(),
                app_state.infra.rev.clone(),
            )
            .with_snapshot_signal(snapshot_signal.clone())
            .with_social_infra(app_state.social.infra.clone()),
        ),
        "podcast.social.follow_list_observer",
        0, // ActiveAccount — mirrors the active-account kind:3 shape above.
        [3u32],
        16,
    ));

    // kind:1 agent-notes observer — receives events from push_interest_via_nmp
    // subscriptions opened by handle_fetch_agent_notes. No iOS WebSocket. It
    // caches raw notes (author hex retained, NO trust stamp); the trust verdict
    // is recomputed live at projection time in SocialState against the shared
    // ActiveFollowSet (so follow/unfollow flips existing notes).
    //
    // `with_responder` wires the auto-responder: when a trusted note lands, the
    // observer spawns an async LLM-reply + publish task off the actor thread (D8).
    //
    // Shape: a Global, kind:1-only shape — matching `agent_notes_interest`'s own
    // `InterestScope::Global` (the `#p`-tag filter on the active pubkey is baked
    // into the `LogicalInterest` that `handle_fetch_agent_notes` pushes).
    let _agent_notes_observer_id = app_ref.open_observed_projection(ObservedProjection::from_kinds(
        std::sync::Arc::new(
            crate::agent_note_handler::AgentNotesObserver::new(
                identity.clone(),
                app_state.social.agent_notes.share(),
                app_state.infra.rev.clone(),
            )
            .with_snapshot_signal(snapshot_signal.clone())
            // `Domain::Social`-scoped infra: inbound-note bumps advance
            // `domain_revs.social`, driving the `podcast.social` sidecar re-emit.
            .with_social_infra(app_state.social.infra.clone())
            .with_responder(
                app,
                Arc::clone(active_follow_set),
                Arc::clone(approved_peer_store),
                store.clone(),
                Arc::clone(responder_cache),
                Arc::clone(outbound_turn_cache),
                app_state.social.outbound_turns.share(),
                app_state.infra.runtime.clone(),
            ),
        ),
        "podcast.social.agent_notes_observer",
        1, // Global — the `#p`-tag filter is baked into the pushed interest.
        [1u32],
        64,
    ));
}
