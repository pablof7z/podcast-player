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
//! Calls into the kernel go through the `nmp_native_runtime::NmpApp` typed
//! method surface (and `nmp_uniffi_support` for the callback seams), not
//! `extern "C"` declarations — the ADR-0069 UniFFI native runtime replaces
//! the deleted `nmp-ffi` C-ABI crate. `nmp_app_podcast_decode_update_frame`
//! is still reached via a raw `extern "C"` declaration because it is an
//! in-crate `#[no_mangle]` symbol not re-exported at the Rust item level
//! (`ffi::snapshot` is `pub(crate)`), matching the same pattern the headless
//! binary's `sign_tap.rs` uses.

use std::collections::HashMap;
use std::ffi::CString;
use std::sync::{Arc, Mutex, OnceLock};
use std::sync::atomic::{AtomicBool, Ordering};
use crossbeam_channel::{Receiver as CbReceiver, Sender as CbSender};

use jni::objects::{JClass, JString};
use jni::sys::{jint, jlong};
use jni::JNIEnv;

use nmp_native_runtime::NmpApp;

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
    /// Whether a capability router is currently installed. `nmp_uniffi_support`
    /// owns the actual `AndroidCapabilityContext` sink's lifetime internally
    /// (as an `Arc`) once installed via `set_capability_callback`, so this
    /// Mutex now only provides the atomicity `nativeSetCapabilityRouter` /
    /// `clear_capability_router` need against a concurrent `nativeFree`
    /// (see the invariant comment on `nativeFree` below) — it no longer
    /// tracks a raw pointer to free.
    capability_ctx: Mutex<bool>,
    /// ADR-0048 — outbound NIP-55 `ExternalSignerRequest` JSON queue. The
    /// capability trampoline (`android_capability_callback`, on a Rust thread)
    /// pushes the inner request payload here when it sees the `external_signer`
    /// namespace; a Kotlin reader thread drains it via `nativeNextSignerRequest`
    /// and hands each item to `ExternalSignerCapabilityBridge.handleJson`. This
    /// channel-drain shape mirrors NMP's own `nmp-android-ffi` Chirp bridge: the
    /// capability is interactive/async (an Amber Intent round-trip) and cannot
    /// resolve synchronously inside the capability callback.
    ///
    /// Wrapped in `Mutex<Option<...>>` so `nativeFree` can drop the sender
    /// after `clear_capability_router` has already dropped the capability-ctx
    /// clone — at that point no other sender exists and `signer_rx` disconnects,
    /// unblocking any `select!` that consumed the one-shot shutdown token before
    /// the loop had a chance to exit (shutdown race, #600).
    pub(crate) signer_requests: Mutex<Option<CbSender<String>>>,
    pub(crate) signer_rx: CbReceiver<String>,
    /// Shutdown token for the `nativeNextUpdate` blocking loop.
    pub(crate) shutdown_tx_update: CbSender<()>,
    pub(crate) shutdown_rx_update: CbReceiver<()>,
    /// Shutdown token for the `nativeNextSignerRequest` blocking loop.
    pub(crate) shutdown_tx_signer: CbSender<()>,
    pub(crate) shutdown_rx_signer: CbReceiver<()>,
    /// Set to `true` in `nativeFree` before `clear_capability_router` runs.
    /// Checked inside the `capability_ctx` lock in `nativeSetCapabilityRouter`
    /// so that a late install (after clear_capability_router already ran) is
    /// rejected atomically — no leaked callback on a freed NmpApp.
    pub(crate) shutting_down: AtomicBool,
}

// SAFETY: `Session` is accessed from multiple JNI threads via Arc clones.
// - `app`: borrowed pointer, safe from any thread (all NMP calls are thread-safe).
// - `podcast`: borrowed pointer, safe from any thread (all NMP calls are thread-safe).
// - `rx`, `signer_rx`, `shutdown_rx_update`, `shutdown_rx_signer`: crossbeam channels
//   are Sync; safe to read from multiple threads. Each JNI caller holds an Arc clone
//   until the call returns.
// - `signer_requests`: `Mutex<Option<CbSender<String>>>` — interior mutability lets
//   `nativeFree` drain and drop the sender; `Mutex` is Sync.
// - `shutdown_tx_update`, `shutdown_tx_signer`: shared safely via Arc.
// - `capability_ctx`: guarded by Mutex.
unsafe impl Send for Session {}
unsafe impl Sync for Session {}

