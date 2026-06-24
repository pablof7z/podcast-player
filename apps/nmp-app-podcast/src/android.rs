//! Android JNI shim. Mirrors iOS
//! `KernelBridge.swift` in `Java_io_f7z_podcast_KernelBridge_*` symbols.
//!
//! Lives inside this crate (gated `#[cfg(target_os = "android")]`) instead of
//! a separate `nmp-android-ffi`-style crate so one cargo binary drives both
//! platforms. iOS/macOS builds are unaffected — `jni` is a
//! `[target.'cfg(target_os = "android")']` dep.
//!
//! Doctrine: D5/D8 — pure transport, no business logic or cached state;
//! D6 — every entry point degrades silently on null / poison / serde failure.
//!
//! Calls into the kernel go through Rust paths (`nmp_ffi::nmp_app_*`), not
//! `extern "C"` declarations. Symbols declared only via `extern "C"` stay
//! undefined in the cdylib; calling through Rust paths makes rustc pull the
//! bodies into the codegen unit — same pattern as NMP's `nmp-android-ffi`.

use std::ffi::{c_void, CStr, CString};
use std::sync::{Arc, Mutex};
use crossbeam_channel::{Receiver as CbReceiver, Sender as CbSender};

use jni::objects::{JClass, JString};
use jni::sys::{jint, jlong};
use jni::JNIEnv;

use nmp_ffi::{
    nmp_app_free, nmp_free_string, nmp_app_is_alive, nmp_app_lifecycle_background,
    nmp_app_lifecycle_foreground, nmp_app_new, nmp_app_set_update_callback,
    nmp_app_start, nmp_app_stop, nmp_external_signer_init,
    nmp_signer_broker_init, NmpApp,
};

use crate::ffi::{
    nmp_app_podcast_register, nmp_app_podcast_set_data_dir,
    nmp_app_podcast_unregister, PodcastHandle,
};
use crate::ffi::guard::ffi_guard;

#[path = "android/capability_router.rs"]
mod capability_router;
#[path = "android/external_signer.rs"]
mod external_signer;
#[path = "android/identity.rs"]
mod identity;
#[path = "android/provider_transport.rs"]
mod provider_transport;
#[path = "android/reports.rs"]
mod reports;
#[path = "android/snapshot.rs"]
mod snapshot;

// ── Session — boxed lifetime container ──────────────────────────────────────

/// Owns the kernel handle, the projection handle, the snapshot receiver, and
/// the boxed sender that the kernel holds as an opaque callback context.
/// Wrapped in an Arc for safe reference counting across JNI threads.
/// Freed exactly once in `nativeFree` — mirror of iOS `PodcastHandle.deinit`.
pub(crate) struct Session {
    pub(crate) app: *mut NmpApp,
    podcast: *mut PodcastHandle,
    pub(crate) rx: CbReceiver<String>,
    pub(crate) tx: *mut CbSender<String>,
    capability_ctx: Mutex<Option<*mut capability_router::AndroidCapabilityContext>>,
    /// ADR-0048 — outbound NIP-55 `ExternalSignerRequest` JSON queue. The
    /// capability trampoline (`android_capability_callback`, on a Rust thread)
    /// pushes the inner request payload here when it sees the `external_signer`
    /// namespace; a Kotlin reader thread drains it via `nativeNextSignerRequest`
    /// and hands each item to `ExternalSignerCapabilityBridge.handleJson`. This
    /// channel-drain shape mirrors NMP's own `nmp-android-ffi` Chirp bridge: the
    /// capability is interactive/async (an Amber Intent round-trip) and cannot
    /// resolve synchronously inside the capability callback.
    pub(crate) signer_requests: CbSender<String>,
    pub(crate) signer_rx: CbReceiver<String>,
    /// Shutdown token for the `nativeNextUpdate` blocking loop.
    pub(crate) shutdown_tx_update: CbSender<()>,
    pub(crate) shutdown_rx_update: CbReceiver<()>,
    /// Shutdown token for the `nativeNextSignerRequest` blocking loop.
    pub(crate) shutdown_tx_signer: CbSender<()>,
    pub(crate) shutdown_rx_signer: CbReceiver<()>,
}

// SAFETY: `Session` is accessed from multiple JNI threads via Arc clones.
// - `app`: borrowed pointer, safe from any thread (all NMP calls are thread-safe).
// - `podcast`: borrowed pointer, safe from any thread (all NMP calls are thread-safe).
// - `rx`, `signer_rx`, `shutdown_rx_update`, `shutdown_rx_signer`: crossbeam channels
//   are Sync; safe to read from multiple threads. Each JNI caller holds an Arc clone
//   until the call returns.
// - `tx`, `signer_requests`, `shutdown_tx_update`, `shutdown_tx_signer`: raw pointers
//   to crossbeam Senders. The `tx` pointer is dropped only in `nativeFree` after the
//   callback is cleared (no kernel thread references it). The others are shared safely
//   via Arc.
// - `capability_ctx`: guarded by Mutex.
unsafe impl Send for Session {}
unsafe impl Sync for Session {}

