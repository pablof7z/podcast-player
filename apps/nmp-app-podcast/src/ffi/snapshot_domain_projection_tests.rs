//! Tests for per-domain typed snapshot projections.
//!
//! Key assertions per the task spec:
//!  - Frame round-trips: each domain closure emits valid `TypedProjectionData`
//!  - Delta proof: a playback-rev bump emits ONLY the `podcast.playback` sidecar
//!    (library, settings, identity, widget, misc closures return `None`)
//!  - Decoder: `decode_podcast_domain_sidecars` correctly filters and parses
//!  - `last_emitted` guard: a second call with the same domain rev → `None`
//!  - `DomainRevs::new()` starts all counters at 1
//!  - `infra.bump_domain` advances both the domain rev and the global rev

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use nmp_core::{encode_snapshot_frame, SnapshotEnvelope, TypedProjectionData};

use crate::ffi::handle::PodcastHandle;
use crate::ffi::snapshot_domain_projections::{
    decode_podcast_domain_sidecars, register_domain_projections, SCHEMA_DOWNLOADS,
    SCHEMA_IDENTITY, SCHEMA_LIBRARY, SCHEMA_MISC, SCHEMA_PLAYBACK, SCHEMA_SETTINGS, SCHEMA_WIDGET,
};
use crate::state::{Domain, DomainRevs, Infra, PodcastAppState};
use crate::store::PodcastStore;

// ── Test helpers ──────────────────────────────────────────────────────────────

/// Make a handle with a real (unstarted) `NmpApp` so `build_configured_relays`
/// does not deref a null pointer. The caller is responsible for freeing `app`
/// after dropping the handle.
fn make_test_handle_with_app(app: *mut nmp_ffi::NmpApp) -> Box<PodcastHandle> {
    let store = Arc::new(Mutex::new(PodcastStore::new()));
    let state = Arc::new(PodcastAppState::new(
        Infra::for_test(),
        store.clone(),
    ));
    // Clear agent_tasks (default seed uses Uuid::new_v4 — non-deterministic).
    state.tasks.tasks.lock().unwrap().clear();

    Box::new(PodcastHandle {
        app,
        state,
        snapshot_cache: Arc::new(Mutex::new(None)),
        clean_html_cache: Arc::new(Mutex::new(HashMap::new())),
    })
}

fn make_frame_with_sidecars(sidecars: &[TypedProjectionData]) -> Vec<u8> {
    let env = SnapshotEnvelope {
        rev: 1,
        running: true,
        ..SnapshotEnvelope::default()
    };
    encode_snapshot_frame(&env, sidecars)
}

// ── DomainRevs construction ───────────────────────────────────────────────────

/// `DomainRevs::new` starts all counters at 1 so the first emit always fires.
#[test]
fn domain_revs_start_at_one() {
    let dr = DomainRevs::new();
    assert_eq!(dr.library.load(Ordering::Relaxed), 1);
    assert_eq!(dr.playback.load(Ordering::Relaxed), 1);
    assert_eq!(dr.downloads.load(Ordering::Relaxed), 1);
    assert_eq!(dr.settings.load(Ordering::Relaxed), 1);
    assert_eq!(dr.identity.load(Ordering::Relaxed), 1);
    assert_eq!(dr.widget.load(Ordering::Relaxed), 1);
    assert_eq!(dr.misc.load(Ordering::Relaxed), 1);
}

/// `infra.bump_domain_explicit` advances both the named domain rev and the
/// global rev.
#[test]
fn bump_domain_explicit_advances_both_revs() {
    let infra = Infra::for_test();
    let initial_global = infra.rev.load(Ordering::Relaxed);
    let initial_domain = infra.domain_revs.library.load(Ordering::Relaxed);

    infra.bump_domain_explicit(Domain::Library);

    assert_eq!(
        infra.domain_revs.library.load(Ordering::Relaxed),
        initial_domain + 1,
        "named domain rev must have incremented by 1"
    );
    assert!(
        infra.rev.load(Ordering::Relaxed) > initial_global,
        "global rev must also advance after bump_domain_explicit"
    );
}

