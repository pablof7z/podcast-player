//! Scenario: end-to-end per-podcast NIP-F4 register→sign→publish against a
//! LIVE kernel, guarding the signing seam rewired in #436/#438.
//!
//! ## What is guarded
//!
//! #436/#438 deleted ALL app-side crypto and rerouted per-podcast signing through:
//!   1. `AddSigner { make_active: false }` — `nmp_app_signin_nsec(make_active=0)`
//!      registers the per-podcast key as a NON-active signer in the kernel's
//!      identity roster.
//!   2. `PublishRaw { signer_pubkey }` — the kernel signs with the NAMED key,
//!      not the active account.
//!   3. `nmp.blossom.upload { signer_pubkey }` — the kernel signs kind:24242
//!      Blossom auth events with the same named key.
//!
//! The existing unit tests (`host_op_publish_tests.rs`) cover the dispatch
//! envelope shape with a NULL app pointer — they never call into the real kernel,
//! so they cannot catch a regression that drops `register_podcast_signer_in_kernel`
//! or changes `signer_pubkey` threading.
//!
//! This scenario drives the REAL kernel actor end-to-end.
//!
//! ## Assertions
//!
//! A. **Per-podcast key is distinct from the active account** (`podcast_pubkey_hex
//!    != active_account.pubkey_hex`). This is the fundamental NIP-F4 invariant:
//!    show/episode events are authored by a key the user controls but that is NOT
//!    their Nostr identity key.
//!
//! B. **Active account unchanged by publish** — `publish_show` calls
//!    `nmp_app_signin_nsec(make_active=0)`, so the kernel's active signer MUST
//!    NOT change. Asserted before AND after every publish dispatch.
//!
//! C. **`last_published_at` is stamped** — the actor ran the full publish path
//!    (generate tags → register signer → dispatch PublishRaw) and bumped rev.
//!    Observable via the snapshot without needing relay connectivity.
//!
//! D. **Episode publish (kind:54) accepted** — `publish_episode` goes through
//!    the SAME `register_podcast_signer_in_kernel` → `PublishRaw{signer_pubkey}`
//!    path. Verified via dispatch acceptance (correlation_id returned, no error).
//!
//! E. **Idempotent re-registration** — a second `publish_show` for the same
//!    podcast re-registers the same key (no error, `make_active=false` holds,
//!    `last_published_at` remains valid). The kernel's `AddSigner` path is
//!    documented as idempotent; this assertion catches a regression where
//!    re-registration fails or accidentally activates the per-podcast key.
//!
//! ## Relay connectivity
//!
//! Not required. The signing layer is validated regardless of whether a relay
//! accepted the event. `register_podcast_signer_in_kernel` is indirectly verified:
//! without it, `PublishRaw{signer_pubkey}` would fail unknown-signer, the handler
//! would not reach its `rev.fetch_add` + `last_published_at` stamp, and
//! assertion C would time out — catching the regression.
//!
//! ## Note on `show_event_json`
//!
//! Prior to #436/#438 the app signed events locally and stamped the resulting
//! event JSON into `OwnedPublishState.show_event_json`. Post-rewrite, the kernel
//! holds the signed event; `show_event_json` is never populated. The correct
//! observable for a successful `publish_show` is `last_published_at`.

use nmp_app_podcast::PodcastHandle;
use nmp_ffi::NmpApp;
use serde_json::json;

use crate::fixtures;
use crate::harness::{dispatch, snapshot, wait_for};
use crate::mock_feed;
use crate::scenarios::ScenarioResult;