impl Drop for Session {
    fn drop(&mut self) {
        // Native teardown deferred to here so that in-flight JNI callers that
        // hold an Arc<Session> clone (cloned via `session_ref` before
        // `nativeFree` removed the registry entry) have returned before we
        // release native handles. `nativeFree` eagerly calls `stop_runtime`
        // (signal only) and signals shutdown channels; this destructor performs
        // the actual memory release.
        //
        // Order matters: clear the update callback first so the kernel thread
        // cannot call back into the update sink after we free `app` below.
        // SAFETY: `self.app` is a live `Box::into_raw` pointer for the entire
        // lifetime of this Session; nothing else frees it before this point.
        let app_ref = unsafe { &*self.app };
        app_ref.set_update_listener(None);
        if !self.podcast.is_null() {
            nmp_app_podcast_unregister(self.podcast);
        }
        // SAFETY: `self.app` was allocated via `Box::into_raw` in `nativeNew`
        // and is freed exactly once here, after the update listener has been
        // cleared and the podcast handle unregistered.
        unsafe {
            drop(Box::from_raw(self.app));
        }
    }
}

// ── Session registry — eliminates raw-Arc UAF race ──────────────────────────
//
// Previously `nativeNew` returned `Arc::into_raw` and `session_ref` called
// `Arc::increment_strong_count` on that raw pointer. That is UB if a
// concurrent `nativeFree` has already dropped the last strong count: a Kotlin
// thread can read the non-zero handle, be preempted, `nativeFree` runs to
// completion (count → 0, memory freed), and the Kotlin thread resumes calling
// `session_ref` on a dangling pointer.
//
// Fix: the canonical Arc lives in a global registry keyed by allocation
// address. `session_ref` clones from the registry under the mutex (safe — the
// Arc is alive while the entry exists). `nativeFree` removes the entry under
// the same mutex, so no further clone is possible after removal. The removed
// Arc is then used for cleanup and drops when the `nativeFree` closure exits.

static SESSION_REGISTRY: OnceLock<Mutex<HashMap<u64, Arc<Session>>>> = OnceLock::new();
// Monotonic handle counter. Starting at 1 keeps 0 as the "null" sentinel.
// Handles are never reused, so an ABA race — where a freed handle coincides
// with a newly allocated Session at the same heap address — cannot occur.
static NEXT_SESSION_HANDLE: std::sync::atomic::AtomicU64 =
    std::sync::atomic::AtomicU64::new(1);

fn session_registry() -> &'static Mutex<HashMap<u64, Arc<Session>>> {
    SESSION_REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

#[must_use]
pub(super) fn session_ref(handle: jlong) -> Option<Arc<Session>> {
    if handle == 0 {
        return None;
    }
    // Clone from the registry under the mutex. If `nativeFree` has already
    // removed this entry, `get` returns `None` — silent no-op (D6). No raw
    // pointer arithmetic; no increment_strong_count on potentially-freed memory.
    session_registry().lock().ok()?.get(&(handle as u64)).cloned()
}

// ── Update callback — copies JSON before the kernel reclaims its buffer. ─────

