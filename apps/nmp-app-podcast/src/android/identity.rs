//! Identity and auth JNI entry points — nsec sign-in, NIP-46 bunker sign-in,
//! profile claim/release, and nostrconnect URI generation.
//!
//! Doctrine: D6 — every entry point degrades silently on null / poison /
//! conversion failure. No business logic lives here.

use jni::objects::{JClass, JString};
use jni::sys::{jint, jlong, jstring};
use jni::JNIEnv;

use crate::ffi::guard::ffi_guard;
use super::session_ref;

/// `nativeSigninNsec(handle, nsec)` — one-shot sign-in via local nsec.
/// Demonstrates the single capability + dispatch the milestone calls for.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeSigninNsec<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    handle: jlong,
    nsec: JString<'l>,
) {
    ffi_guard("nativeSigninNsec", || (), || {
        let Some(s) = session_ref(handle) else {
            return;
        };
        let secret = match env.get_string(&nsec) {
            Ok(s) => s.to_string_lossy().into_owned(),
            Err(_) => return,
        };
        // v0.2.4: make_active = true — Android sign-in activates the imported
        // account.
        // SAFETY: `s.app` is a live pointer for the lifetime of the Session.
        unsafe { &*s.app }.add_signer(
            nmp_core::SignerSource::LocalNsec(zeroize::Zeroizing::new(secret)),
            true,
        );
    });
}

/// `nativeClaimProfile(handle, pubkeyHex, consumerID)` — register a refcounted
/// interest in a Nostr pubkey's kind:0 profile under the given consumer token.
/// The kernel fetches the profile over its relay pool and surfaces it in
/// `projections["resolved_profiles"]` on the next push frame. D6: invalid
/// pubkey, null/non-UTF-8 arguments, or a null handle are silent no-ops.
///
/// Mirrors iOS `PodcastHandle.claimProfile(pubkeyHex:consumerID:)`. Uses the
/// ADR-0063 Lane D `NmpApp::resolve_ref` entry point (namespace=Profile,
/// shape=Profile(Card), liveness=CacheOk for background list-row claims).
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeClaimProfile<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    handle: jlong,
    pubkey_hex: JString<'l>,
    consumer_id: JString<'l>,
) {
    ffi_guard("nativeClaimProfile", || (), || {
        let Some(s) = session_ref(handle) else {
            return;
        };
        let pubkey = match env.get_string(&pubkey_hex) {
            Ok(s) => s.to_string_lossy().into_owned(),
            Err(_) => return,
        };
        let consumer = match env.get_string(&consumer_id) {
            Ok(s) => s.to_string_lossy().into_owned(),
            Err(_) => return,
        };
        // ADR-0063 Lane D: namespace=Profile, shape=Profile(Card),
        // liveness=CacheOk (background list-row claims never force a re-fetch).
        // SAFETY: `s.app` is a live pointer for the lifetime of the Session.
        unsafe { &*s.app }.resolve_ref(
            nmp_core::RefNamespace::Profile,
            pubkey,
            consumer,
            nmp_core::RefShape::Profile(nmp_core::ProfileShape::Card),
            nmp_core::RefLiveness::CacheOk,
        );
    });
}