#[must_use]
pub(super) fn session_ref(handle: jlong) -> Option<Arc<Session>> {
    if handle == 0 {
        return None;
    }
    // SAFETY: handle is a live Arc<Session> raw pointer produced by nativeNew.
    // increment_strong_count + from_raw clones the Arc without consuming the
    // original (whose raw pointer stays stored in the handle).
    unsafe {
        Arc::increment_strong_count(handle as *const Session);
        Some(Arc::from_raw(handle as *const Session))
    }
}

// ── Update callback — copies JSON before the kernel reclaims its buffer. ─────

/// `nmp_app_set_update_callback` fires on the kernel's listener thread. NMP's
/// update transport is binary FlatBuffers (NMP `UpdateCallback` is
/// `extern "C" fn(*mut c_void, *const u8, usize)`), so the frame arrives as a
/// borrowed `(bytes, len)` buffer — **not** a NUL-terminated C string. We
/// decode it to the JSON envelope via `nmp_app_podcast_decode_update_frame`
/// (the same in-crate symbol the iOS `KernelBridge.swift` callback uses), copy
/// the JSON into an owned `String`, free the kernel pointer, then send it down
/// the channel. A Kotlin thread drains the channel via `nativeNextUpdate` —
/// pull-side cadence sidesteps JNI thread-attach/global-ref complexity.
extern "C" fn on_update(context: *mut c_void, bytes: *const u8, len: usize) {
    if context.is_null() || bytes.is_null() || len == 0 {
        return;
    }
    ffi_guard("on_update", || (), || {
        // SAFETY: `bytes` is valid for `len` bytes for the duration of this
        // call (NMP borrows the frame to the callback).
        // `decode_update_frame` returns a heap-owned C string (or null on a
        // non-decodable frame) that we must release through
        // `nmp_free_string`.
        let json_ptr = unsafe {
            crate::ffi::snapshot::nmp_app_podcast_decode_update_frame(bytes, len)
        };
        if json_ptr.is_null() {
            return;
        }
        let owned = unsafe { CStr::from_ptr(json_ptr) }
            .to_string_lossy()
            .into_owned();
        nmp_free_string(json_ptr);
        // SAFETY: `context` is the `Box<Sender<String>>` pointer registered
        // in `nativeNew`; it lives until `nativeFree` clears the callback
        // before reclaiming the box. AssertUnwindSafe is sound: null-checked
        // above; not observed again on panic path.
        let tx = unsafe { &*(context as *const CbSender<String>) };
        // Dead receiver ⇒ silent no-op (D6).
        let _ = tx.send(owned);
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// JNI entry points — lifecycle (mirror of `KernelBridge.swift`)
// ─────────────────────────────────────────────────────────────────────────────

/// `nativeNew()` — construct the kernel, wire the update callback, register the
/// Podcast projection. Mirror of `PodcastHandle.init()` in Swift.
///
/// Returns the Arc<Session> pointer as `jlong` (0 on any failure).
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeNew(
    _env: JNIEnv,
    _class: JClass,
) -> jlong {
    ffi_guard("nativeNew", || 0 as jlong, || {
        let app = nmp_app_new();
        if app.is_null() {
            return 0;
        }
        let (tx, rx) = crossbeam_channel::unbounded::<String>();
        let tx = Box::into_raw(Box::new(tx));
        // `nmp_app_set_update_callback` is `pub extern "C" fn` (safe Rust at
        // the call site). `app` is valid (just allocated), `tx` is a fresh
        // box, and `on_update` matches the kernel's `UpdateCallback` C ABI.
        nmp_app_set_update_callback(app, tx as *mut c_void, Some(on_update));
        let podcast = nmp_app_podcast_register(app);
        // ADR-0048 — install the NIP-55 external-signer driver so the kernel can
        // dispatch `external_signer` capability requests (built when the host
        // calls `nativeSignInNip55`). The driver only emits onto the capability
        // socket; the host adapter (`ExternalSignerCapabilityBridge`) is wired
        // through the channel below once `nativeSetCapabilityRouter` registers
        // the trampoline. Safe to call before the callback exists — no request
        // is built until sign-in.
        nmp_external_signer_init(app);
        // NIP-46 signer broker — registers the bunker hook + relay listener so
        // `nativeSignInBunker` / `nativeNostrconnectUri` are live. Idempotent;
        // mirrors the iOS `PodcastHandle.init` call to `nmp_signer_broker_init`.
        // MUST be called once after `nmp_app_new()` and before any bunker://
        // or nostrconnect:// sign-in attempt (D6 — no-op if already init'd).
        nmp_signer_broker_init(app);
        let (signer_tx, signer_rx) = crossbeam_channel::unbounded::<String>();
        let (shutdown_tx_update, shutdown_rx_update) = crossbeam_channel::bounded::<()>(1);
        let (shutdown_tx_signer, shutdown_rx_signer) = crossbeam_channel::bounded::<()>(1);
        let session = Arc::new(Session {
            app,
            podcast,
            rx,
            tx,
            capability_ctx: Mutex::new(None),
            signer_requests: signer_tx,
            signer_rx,
            shutdown_tx_update,
            shutdown_rx_update,
            shutdown_tx_signer,
            shutdown_rx_signer,
        });
        Arc::into_raw(session) as jlong
    })
}

/// `nativeSetDataDir(handle, path)` — bind the podcast library store to a
/// persistence directory and reload any saved state (`podcasts.json`,
/// `identity.json`, the Up-Next queue, per-podcast keys, relay config, and the
/// inbox-triage cache). Mirror of the iOS `KernelBridge+Callbacks.swift`
/// `configurePodcastDataDir` call.
///
/// Caller contract (same as iOS): invoke once, after `nativeNew` (which runs
/// `nmp_app_podcast_register`) and **before** `nativeStart`, so persisted state
/// is reloaded into the actor before it starts emitting snapshots. A null
/// handle, null/non-UTF-8 path, or a `null` podcast projection is a silent
/// no-op (D6) — the kernel side decides what and when to persist; the shell
/// only supplies the OS path.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeSetDataDir<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    handle: jlong,
    path: JString<'l>,
) {
    ffi_guard("nativeSetDataDir", || (), || {
        let Some(s) = session_ref(handle) else {
            return;
        };
        if s.podcast.is_null() {
            return;
        }
        let path = match env.get_string(&path) {
            Ok(p) => p.to_string_lossy().into_owned(),
            Err(_) => return,
        };
        let Ok(c_path) = CString::new(path) else {
            return;
        };
        // `nmp_app_podcast_set_data_dir` is the same in-crate symbol iOS
        // calls; it owns all reload/persist logic and degrades silently on
        // poison/IO error.
        nmp_app_podcast_set_data_dir(s.podcast, c_path.as_ptr());
    });
}

/// `nativeStart(handle, visibleLimit, emitHz)` — start the kernel actor.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeStart(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
    visible_limit: jint,
    emit_hz: jint,
) {
    ffi_guard("nativeStart", || (), || {
        if let Some(s) = session_ref(handle) {
            nmp_app_start(s.app, 0, visible_limit as u32, emit_hz as u32);
        }
    });
}

/// `nativeStop(handle)` — halt the kernel actor (idempotent).
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeStop(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    ffi_guard("nativeStop", || (), || {
        if let Some(s) = session_ref(handle) {
            nmp_app_stop(s.app);
        }
    });
}

/// `nativeIsAlive(handle)` — actor-liveness probe (D7).
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeIsAlive(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jint {
    ffi_guard("nativeIsAlive", || 0 as jint, || {
        match session_ref(handle) {
            Some(s) => nmp_app_is_alive(s.app) as jint,
            None => 0,
        }
    })
}

/// `nativeLifecycleForeground(handle)` / `nativeLifecycleBackground(handle)` —
/// host lifecycle bridge (G3). Mirror of iOS scenePhase wiring.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeLifecycleForeground(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    ffi_guard("nativeLifecycleForeground", || (), || {
        if let Some(s) = session_ref(handle) {
            nmp_app_lifecycle_foreground(s.app);
        }
    });
}