/// Installed via `nmp_uniffi_support::set_update_sink` in `nativeNew`. NMP's
/// update transport is binary FlatBuffers, so the frame arrives as an owned
/// `Vec<u8>` (the sink API copies it out of the kernel's buffer before
/// invoking this closure — no raw `(ptr, len)` borrow to manage). We decode
/// it to the JSON envelope via `nmp_app_podcast_decode_update_frame` (the
/// same in-crate symbol the iOS `KernelBridge.swift` callback uses), copy the
/// JSON into an owned `String`, and send it down the channel. A Kotlin thread
/// drains the channel via `nativeNextUpdate` — pull-side cadence sidesteps
/// JNI thread-attach/global-ref complexity.
fn on_update(sink: &CbSender<String>, frame: Vec<u8>) {
    if frame.is_empty() {
        return;
    }
    ffi_guard("on_update", || (), || {
        // SAFETY: `frame` is a valid Rust `Vec<u8>`, trivially valid for its
        // own length.
        let json_ptr = unsafe {
            crate::ffi::snapshot::nmp_app_podcast_decode_update_frame(frame.as_ptr(), frame.len())
        };
        if json_ptr.is_null() {
            return;
        }
        // SAFETY: `json_ptr` is a heap-owned NUL-terminated C string produced
        // via `CString::into_raw` inside `nmp_app_podcast_decode_update_frame`,
        // and we now own it exactly once. Reclaiming it as a `CString` frees
        // it on drop — there is no separate free-string doorway anymore.
        let owned = unsafe { CString::from_raw(json_ptr) }
            .to_string_lossy()
            .into_owned();
        // Dead receiver ⇒ silent no-op (D6).
        let _ = sink.send(owned);
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
        // SAFETY: `Box::into_raw` always yields a non-null pointer — no
        // null check needed (unlike the deleted `nmp_app_new` C-ABI, which
        // could theoretically fail on OOM).
        let app = Box::into_raw(Box::new(nmp_native_runtime::new_app()));
        let (tx, rx) = crossbeam_channel::unbounded::<String>();
        // `nmp_uniffi_support::set_update_sink` owns the sink's lifetime
        // internally (as an `Arc`) once installed; `Session::drop` clears it
        // via `set_update_listener(None)` rather than freeing a raw pointer.
        nmp_uniffi_support::set_update_sink(unsafe { &*app }, Some(Box::new(tx)), on_update);
        let podcast = nmp_app_podcast_register(app);
        // ADR-0048 — install the NIP-55 external-signer driver so the kernel can
        // dispatch `external_signer` capability requests (built when the host
        // calls `nativeSignInNip55`). The driver only emits onto the capability
        // socket; the host adapter (`ExternalSignerCapabilityBridge`) is wired
        // through the channel below once `nativeSetCapabilityRouter` registers
        // the trampoline. Safe to call before the callback exists — no request
        // is built until sign-in.
        unsafe { &*app }.init_external_signer();
        // NIP-46 signer broker — registers the bunker hook + relay listener so
        // `nativeSignInBunker` / `nativeNostrconnectUri` are live. Idempotent;
        // mirrors the iOS `PodcastHandle.init` call to `init_signer_broker`.
        // MUST be called once after allocating `app` and before any bunker://
        // or nostrconnect:// sign-in attempt (D6 — no-op if already init'd).
        let _ = unsafe { &*app }.init_signer_broker();
        let (signer_tx, signer_rx) = crossbeam_channel::unbounded::<String>();
        let (shutdown_tx_update, shutdown_rx_update) = crossbeam_channel::bounded::<()>(1);
        let (shutdown_tx_signer, shutdown_rx_signer) = crossbeam_channel::bounded::<()>(1);
        let session = Arc::new(Session {
            app,
            podcast,
            rx,
            capability_ctx: Mutex::new(false),
            signer_requests: Mutex::new(Some(signer_tx)),
            signer_rx,
            shutdown_tx_update,
            shutdown_rx_update,
            shutdown_tx_signer,
            shutdown_rx_signer,
            shutting_down: AtomicBool::new(false),
        });
        // Assign a monotonic handle so handles are never reused. Using the Arc
        // allocation address as the key would create an ABA hazard: after free,
        // a new Session might land at the same address and a stale Kotlin
        // caller with the old handle would erroneously route to the new session.
        let handle = NEXT_SESSION_HANDLE.fetch_add(1, Ordering::Relaxed);
        match session_registry().lock() {
            Ok(mut guard) => { guard.insert(handle, session); }
            Err(_) => return 0, // poisoned — fail safe (D6)
        }
        handle as jlong
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
            // ADR-0053 / NMP v0.8: Android is a full Podcast client, so
            // declare the explicit all-builtins projection intent before
            // actor start. App-local podcast sidecars are registered via
            // `nmp_app_podcast_register`.
            let app_ref = unsafe { &*s.app };
            app_ref.consume_all_builtin_projections();
            app_ref.start_runtime(visible_limit as usize, emit_hz as u32);
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
            unsafe { &*s.app }.stop_runtime();
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
            Some(s) => unsafe { &*s.app }.is_alive() as jint,
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
            unsafe { &*s.app }.lifecycle_foreground();
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
            unsafe { &*s.app }.lifecycle_background();
        }
    });
}

/// `nativeFree(handle)` — initiate kernel shutdown and release the registry
/// entry. Exactly-once. Native handle teardown (`Box::from_raw`, etc.) is
/// deferred to `Session::drop` so that any in-flight JNI callers holding an
/// `Arc<Session>` clone (grabbed before the registry entry was removed) can
/// return before native memory is released — eliminating the UAF race.
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
        // Remove the Arc from the registry under the mutex. After this point
        // `session_ref` returns None for this handle — no new Arc clones can
        // be created, closing the UAF window. The Arc we extracted keeps the
        // Session allocation alive until all existing clones are also released.
        let s = match session_registry().lock() {
            Ok(mut guard) => guard.remove(&(handle as u64)),
            Err(_) => None,
        };
        let Some(s) = s else { return; };
        // Signal the actor to stop (non-destructive — does not free any handle).
        unsafe { &*s.app }.stop_runtime();
        // Signal shutdown: each blocking loop gets its own dedicated channel so
        // neither can steal the other's token. Both sends always succeed (D6 —
        // a full channel means the signal is already pending).
        let _ = s.shutdown_tx_update.try_send(());
        let _ = s.shutdown_tx_signer.try_send(());
        // Mark teardown before clearing the router so that a concurrent
        // nativeSetCapabilityRouter that already cloned signer_tx will see
        // this flag inside the capability_ctx lock and bail without installing.
        s.shutting_down.store(true, Ordering::Release);
        capability_router::clear_capability_router(&s);
        // Drop the signer-request sender now that the capability-ctx clone has
        // been cleared. This disconnects signer_rx, unblocking the
        // nativeNextSignerRequest select! if it re-entered after consuming the
        // one-shot shutdown token (#600).
        drop(s.signer_requests.lock().ok().and_then(|mut g| g.take()));
        // Drop our Arc. When all in-flight session_ref Arc clones also drop
        // (i.e. every concurrent JNI call returns), Session::drop runs and
        // releases native handles: set_update_listener(None),
        // nmp_app_podcast_unregister, and Box::from_raw(app).
    });
}