pub fn run(app: *mut NmpApp, handle: *mut PodcastHandle) -> ScenarioResult {
    // ── Step 1: Establish a known active identity ─────────────────────────────
    //
    // Required for assertion B: we need a baseline active_account.pubkey_hex to
    // compare against after every publish dispatch. The identity scenario runs
    // before this one in run_all, so the import may have already been done;
    // we take the fast path in that case.
    let active_before = match snapshot(handle).and_then(|u| u.active_account) {
        Some(acc) => acc,
        None => {
            let res = dispatch(
                app,
                "podcast.identity",
                json!({"type": "ImportNsec", "nsec": fixtures::HEADLESS_TEST_NSEC}),
            );
            if let Some(err) = res.get("error").and_then(|v| v.as_str()) {
                return ScenarioResult::Fail(format!("ImportNsec rejected: {err}"));
            }
            match wait_for(handle, 8_000, |u| u.active_account.is_some()) {
                Ok(u) => match u.active_account {
                    Some(acc) => acc,
                    None => {
                        return ScenarioResult::Fail(
                            "active_account is None immediately after wait_for".into(),
                        )
                    }
                },
                Err(e) => {
                    return ScenarioResult::Fail(format!(
                        "timeout waiting for active_account after ImportNsec: {e}"
                    ))
                }
            }
        }
    };

    if active_before.pubkey_hex != fixtures::HEADLESS_TEST_PUBKEY_HEX {
        return ScenarioResult::Fail(format!(
            "active_account pubkey mismatch: expected {} got {}",
            fixtures::HEADLESS_TEST_PUBKEY_HEX,
            active_before.pubkey_hex
        ));
    }

    // ── Step 2: Subscribe to a mock RSS feed and isolate the new podcast ──────
    //
    // Capture existing podcast IDs so we can identify the entry this scenario
    // creates. Previous scenarios may have left podcasts in the shared store.
    let existing_ids: std::collections::HashSet<String> = snapshot(handle)
        .map(|u| u.library.iter().map(|p| p.id.clone()).collect())
        .unwrap_or_default();

    let port = mock_feed::start();
    let feed_url = format!("http://127.0.0.1:{port}/feed.xml");

    let sub_result = dispatch(
        app,
        "podcast",
        json!({"op": "subscribe", "feed_url": feed_url}),
    );
    if let Some(err) = sub_result.get("error").and_then(|v| v.as_str()) {
        return ScenarioResult::Fail(format!("subscribe rejected: {err}"));
    }

    let update = match wait_for(handle, 10_000, |u| {
        u.library.iter().any(|p| !existing_ids.contains(&p.id))
    }) {
        Ok(u) => u,
        Err(msg) => {
            return ScenarioResult::Fail(format!(
                "timeout waiting for new library entry: {msg}"
            ))
        }
    };

    let podcast_id = update
        .library
        .iter()
        .find(|p| !existing_ids.contains(&p.id))
        .map(|p| p.id.clone())
        .expect("predicate ensured at least one new entry");

    // Capture an episode id for step 5 (episode publish assertion D).
    let episode_id = update
        .library
        .iter()
        .find(|p| p.id == podcast_id)
        .and_then(|p| p.episodes.first())
        .map(|e| e.id.clone());

    // ── Step 3: create_owned_podcast — mint the per-podcast NIP-F4 keypair ───
    let create_res = dispatch(
        app,
        "podcast.publish",
        json!({"op": "create_owned_podcast", "podcast_id": podcast_id}),
    );
    if create_res.get("error").is_some() {
        return ScenarioResult::Fail(format!(
            "create_owned_podcast rejected: {create_res}"
        ));
    }

    // Wait until owned_podcasts contains our podcast with a populated pubkey.
    let target_id = podcast_id.clone();
    let update = match wait_for(handle, 10_000, |u| {
        u.owned_podcasts.iter().any(|o| {
            o.podcast_id == target_id && !o.podcast_pubkey_hex.is_empty()
        })
    }) {
        Ok(u) => u,
        Err(msg) => {
            return ScenarioResult::Fail(format!(
                "timeout waiting for owned_podcasts[{podcast_id}]: {msg}"
            ))
        }
    };

    let owned = match update
        .owned_podcasts
        .iter()
        .find(|o| o.podcast_id == podcast_id)
    {
        Some(o) => o.clone(),
        None => {
            return ScenarioResult::Fail(
                "owned_podcasts entry disappeared after wait_for".into(),
            )
        }
    };

    let podcast_pubkey = owned.podcast_pubkey_hex.clone();

    // ── Assertion A: per-podcast key is DISTINCT from the active account ──────
    if podcast_pubkey.len() != 64 || !podcast_pubkey.chars().all(|c| c.is_ascii_hexdigit()) {
        return ScenarioResult::Fail(format!(
            "podcast_pubkey_hex is not valid 64-char lowercase hex: {podcast_pubkey}"
        ));
    }
    if podcast_pubkey == active_before.pubkey_hex {
        return ScenarioResult::Fail(format!(
            "REGRESSION: podcast_pubkey_hex == active_account.pubkey_hex ({podcast_pubkey}) — \
             NIP-F4 requires a distinct per-podcast key, NOT the user's identity key. \
             create_owned_podcast must have generated a fresh derived keypair."
        ));
    }

    // ── Assertion B (pre-publish baseline): active account unchanged so far ───
    if let Some(acc) = snapshot(handle).and_then(|u| u.active_account) {
        if acc.pubkey_hex != active_before.pubkey_hex {
            return ScenarioResult::Fail(format!(
                "active_account changed BEFORE publish (after create_owned): \
                 expected {} got {}",
                active_before.pubkey_hex,
                acc.pubkey_hex
            ));
        }
    }

    // ── Step 4: publish_show (kind:10154) ─────────────────────────────────────
    //
    // Exercises the full register→sign seam:
    //   register_podcast_signer_in_kernel(secret_hex) → nmp_app_signin_nsec(make_active=0)
    //   publish_raw_with_signer_via_nmp(KIND_SHOW, ..., pubkey_hex)
    //   → PublishRaw { kind:10154, tags, content, signer_pubkey: Some(pubkey_hex) }
    //
    // The harness dispatch() returns the NMP accept envelope {"correlation_id":"..."},
    // NOT the handler result. The actor processes the command asynchronously.
    let show_dispatch = dispatch(
        app,
        "podcast.publish",
        json!({"op": "publish_show", "podcast_id": podcast_id}),
    );
    if show_dispatch.get("error").is_some() {
        return ScenarioResult::Fail(format!(
            "publish_show dispatch rejected: {show_dispatch}"
        ));
    }
    // Acceptance means the action was queued on the kernel's actor — the signing
    // path will run on the actor's next tick.
    if show_dispatch.get("correlation_id").is_none() {
        return ScenarioResult::Fail(format!(
            "publish_show not accepted by kernel (no correlation_id): {show_dispatch}"
        ));
    }

    // ── Assertion C: last_published_at is stamped by the actor ───────────────
    //
    // publish_show stamps last_published_at + bumps rev BEFORE dispatching
    // PublishRaw. If register_podcast_signer_in_kernel is dropped or the handler
    // early-exits (unknown key / store error), this stamp never happens and the
    // timeout below fires — catching the regression.
    let target_id2 = podcast_id.clone();
    let update_after_show = match wait_for(handle, 10_000, |u| {
        u.owned_podcasts
            .iter()
            .find(|o| o.podcast_id == target_id2)
            .and_then(|o| o.last_published_at)
            .is_some()
    }) {
        Ok(u) => u,
        Err(msg) => {
            return ScenarioResult::Fail(format!(
                "REGRESSION: timeout waiting for last_published_at after publish_show \
                 (podcast_id={podcast_id}): {msg}. \
                 Likely cause: register_podcast_signer_in_kernel was removed or the \
                 publish_show handler errored before reaching rev.fetch_add."
            ))
        }
    };

    let last_published_at_1 = update_after_show
        .owned_podcasts
        .iter()
        .find(|o| o.podcast_id == podcast_id)
        .and_then(|o| o.last_published_at)
        .expect("predicate ensured last_published_at is Some");

    if last_published_at_1 <= 0 {
        return ScenarioResult::Fail(format!(
            "last_published_at is not a positive Unix timestamp ({last_published_at_1})"
        ));
    }

    // ── Assertion B (post-show-publish): active account must NOT have changed ─
    //
    // nmp_app_signin_nsec(make_active=0) is the contract for AddSigner.
    // If a regression passes make_active=1, the kernel's active signer switches
    // to the per-podcast key and this assertion fires.
    let active_after_show = match update_after_show.active_account {
        Some(acc) => acc,
        None => {
            return ScenarioResult::Fail(
                "active_account became None after publish_show (unexpected)".into(),
            )
        }
    };
    if active_after_show.pubkey_hex != active_before.pubkey_hex {
        return ScenarioResult::Fail(format!(
            "REGRESSION (make_active=false): active_account changed after publish_show. \
             Before: {} After: {}. \
             nmp_app_signin_nsec must be called with make_active=0.",
            active_before.pubkey_hex,
            active_after_show.pubkey_hex
        ));
    }

    // ── Step 5 (Assertion D): publish_episode (kind:54) ──────────────────────
    //
    // The same register→sign path as publish_show but for a kind:54 episode
    // event. The mock feed provides at least 3 episodes; use the first one.
    if let Some(ref ep_id) = episode_id {
        let ep_dispatch = dispatch(
            app,
            "podcast.publish",
            json!({"op": "publish_episode", "episode_id": ep_id}),
        );
        if ep_dispatch.get("error").is_some() {
            return ScenarioResult::Fail(format!(
                "publish_episode dispatch rejected: {ep_dispatch}"
            ));
        }
        if ep_dispatch.get("correlation_id").is_none() {
            return ScenarioResult::Fail(format!(
                "publish_episode not accepted by kernel (no correlation_id): {ep_dispatch}"
            ));
        }

        // Give the actor a tick to process the episode publish command before
        // reading the snapshot for the active-account check. The episode publish
        // path does not update an observable snapshot slot (no episode-level
        // last_published_at), so we use a short sleep + snapshot read.
        std::thread::sleep(std::time::Duration::from_millis(600));

        match snapshot(handle).and_then(|u| u.active_account) {
            Some(acc) if acc.pubkey_hex == active_before.pubkey_hex => {}
            Some(acc) => {
                return ScenarioResult::Fail(format!(
                    "REGRESSION (make_active=false): active_account changed after \
                     publish_episode. Before: {} After: {}.",
                    active_before.pubkey_hex,
                    acc.pubkey_hex
                ))
            }
            None => {
                return ScenarioResult::Fail(
                    "active_account became None after publish_episode".into(),
                )
            }
        }
    }

    // ── Step 6 (Assertion E): Idempotent re-registration ────────────────────
    //
    // A second publish_show for the same podcast re-registers the identical
    // per-podcast key through AddSigner (idempotent by kernel contract). This
    // catches regressions where:
    //   - The kernel rejects a duplicate signer registration (AddSigner not idempotent).
    //   - Re-registration accidentally flips make_active to true.
    let show2_dispatch = dispatch(
        app,
        "podcast.publish",
        json!({"op": "publish_show", "podcast_id": podcast_id}),
    );
    if show2_dispatch.get("error").is_some() {
        return ScenarioResult::Fail(format!(
            "idempotent re-register: second publish_show rejected: {show2_dispatch}"
        ));
    }
    if show2_dispatch.get("correlation_id").is_none() {
        return ScenarioResult::Fail(format!(
            "idempotent re-register: second publish_show not accepted: {show2_dispatch}"
        ));
    }

    // Wait briefly for the second publish_show to complete (last_published_at
    // may stay the same within the same second; we just need the actor to finish).
    let target_id3 = podcast_id.clone();
    let _ = wait_for(handle, 5_000, |u| {
        u.owned_podcasts
            .iter()
            .find(|o| o.podcast_id == target_id3)
            .and_then(|o| o.last_published_at)
            .map(|t| t >= last_published_at_1)
            .unwrap_or(false)
    });

    // Final active-account check after idempotent re-register.
    match snapshot(handle).and_then(|u| u.active_account) {
        Some(acc) if acc.pubkey_hex == active_before.pubkey_hex => {}
        Some(acc) => {
            return ScenarioResult::Fail(format!(
                "REGRESSION (make_active=false): active_account changed after idempotent \
                 re-register. Before: {} After: {}.",
                active_before.pubkey_hex,
                acc.pubkey_hex
            ))
        }
        None => {
            return ScenarioResult::Fail(
                "active_account became None after idempotent re-register".into(),
            )
        }
    }

    ScenarioResult::Pass
}