/// `nativeReleaseProfile(handle, pubkeyHex, consumerID)` — release a previously
/// claimed profile interest. The kernel drops the pending request when the last
/// consumer releases. Idempotent / safe when nothing is claimed for this pair.
/// D6: any invalid argument is a silent no-op.
///
/// Mirrors iOS `PodcastHandle.releaseProfile(pubkeyHex:consumerID:)`. Uses the
/// ADR-0063 Lane D `NmpApp::release_ref` entry point (namespace=Profile).
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeReleaseProfile<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    handle: jlong,
    pubkey_hex: JString<'l>,
    consumer_id: JString<'l>,
) {
    ffi_guard("nativeReleaseProfile", || (), || {
        let Some(s) = session_ref(handle) else {
            return;
        };
        let pubkey = match env.get_string(&pubkey_hex) {
            Ok(s) => s.to_string_lossy().into_owned(),
            Err(_) => return,
        };
        let consumer = match env.get_string(&consumer_id) {
            Ok(s) => s.to_string_lossy().into_owned(),
            Err(_) => return,
        };
        // ADR-0063 Lane D: namespace=Profile.
        // SAFETY: `s.app` is a live pointer for the lifetime of the Session.
        unsafe { &*s.app }.release_ref(nmp_core::RefNamespace::Profile, pubkey, consumer);
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// NIP-46 remote-signer JNI wrappers (bunker:// + nostrconnect://)
// ─────────────────────────────────────────────────────────────────────────────

/// `nativeSignInBunker(handle, uri, makeActive)` — add a `SignerSource::BunkerUri`
/// signer for the supplied `bunker://` URI (replaces the old dedicated
/// `SignInBunker` actor command — see `nmp_core::SignerSource`).
/// Silent no-op (D6) if the broker has not been initialised — which it always
/// is because `nativeNew` calls `init_signer_broker`.
///
/// `makeActive = true` is the only meaningful value for the UX (the user chose
/// this signer to be their active account); pass `true` from Kotlin.
///
/// Mirrors iOS `PodcastHandle.signInBunker(uri:)`.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeSignInBunker<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    handle: jlong,
    uri: JString<'l>,
    make_active: jint,
) {
    ffi_guard("nativeSignInBunker", || (), || {
        let Some(s) = session_ref(handle) else {
            return;
        };
        let uri_str = match env.get_string(&uri) {
            Ok(s) => s.to_string_lossy().into_owned(),
            Err(_) => return,
        };
        // SAFETY: `s.app` is a live pointer for the lifetime of the Session.
        unsafe { &*s.app }.add_signer(
            nmp_core::SignerSource::BunkerUri(uri_str),
            make_active != 0,
        );
    });
}

/// `nativeCancelBunkerHandshake(handle)` — abort the in-flight NIP-46
/// handshake. Idempotent / safe when no handshake is in flight (D6).
///
/// Mirrors iOS `PodcastHandle.cancelBunkerHandshake()`.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeCancelBunkerHandshake(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    ffi_guard("nativeCancelBunkerHandshake", || (), || {
        if let Some(s) = session_ref(handle) {
            // SAFETY: `s.app` is a live pointer for the lifetime of the Session.
            unsafe { &*s.app }.cancel_bunker_handshake();
        }
    });
}

/// `nativeNostrconnectUri(handle, relayUrl, callbackScheme)` — allocate a
/// freshly-generated `nostrconnect://` URI from the broker and copy it to a
/// Java `String`.
///
/// Returns `null` when the broker is not initialised or the kernel returns
/// `None` (D6).
///
/// `relayUrl` is retained only for Kotlin/Swift API compatibility; NMP v0.8
/// always selects the relay from the kernel relay config. `callbackScheme` is
/// optional platform callback information.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeNostrconnectUri<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    handle: jlong,
    _relay_url: JString<'l>,
    callback_scheme: JString<'l>,
) -> jstring {
    let null: jstring = std::ptr::null_mut();
    ffi_guard("nativeNostrconnectUri", || null, || {
        let Some(s) = session_ref(handle) else {
            return null;
        };
        // Convert optional JString arg — null JString (from Kotlin `null`)
        // becomes `None`, which the kernel accepts per its contract.
        let callback: Option<String> = env
            .get_string(&callback_scheme)
            .ok()
            .map(|js| js.to_string_lossy().into_owned());

        // SAFETY: `s.app` is a live pointer for the lifetime of the Session.
        let uri = unsafe { &*s.app }.nostrconnect_uri(callback.as_deref());
        let Some(uri) = uri else {
            return null;
        };
        match env.new_string(uri) {
            Ok(js) => js.into_raw(),
            Err(_) => null,
        }
    })
}