/// A `Domain`-scoped `Infra`'s bare `bump()` routes to that domain's rev.
#[test]
fn scoped_bump_routes_to_domain_rev() {
    let infra = Infra::for_test().with_domain(Domain::Playback);
    let initial_playback = infra.domain_revs.playback.load(Ordering::Relaxed);
    let initial_library = infra.domain_revs.library.load(Ordering::Relaxed);

    infra.bump();

    assert_eq!(
        infra.domain_revs.playback.load(Ordering::Relaxed),
        initial_playback + 1,
        "scoped bump() must advance the playback domain rev"
    );
    assert_eq!(
        infra.domain_revs.library.load(Ordering::Relaxed),
        initial_library,
        "scoped bump() must NOT advance an unrelated domain rev"
    );
}

// ── Decoder: decode_podcast_domain_sidecars ───────────────────────────────────

/// A frame with no `podcast.*` sidecars yields `None` (D6 — degrade silently).
#[test]
fn decode_absent_sidecars_yields_none() {
    let frame = make_frame_with_sidecars(&[]);
    assert!(
        decode_podcast_domain_sidecars(&frame).is_none(),
        "frame without podcast.* sidecars must yield None"
    );
}

/// A frame with a `podcast.playback` sidecar carrying valid JSON is decoded
/// into a map entry keyed by `"podcast.playback"`.
#[test]
fn decode_podcast_playback_sidecar_is_extracted() {
    let payload = serde_json::json!({ "rev": 42u64, "now_playing": null, "queue": [] });
    let payload_bytes = serde_json::to_vec(&payload).unwrap();
    let sidecar = TypedProjectionData {
        key: SCHEMA_PLAYBACK.to_string(),
        schema_id: SCHEMA_PLAYBACK.to_string(),
        schema_version: 1,
        file_identifier: String::new(),
        payload: payload_bytes,
    };
    let frame = make_frame_with_sidecars(&[sidecar]);
    let map = decode_podcast_domain_sidecars(&frame)
        .expect("frame with podcast.playback sidecar must yield Some");
    assert!(
        map.contains_key(SCHEMA_PLAYBACK),
        "decoded map must contain podcast.playback; keys: {:?}",
        map.keys().collect::<Vec<_>>()
    );
    assert_eq!(
        map[SCHEMA_PLAYBACK]["rev"],
        serde_json::json!(42u64),
        "decoded rev must match payload"
    );
}

/// Non-`podcast.*` sidecars are not included in the decoded map.
#[test]
fn decode_ignores_non_podcast_sidecars() {
    let other_payload = serde_json::to_vec(&serde_json::json!({ "data": "irrelevant" })).unwrap();
    let other_sidecar = TypedProjectionData {
        key: "signed_events".to_string(),
        schema_id: "nmp.signedEvents".to_string(),
        schema_version: 1,
        file_identifier: "KSEV".to_string(),
        payload: other_payload,
    };
    let frame = make_frame_with_sidecars(&[other_sidecar]);
    assert!(
        decode_podcast_domain_sidecars(&frame).is_none(),
        "non-podcast.* sidecars must not appear in the podcast domain decoder output"
    );
}

/// A sidecar with malformed (non-JSON) payload is silently skipped (D6).
#[test]
fn decode_malformed_sidecar_payload_is_silently_skipped() {
    let bad = TypedProjectionData {
        key: SCHEMA_LIBRARY.to_string(),
        schema_id: SCHEMA_LIBRARY.to_string(),
        schema_version: 1,
        file_identifier: String::new(),
        payload: b"not json {{{".to_vec(),
    };
    let frame = make_frame_with_sidecars(&[bad]);
    // The single sidecar has a bad payload; the map ends up empty → None (D6).
    assert!(
        decode_podcast_domain_sidecars(&frame).is_none(),
        "malformed podcast.* sidecar payload must be silently skipped (D6)"
    );
}

// ── Delta proof: playback bump excludes library ───────────────────────────────

