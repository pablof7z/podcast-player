//! Composition-root helpers for [`super::register::nmp_app_podcast_register`].
//!
//! Extracted from `register.rs` (500-line file-size ceiling). Holds the two
//! self-contained setup steps `register` delegates to:
//!
//! * [`install_protocol_composition`] — the protocol-installer surface ADR-0069
//!   moved off the deleted `register_defaults`.
//! * [`seed_default_relays`] — the app's default relay set for a fresh install.

use nmp_native_runtime::NmpApp;

use super::actions::agent_module::AgentActionModule;
use super::actions::categorization_module::CategorizationModule;
use super::actions::chapters_module::ChaptersActionModule;
use super::actions::clip_module::ClipActionModule;
use super::actions::identity_module::IdentityActionModule;
use super::actions::inbox_module::InboxActionModule;
use super::actions::knowledge_module::KnowledgeActionModule;
use super::actions::memory_module::MemoryActionModule;
use super::actions::picks_module::AgentPicksModule;
use super::actions::player_module::PlayerActionModule;
use super::actions::podcast_module::PodcastActionModule;
use super::actions::publish_module::NipF4PublishModule;
use super::actions::queue_module::QueueActionModule;
use super::actions::settings_module::SettingsActionModule;
use super::actions::siri_module::SiriActionModule;
use super::actions::social_module::SocialActionModule;
use super::actions::tasks_module::AgentTasksModule;
use super::actions::voice_module::VoiceActionModule;

/// Wire the canonical NMP composition onto `app_mut`.
///
/// ADR-0069: the old `register_defaults` composition root is deleted. This
/// composes the same protocol surface it provided as explicit installers: the
/// NMP substrate (routing, blocked-relay lookup, publish resolver,
/// coverage/NIP-77 interceptors, NIP-11) + the per-crate protocol registers
/// (NIP-02 follow/unfollow + FollowListProjection, NIP-25 react/unreact, NIP-17
/// DM send/relay-list + DmRelayCache/DmInboxRelayLookup, NIP-57 zap, NIP-51
/// bookmarks/mute, WoT trust bootstrap, BUD-02 Blossom upload) + the podcast
/// action modules. The Swift shell dispatches these `nmp.*` / `podcast.*`
/// namespaces, so they must be registered or those dispatches fail closed.
pub(super) fn install_protocol_composition(app_mut: &mut NmpApp) {
    let _substrate = nmp_substrate::install(app_mut, nmp_substrate::SubstrateConfig::default());

    nmp_nip02::register(app_mut, nmp_nip02::Config::default())
        .expect("nmp-nip02 registration must not collide");
    nmp_nip25::register(app_mut, nmp_nip25::Config::default())
        .expect("nmp-nip25 registration must not collide");
    nmp_nip17::register(app_mut, nmp_nip17::Config::default())
        .expect("nmp-nip17 registration must not collide");
    nmp_nip57::register(app_mut, nmp_nip57::Config::default())
        .expect("nmp-nip57 registration must not collide");
    nmp_nip51::register(
        app_mut,
        nmp_nip51::Config {
            search_fallback_relays: nmp_nip50::SearchFallbackRelays::default(),
        },
    )
    .expect("nmp-nip51 registration must not collide");
    nmp_wot::register(app_mut, nmp_wot::Config::default())
        .expect("nmp-wot registration must not collide");

    // BUD-02 Blossom upload action (`nmp.blossom.upload`). D13/D0: Rust owns the
    // full Build → Sign → Transport pipeline; Swift dispatches with a
    // correlation-id and reads the BlobDescriptor from action_results on the
    // next push frame.
    nmp_blossom::register(app_mut, nmp_blossom::Config::default())
        .expect("nmp-blossom registration must not collide");

    app_mut.register_action(IdentityActionModule).expect("action module registration must not collide");
    app_mut.register_action(PodcastActionModule).expect("action module registration must not collide");
    app_mut.register_action(PlayerActionModule).expect("action module registration must not collide");
    app_mut.register_action(QueueActionModule).expect("action module registration must not collide");
    app_mut.register_action(ChaptersActionModule).expect("action module registration must not collide");
    app_mut.register_action(AgentPicksModule).expect("action module registration must not collide");
    app_mut.register_action(AgentTasksModule).expect("action module registration must not collide");
    app_mut.register_action(KnowledgeActionModule).expect("action module registration must not collide");
    app_mut.register_action(MemoryActionModule).expect("action module registration must not collide");
    app_mut.register_action(ClipActionModule).expect("action module registration must not collide");
    app_mut.register_action(InboxActionModule).expect("action module registration must not collide");
    app_mut.register_action(NipF4PublishModule).expect("action module registration must not collide");
    app_mut.register_action(VoiceActionModule).expect("action module registration must not collide");
    app_mut.register_action(AgentActionModule).expect("action module registration must not collide");
    app_mut.register_action(CategorizationModule).expect("action module registration must not collide");
    app_mut.register_action(SettingsActionModule).expect("action module registration must not collide");
    app_mut.register_action(SiriActionModule).expect("action module registration must not collide");
    app_mut.register_action(SocialActionModule).expect("action module registration must not collide");
}

/// Seed the podcast app's default relay set (NMP v0.2.1, PR #900).
///
/// As of v0.2.1 `nmp-core` no longer carries a hardcoded onboarding relay
/// default — the app owns its relay list. The Rust composition root
/// (`NmpAppBuilder::start`) seeds `DEFAULT_APP_RELAYS` for builder-based apps,
/// but the podcast app is constructed by the iOS shell over the raw C-ABI
/// (`nmp_app_new` → `nmp_app_podcast_register` → `nmp_app_start`), so it never
/// runs through the builder. Without an explicit seed a fresh install would
/// start with ZERO configured relays and Nostr discovery / publish would
/// silently no-op. `set_initial_relays_for_start` is the non-builder seam: it
/// stages `(url, role)` rows into `ActorCommand::Start { initial_relays }`,
/// read once by the actor before the first tick. It takes `&self`, so it is
/// sound on `app_ref`, and it MUST run before the shell calls `nmp_app_start`.
///
/// SEED-IF-EMPTY — investigated, intentionally still unconditional. At
/// `register` time the `configured_relays` slot is ALWAYS empty: the actor only
/// populates it from `initial_relays` when it handles `ActorCommand::Start`,
/// which runs AFTER `register` returns. The persistence load in `data_dir.rs`
/// also runs before `Start` and calls `set_initial_relays_for_start` — if it
/// finds saved relays, the persisted list wins (staged last, `Start` takes the
/// final staged value). So on subsequent launches the persistence load
/// overrides this seed; on a truly fresh install the sidecar is absent and this
/// seed provides the correct defaults.
pub(super) fn seed_default_relays(app_ref: &NmpApp) {
    app_ref.set_initial_relays_for_start(vec![
        (
            "wss://relay.primal.net".to_string(),
            "both,indexer".to_string(),
        ),
        ("wss://purplepag.es".to_string(), "indexer".to_string()),
        // The in-app feedback source relay seed was dropped with nmp-feedback
        // (nmp-feedback#3); re-added when feedback re-integration lands.
    ]);
}
