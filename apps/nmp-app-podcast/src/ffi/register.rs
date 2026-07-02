//! The `pub extern "C"` registration entry point Swift links against to wire
//! Podcast projections and action namespaces into an [`NmpApp`].

use std::sync::{Arc, Mutex};

use crate::state::{Infra, PodcastAppState};

use nmp_core::substrate::{ObservedProjection, ObservedProjectionRegistrar};
use nmp_native_runtime::NmpApp;
use nmp_nip02::{ActiveFollowSet, LatestKind3FollowSet};

use super::guard::ffi_guard;
use super::handle::PodcastHandle;
use crate::host_op_handler::PodcastHostOpHandler;
use crate::store::agent_note_responder_cache::ResponderCache;
use crate::store::approved_peer_store::ApprovedPeerStore;
use crate::store::outbound_turn_cache::OutboundTurnCache;
use crate::snapshot_signal::SnapshotUpdateSignal;
use crate::store::identity::IdentityStore;
use crate::store::PodcastStore;
// player_actor, queue, download_queue removed in Step 14 —
// now seeded inside PodcastAppState::new (PlaybackState).

/// Register Podcast projections and action namespaces against `app`. Returns a
/// non-null `*mut PodcastHandle` on success; `null` on any failure (null
/// pointer arguments, slot lock poisoning).
///
/// `app` MUST outlive the returned handle. Call
/// [`nmp_app_podcast_unregister`] before `nmp_app_free`.
#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_register(app: *mut NmpApp) -> *mut PodcastHandle {
    if app.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard("nmp_app_podcast_register", std::ptr::null_mut, || {
    // Wire the canonical NMP composition — NIP-02 / NIP-17 / NIP-57 / NIP-65
    // action modules, the kind:10050 ingest parser, the production routing
    // substrate, and the DM-inbox + zap-receipts runtime controllers.
    //
    // SAFETY: caller guarantees `app` is a valid pointer from `nmp_app_new`.
    // No other reference aliases it here — the `&*app` borrow further down is
    // taken only after this exclusive borrow is dropped.
    // AssertUnwindSafe is sound: all pointer null checks happen before this
    // closure is constructed; captured raw ptrs are never observed on panic path.
    let app_mut = unsafe { &mut *app };
    // ADR-0069: `register_defaults` is deleted. Compose the same protocol
    // surface (substrate + per-crate protocol registers + podcast action
    // modules) via explicit installers. See `register_composition`.
    super::register_composition::install_protocol_composition(app_mut);

    // Shared state between the handle (snapshot reader) and the handler (writer).
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let identity = Arc::new(Mutex::new(IdentityStore::new()));
    // player_actor removed in Step 14 — now seeded inside PlaybackState.
    // search_results and nostr_results removed in Step 9 —
    // now owned by state.discovery (DiscoveryState).
    // queue removed in Step 14 — now seeded inside PlaybackState.
    // download_queue removed in Step 14 — now seeded inside PlaybackState.
    // picks and picks_score_in_progress removed in Step 3 —
    // they are now seeded inside PodcastAppState::new (PicksState).
    // clips removed in Step 5a — now seeded inside PodcastAppState::new (ClipsState).
    // transcripts removed in Step 5b — now seeded inside PodcastAppState::new (TranscriptsState).
    // agent_tasks removed in Step 6 — now seeded inside PodcastAppState::new (TasksState).
    // dismissed_episode_ids, inbox_triage_cache, inbox_triage_in_progress removed in Step 7 —
    // now seeded inside PodcastAppState::new (InboxState).
    // podcast_keys and publish_state removed in Step 13 —
    // now seeded inside PodcastAppState::new (PublishState).
    // voice_state and voice_conversation removed in Step 12 —
    // now seeded inside PodcastAppState::new via VoiceSubstate::new (with real app ptr).
    // conversation, agent_busy, agent_touched removed in Step 11 —
    // now seeded inside PodcastAppState::new (AgentChatState).
    // categories and categorization_in_progress removed in Step 4 —
    // they are now seeded inside PodcastAppState::new (CategoriesState).
    // comments_cache, viewed_comments_episode_id removed in Step 8 —
    // they are now owned by PodcastAppState::comments (CommentsState).
    // social, agent_notes removed in Steps 9-10 —
    // they are now owned by PodcastAppState::social (SocialState).
    // Install the host-op handler (requires &self, so take the ref AFTER the
    // &mut borrow above is released by the block end).
    let app_ref = unsafe { &*app };
    // Step N+1: rev + runtime are constructed here and bundled into Infra;
    // signal is also wired here and stored in infra.signal.  Neither is a
    // separate local variable anymore — the Infra is the canonical owner.
    //
    // Start at 1 so the first snapshot delivery always triggers an iOS update
    // (guard is `update.rev > last_seen_rev`; last_seen_rev starts at 0).
    let rev = std::sync::Arc::new(std::sync::atomic::AtomicU64::new(1));
    let snapshot_signal = SnapshotUpdateSignal::new(rev.clone(), app_ref.actor_sender());

    // Feedback runtime DROPPED (nmp-feedback#3 / podcast-player#597): the
    // dependency has no rev past the nmp-ffi deletion. Re-integration (its
    // construction, relay seed, and observer) is deferred to a follow-up slice.

    // Steps 0-N+1 — composed state root.
    // `Infra` bundles rev + signal + runtime.  `PodcastAppState::new`
    // seeds each substate's slots internally.  Both seams receive ONE Arc
    // clone; no separate Arcs needed in register.rs.
    //
    // Step N+1: runtime is the LAST local Infra component; constructed here
    // and moved into Infra rather than stored as a separate `let runtime`.
    // Step 11: AgentChatState::new reads `infra.signal` to wire the snapshot
    // signal into its inner AgentChatHandler automatically.
    // Step 12: VoiceSubstate is constructed with null app by default inside
    // new_with_identity; replaced with the real app pointer below before
    // sealing into Arc.
    // Step 16: FeedFetchCoordinator is now constructed inside new_with_identity
    // (accesses picks + categories built there); FeedbackRuntime is injected.
    let app_state_infra = Infra {
        rev: rev.clone(),
        signal: Some(snapshot_signal.clone()),
        runtime: std::sync::Arc::new(
            tokio::runtime::Builder::new_multi_thread()
                .thread_name("podcast-tokio")
                .enable_all()
                .build()
                .expect("tokio runtime"),
        ),
        domain_revs: std::sync::Arc::new(crate::state::DomainRevs::new()),
        // Root infra defaults to Misc; each substate receives a domain-scoped
        // clone via `infra.with_domain(...)` inside PodcastAppState::new_with_identity.
        domain: crate::state::Domain::Misc,
    };
    // Steps 8-10: pass the shared identity Arc so CommentsState / SocialState
    // can access it without needing a separate clone in register.rs.
    let mut app_state_inner = PodcastAppState::new_with_identity(
        app_state_infra.clone(),
        store.clone(),
        identity.clone(),
    );
    // Step 12: Replace the default null-app VoiceSubstate with one that holds
    // the live `app` pointer so `VoiceConversationManager` can dispatch
    // `VoiceCommand::Speak` back to the iOS TTS executor.
    app_state_inner.voice = crate::state::voice::VoiceSubstate::new(
        app_state_infra.with_domain(crate::state::Domain::Voice),
        store.clone(),
        app,
    );

    // ── Kernel-owned task scheduler tick (D9 / D13) ───────────────────────────
    //
    // Spawn the periodic 60-second due-task check NOW — after the real `app`
    // pointer is available and before `app_state_inner` is sealed into `Arc`.
    // The ticker captures `app` (wrapped as a `usize` for Send) and runs for
    // the lifetime of the Tokio runtime (dropped with the handle).
    //
    // Slice 2 will delete the iOS / Android host foreground poll paths
    // (`AppStateStore.runDueScheduledTasksIfNeeded` / Android `TaskRunDuePayload`);
    // until then both paths are idempotent — whichever reaches `run_task_by_id`
    // first advances `next_run_at`, and the other finds no due tasks.
    app_state_inner.tasks.start_ticker(app);

    // ── Reactive social-graph trust set ──────────────────────────────────────
    //
    // ActiveFollowSet (nmp-nip02): observes kind:3 events and maintains a live
    // BTreeSet<hex-pubkey> for the active account's follow list.  Its predicate
    // (`ActiveFollowSet::predicate()`) is a closure that captures the same
    // Arc<RwLock<…>> so consumers always see the latest kind:3 — no re-wiring.
    //
    // Constructed BEFORE sealing `app_state` so the SAME Arc can be injected
    // into SocialState (the projection recomputes `trusted` live against it)
    // AND registered as an ObservedProjectionSink below. Because the trust
    // verdict is recomputed at projection time, observer-registration order no
    // longer matters for correctness.
    //
    // `ActiveFollowSet::new` now also takes a `LatestKind3FollowSet` — the
    // store-backed latest-kind:3 reader (the same canonical event-store source
    // `FollowListProjection` reads below), replacing the deleted
    // `ContactsLookup` observer-local cache.
    let active_follow_set = ActiveFollowSet::new(
        app_ref.active_account_handle(),
        LatestKind3FollowSet::new(app_ref.event_store_handle()),
    );

    // NOTE: outbound_turn_cache is constructed and seeded from disk below,
    // AFTER data_dir is bound. We keep a placeholder empty Arc here so the
    // social state has a slot to share immediately; the actual disk load
    // happens in data_dir.rs (nmp_app_podcast_set_data_dir). The Arc<Mutex>
    // is shared with AgentNotesObserver so the observer can persist turns.
    let outbound_turn_cache = Arc::new(std::sync::Mutex::new(OutboundTurnCache::new()));

    // Approved-peer store: kernel-owned approve/block allow-list.
    // Constructed empty here; seeded from disk in data_dir.rs after the data
    // dir is bound. The same Arc is injected into SocialState (trust predicate)
    // AND stored on PodcastHandle (so data_dir.rs can seed it after load).
    let approved_peer_store = Arc::new(std::sync::Mutex::new(ApprovedPeerStore::new()));

    // Inject the live follow set AND the approved-peer store into SocialState
    // so trust_predicate() computes `(followed || approved) && !blocked` at
    // projection time (not frozen at receipt). Mirrors the `voice`
    // field-replacement pattern above: the fresh substate's slots are the
    // ones observers `.share()` from below.
    app_state_inner.social =
        crate::state::social::SocialState::new(app_state_inner.social.infra.clone())
            .with_follow_set(Arc::clone(&active_follow_set))
            .with_approved_peers(Arc::clone(&approved_peer_store));

    let app_state = Arc::new(app_state_inner);

    // ── Agent-note auto-responder cache ──────────────────────────────────────
    //
    // Shared between the handle (where `data_dir.rs` restores persisted state)
    // and the `AgentNotesObserver` (which checks + updates it on each reply).
    // The `Arc` is cheap to clone; the inner `Mutex` protects access between
    // the observer thread and the data_dir restore call.
    let responder_cache = Arc::new(Mutex::new(ResponderCache::default()));
    // Outbound-turn cache is also shared between the handle (data_dir.rs seeding)
    // and the AgentNotesObserver (append after publish). The social state's
    // outbound_turns slot is shared via .share() so the in-memory projection
    // sees new turns immediately. The disk cache keeps turns across restarts.
    // Step 16: feed_fetch is now app_state.feed_fetch; no local variable needed.

    // Seed the podcast app's default relay set for a fresh install (the iOS
    // shell constructs over the raw C-ABI, bypassing the builder's default
    // seed). See `register_composition::seed_default_relays` for the
    // SEED-IF-EMPTY rationale and persistence-override interaction.
    super::register_composition::seed_default_relays(app_ref);

    // Steps 8-10: comments_cache, viewed_comments_episode_id, nostr_results,
    // Steps 8-10: search_results, social, agent_notes removed from constructor.
    // Step 11: agent_chat removed — now owned by state.agent_chat (AgentChatState).
    // Step 12: voice_state removed — now owned by state.voice (VoiceSubstate).
    // Step 13: podcast_keys + publish_state removed — now owned by state.publish (PublishState).
    // Step 7: dismissed_episode_ids, inbox_triage_cache, inbox_triage_in_progress removed —
    // now owned by state.inbox (InboxState).
    // Step 14: player_actor/queue/download_queue removed from constructor —
    // now owned by app_state.playback (PlaybackState).
    // Step N+1: handler now takes only (app, state) — all infra is in state.infra.
    app_ref.set_host_op_handler(Arc::new(PodcastHostOpHandler::new(app, app_state.clone())));

    // NIP-F4 discovery observer (canonical EnsureInterest + ObservedProjectionSink
    // pattern). The `podcast.discover_nostr` action emits
    // `ActorCommand::Interests(InterestsCommand::EnsureInterest)` for `kind:10154`;
    // NMP core opens the subscription through its own relay pool (no iOS
    // WebSocket — D7) and every inbound show event fires this observer, which
    // writes the projected show onto the same `nostr_results` slot the
    // snapshot reads. Registered before the slot Arcs are moved into the
    // handle. The returned id is dropped: the observer lives for the app's
    // lifetime (mirrors the snapshot projection), and `nmp_app_free` joins the
    // actor before dropping the slot.
    // Step 9: observer shares from state.discovery.nostr_results (removes the
    // dead-duplicate handler Arc from PodcastHostOpHandler.nostr_results).
    // Step N+1: observers use infra clones from app_state rather than separate locals.
    //
    // Observed-projection shape (mirrors this observer's prior interest scope): `from_kinds` declares a Global, kind:10154-only shape (no
    // author filter — discovery is a browse across all published shows),
    // mirroring the `nostr_discovery_interest()` sweep this observer already
    // consumes historical shows from.
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
    // subscriptions opened by handle_fetch_comments. No iOS WebSocket.
    // Step 8: observer shares cache from state.comments.cache (removes the
    // dead-duplicate handler Arc from PodcastHostOpHandler.comments_cache).
    //
    // Observed-projection shape (mirrors this observer's prior interest scope): `from_kinds` declares a Global, kind:1111-only shape (comments
    // are anchored by episode `#i` tag, not by account) — the observer itself
    // already narrows to the anchor it cares about per inbound event.
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
    // `active_follow_set` was constructed above (before sealing `app_state`)
    // and injected into SocialState. Here it is registered as an
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
        let afs = Arc::clone(&active_follow_set);
        let state_for_switch = app_state.clone();
        app_ref.register_identity_change_observer(move |_| {
            afs.notify_account_changed();
            state_for_switch.social.clear_for_account_switch();
        });
    }
    // Clone as the concrete type, then let the fn-arg position coerce
    // Arc<ActiveFollowSet> → Arc<dyn ObservedProjectionSink> (unsizing).
    //
    // Observed-projection shape (mirrors this observer's prior interest scope): `from_kinds` declares an ActiveAccount-scoped, kind:3-only
    // shape — `ActiveFollowSet::on_kernel_event` itself gates on
    // `event.author == active account`, so an unrelated kind:3 is a cheap
    // no-op rather than a filter miss.
    let _follow_set_observer_id = app_ref.open_observed_projection(ObservedProjection::from_kinds(
        active_follow_set.clone(),
        "podcast.social.active_follow_set",
        0, // ActiveAccount — re-routes to the new account's kind:3 on switch.
        [3u32],
        16,
    ));

    // FollowListObserver: materialises a SocialSnapshot from the inner
    // FollowListProjection on every kind:3 push frame and writes it to
    // state.social.social_slot.  Uses the kernel's standing
    // account_profile_interest subscription (kind:0 + kind:3 + kind:10002) —
    // no extra relay subscription needed.
    //
    // `with_social_infra` wires the Domain::Social-scoped Infra so every
    // kind:3 mutation bumps `domain_revs.social` (driving the podcast.social
    // sidecar re-emit) AND the global rev/signal.  Mirrors the same wiring
    // applied to AgentNotesObserver below.
    //
    // `FollowListProjection` (the observer's inner read-model) is now a thin
    // read-model over the canonical event store via `LatestKind3FollowSet`
    // (replaces the deleted `ContactsLookup` observer-local cache — see
    // `active_follow_set` construction above for the same replacement).
    //
    // Observed-projection shape (mirrors this observer's prior interest scope): `from_kinds` declares the same ActiveAccount-scoped kind:3
    // shape as `active_follow_set` above.
    let _follow_list_observer_id = app_ref.open_observed_projection(ObservedProjection::from_kinds(
        std::sync::Arc::new(
            crate::social_handler::FollowListObserver::new(
                app_ref.active_account_handle(),
                LatestKind3FollowSet::new(app_ref.event_store_handle()),
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
    // subscriptions opened by handle_fetch_agent_notes. No iOS WebSocket.
    // It caches raw notes (author hex retained, NO trust stamp); the trust
    // verdict is recomputed live at projection time in SocialState against the
    // shared ActiveFollowSet (so follow/unfollow flips existing notes).
    //
    // `with_responder` wires the auto-responder: when a trusted note lands, the
    // observer calls `agent_note_responder::try_respond_to_trusted_note`, which
    // spawns an async LLM-reply + publish task off the actor thread (D8).
    //
    // Observed-projection shape (mirrors this observer's prior interest scope): `from_kinds` declares a Global, kind:1-only shape — matching
    // `agent_notes_interest`'s own `InterestScope::Global` (the `#p`-tag
    // filter on the active pubkey is baked into the `LogicalInterest` that
    // `handle_fetch_agent_notes` pushes, not into the account-switch scope).
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
                Arc::clone(&active_follow_set),
                Arc::clone(&approved_peer_store),
                store.clone(),
                Arc::clone(&responder_cache),
                Arc::clone(&outbound_turn_cache),
                app_state.social.outbound_turns.share(),
                app_state.infra.runtime.clone(),
            ),
        ),
        "podcast.social.agent_notes_observer",
        1, // Global — the `#p`-tag filter is baked into the pushed interest.
        [1u32],
        64,
    ));

    // In-app feedback observer DROPPED with nmp-feedback (nmp-feedback#3);
    // re-added when feedback re-integration lands.

    // Step N+1: PodcastHandle is now the minimal 2-field shell:
    //   app  — raw *mut NmpApp for capability dispatch
    //   state — Arc<PodcastAppState> (the entire tree)
    //   snapshot_cache + clean_html_cache — perf caches owned by the handle
    //
    // Everything else (rev, signal, runtime, store, identity, feedback,
    // feed_fetch, player, queue, …) is accessed via state.infra.* /
    // state.library.* / state.playback.* etc.
    let handle = Arc::new(PodcastHandle {
        app,
        state: app_state,
        responder_cache,
        outbound_turn_cache,
        approved_peer_store,
        ask_state: Arc::new(Mutex::new(super::agent_ask::AgentAskState::default())),
        ask_callback: Arc::new(Mutex::new(super::agent_ask::AgentAskCallbackState::default())),
        snapshot_cache: Arc::new(Mutex::new(None)),
        clean_html_cache: Arc::new(Mutex::new(std::collections::HashMap::new())),
    });

    // Per-domain typed snapshot projections (perf/domain-sub-projections-kernel).
    //
    // Each closure runs on the actor thread on every tick (D8 — non-blocking).
    // It reads the domain's `Arc<AtomicU64>` rev and compares against its own
    // `last_emitted`; if unchanged, returns `None` so the sidecar is omitted
    // from the frame entirely — true push-side delta semantics.
    //
    // The Tier-3 encoder carries typed sidecars verbatim. The shell decodes them
    // via `nmp_app_podcast_decode_update_frame`, which injects every `podcast.*`
    // sidecar into `v.projections[key]` — available for future Swift/Android
    // consumption without touching the pull path.
    //
    // The PULL path (`nmp_app_podcast_snapshot` / `build_snapshot_payload`) is
    // kept intact as cold-start hydration + fallback.
    super::snapshot_domain_projections::register_domain_projections(app_ref, &handle);

    // Ownership: one strong ref is returned to the shell as the opaque handle
    // pointer; the projection closure above holds a second strong ref for the
    // app's lifetime. `nmp_app_podcast_unregister` reclaims the shell's ref via
    // `Arc::from_raw`. `nmp_app_free` joins the actor thread before dropping, so
    // no projector call is in flight after teardown. The handle is only ever
    // borrowed shared across the FFI (no `&mut`), so `Arc` aliasing is sound.
    Arc::into_raw(handle) as *mut PodcastHandle
    }) // ffi_guard
}