/// Core delta assertion from the task spec:
/// "playback-tick frame EXCLUDES the library sidecar".
///
/// When only `domain_revs.playback` is bumped (simulating a playback tick),
/// the library closure's `last_emitted` matches `domain_revs.library`, so
/// the library sidecar is absent from the frame.
#[test]
fn playback_tick_excludes_library_sidecar() {
    let app = nmp_ffi::nmp_app_new();
    assert!(!app.is_null(), "nmp_app_new must succeed");
    let app_ref = unsafe { &*app };

    let handle = Arc::new(*make_test_handle_with_app(app));
    let domain_revs = Arc::clone(&handle.state.infra.domain_revs);

    register_domain_projections(app_ref, &handle);

    // First call: all domain revs start at 1, all last_emitted start at 0 →
    // most closures fire. Run to consume the initial state.
    let _ = app_ref.run_typed_snapshot_projections();

    // Second call without any rev bump → ALL closures return None (no change).
    let no_change = app_ref.run_typed_snapshot_projections();
    assert!(
        no_change.is_empty(),
        "second run with no domain rev bump must emit nothing (all closures return None); got {:?}",
        no_change.iter().map(|p| p.schema_id.as_str()).collect::<Vec<_>>()
    );

    // Bump only the playback domain rev.
    domain_revs.playback.fetch_add(1, Ordering::Relaxed);

    // Third call → only podcast.playback is emitted; library is absent.
    let after_playback_bump = app_ref.run_typed_snapshot_projections();
    let keys_after: Vec<&str> = after_playback_bump
        .iter()
        .map(|p| p.schema_id.as_str())
        .collect();

    assert!(
        keys_after.contains(&SCHEMA_PLAYBACK),
        "podcast.playback must be emitted after playback domain bump; got {keys_after:?}"
    );
    assert!(
        !keys_after.contains(&SCHEMA_LIBRARY),
        "podcast.library must NOT be in the frame after a playback-only bump (delta proof); got {keys_after:?}"
    );
    assert!(
        !keys_after.contains(&SCHEMA_SETTINGS),
        "podcast.settings must NOT be in the frame after a playback-only bump; got {keys_after:?}"
    );

    drop(handle);
    unsafe { drop(Box::from_raw(app)) };
}

// ── Per-domain round-trip: sidecars carry valid JSON ─────────────────────────

/// Each domain sidecar (when emitted) carries a JSON payload that includes
/// a `rev` field and the domain-specific data keys.
#[test]
fn domain_projections_emit_valid_json_with_rev_field() {
    let app = nmp_ffi::nmp_app_new();
    assert!(!app.is_null(), "nmp_app_new must succeed");
    let app_ref = unsafe { &*app };

    let handle = Arc::new(*make_test_handle_with_app(app));
    register_domain_projections(app_ref, &handle);

    // First call emits everything (all domain revs start at 1, last_emitted at 0).
    let projections = app_ref.run_typed_snapshot_projections();

    // There may be 0 projections for downloads/identity/widget (they return None
    // when empty). settings, playback, and misc must always be present.
    let by_key: std::collections::HashMap<String, &TypedProjectionData> = projections
        .iter()
        .map(|p| (p.schema_id.clone(), p))
        .collect();

    for (key, entry) in &by_key {
        let value: serde_json::Value = serde_json::from_slice(&entry.payload)
            .unwrap_or_else(|e| panic!("domain {key} sidecar must be valid JSON: {e}"));
        assert!(
            value.get("rev").is_some(),
            "domain {key} payload must carry a 'rev' field"
        );
    }

    // settings must always be present (non-optional payload).
    assert!(
        by_key.contains_key(SCHEMA_SETTINGS),
        "podcast.settings must be emitted on initial run; got: {:?}",
        by_key.keys().collect::<Vec<_>>()
    );
    // playback must always be present.
    assert!(
        by_key.contains_key(SCHEMA_PLAYBACK),
        "podcast.playback must be emitted on initial run; got: {:?}",
        by_key.keys().collect::<Vec<_>>()
    );
    // misc must always be present.
    assert!(
        by_key.contains_key(SCHEMA_MISC),
        "podcast.misc must be emitted on initial run; got: {:?}",
        by_key.keys().collect::<Vec<_>>()
    );

    drop(handle);
    unsafe { drop(Box::from_raw(app)) };
}