#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeLifecycleBackground(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    ffi_guard("nativeLifecycleBackground", || (), || {
        if let Some(s) = session_ref(handle) {
            nmp_app_lifecycle_background(s.app);
        }
    });
}

/// `nativeFree(handle)` — tear down the kernel and the projection handle.
/// Exactly-once. Reconstructs the Arc, clears the callback, drops the Sender box
/// (which unblocks any select! waiting on the rx), and drops the Arc. Session is
/// freed only after all in-flight JNI calls (holding Arc clones) return.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeFree(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    if handle == 0 {
        return;
    }
    ffi_guard("nativeFree", || (), || {
        // SAFETY: `handle` was produced by `nativeNew` as Arc::into_raw`;
        // reconstructing via Arc::from_raw is the inverse.
        let s = unsafe { Arc::from_raw(handle as *const Session) };
        nmp_app_stop(s.app);
        // Signal shutdown: each blocking loop gets its own dedicated channel so
        // neither can steal the other's token. Both sends always succeed (D6 —
        // a full channel means the signal is already pending).
        let _ = s.shutdown_tx_update.try_send(());
        let _ = s.shutdown_tx_signer.try_send(());
        capability_router::clear_capability_router(&s);
        if !s.podcast.is_null() {
            nmp_app_podcast_unregister(s.podcast);
        }
        nmp_app_set_update_callback(s.app, std::ptr::null_mut(), None);
        nmp_app_free(s.app);
        // SAFETY: callback has been cleared; the Sender box is no longer
        // reachable from the kernel thread. Drop it to disconnect the update
        // channel, unblocking any select! waiting on s.rx.
        unsafe {
            drop(Box::from_raw(s.tx));
        }
        // Drop the Arc s. When all in-flight session_ref Arc clones are also
        // released (i.e. all blocking JNI calls return), the Session is freed.
    });
}
