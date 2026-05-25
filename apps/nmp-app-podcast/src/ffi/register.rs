//! The `pub extern "C"` registration entry point Swift links against to wire
//! Podcast projections and action namespaces into an [`NmpApp`].

use std::ffi::c_char;

use nmp_ffi::NmpApp;

use super::handle::PodcastHandle;
use super::helpers::c_string_opt;

/// Register Podcast projections and action namespaces against `app`. Returns a
/// non-null `*mut PodcastHandle` on success; `null` on any failure (null
/// pointer arguments, slot lock poisoning).
///
/// `viewer_pubkey` is a hex-encoded pubkey (64 chars). NULL is permitted and
/// treated as "no viewer" (pre-sign-in state).
///
/// `app` MUST outlive the returned handle. Call
/// [`nmp_app_podcast_unregister`] before `nmp_app_free`.
#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_register(
    app: *mut NmpApp,
    viewer_pubkey: *const c_char,
) -> *mut PodcastHandle {
    if app.is_null() {
        return std::ptr::null_mut();
    }

    // Wire the canonical NMP composition — NIP-02 / NIP-17 / NIP-57 / NIP-65
    // action modules, the kind:10050 ingest parser, the production routing
    // substrate, and the DM-inbox + zap-receipts runtime controllers.
    //
    // SAFETY: caller guarantees `app` is a valid pointer from `nmp_app_new`.
    // No other reference aliases it here — the `&*app` borrow further down is
    // taken only after this exclusive borrow is dropped.
    nmp_app_template::register_defaults(unsafe { &mut *app });

    // Podcast-specific action module registrations will be added here in
    // subsequent milestones (NIP-74 feed actions, playback intents, etc.).
    // See `actions.rs`.

    // Consume the viewer_pubkey argument (used in future projections).
    let _viewer = c_string_opt(viewer_pubkey);

    Box::into_raw(Box::new(PodcastHandle { app }))
}
