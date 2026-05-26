//! Android JNI shim — M2.F second-platform proof. Mirrors iOS
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
//!
//! Dispatch-heavy entry points (nativeDispatchAction, nativeSigninNsec,
//! nativeNextUpdate, nativePodcastSnapshot, nmpActionDispatch,
//! nmpCapabilityReport) live in [`bridge`] to keep this file within the
//! 300-line soft limit.

use std::ffi::{c_char, c_void, CStr};
use std::sync::mpsc::{Receiver, Sender};

use jni::objects::{JClass};
use jni::sys::{jint, jlong};
use jni::JNIEnv;

use nmp_ffi::{
    nmp_app_free, nmp_app_is_alive, nmp_app_lifecycle_background,
    nmp_app_lifecycle_foreground, nmp_app_new, nmp_app_set_update_callback, nmp_app_start,
    nmp_app_stop, NmpApp,
};

use crate::ffi::{nmp_app_podcast_register, nmp_app_podcast_unregister, PodcastHandle};

mod bridge;

// ─────────────────────────────────────────────────────────────────────────────
// Session — boxed lifetime container
// ─────────────────────────────────────────────────────────────────────────────

/// Owns the kernel handle, the projection handle, the snapshot receiver, and
/// the boxed sender that the kernel holds as an opaque callback context.
/// Freed exactly once in `nativeFree` — mirror of iOS `PodcastHandle.deinit`.
pub(crate) struct Session {
    pub(crate) app: *mut NmpApp,
    podcast: *mut PodcastHandle,
    rx: Receiver<String>,
    tx: *mut Sender<String>,
}

// SAFETY: `Session` is sent across threads only inside a `Box` whose ownership
// is transferred to Kotlin as an opaque `jlong`. Access is serialized by the
// Kotlin caller (`nativeNew` → `nativeFree` lifecycle; `nativeNextUpdate` on a
// single reader thread). The raw pointers are never aliased.
unsafe impl Send for Session {}

#[must_use]
fn session_ref<'a>(handle: jlong) -> Option<&'a Session> {
    if handle == 0 {
        None
    } else {
        // SAFETY: non-zero handles are live `Session` pointers produced by
        // `nativeNew`; Kotlin never calls after `nativeFree`.
        Some(unsafe { &*(handle as *const Session) })
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Update callback — copies the JSON before the kernel reclaims its buffer.
// ─────────────────────────────────────────────────────────────────────────────

/// `nmp_app_set_update_callback` fires on the kernel's listener thread; the
/// `json` pointer is only borrowed for this call (NMP `ffi-surface.md` §3), so
/// we copy it into an owned `String` before sending it down a channel. A
/// Kotlin thread drains the channel via `nativeNextUpdate` — pull-side cadence
/// sidesteps JNI thread-attach/global-ref complexity.
extern "C" fn on_update(context: *mut c_void, json: *const c_char) {
    if context.is_null() || json.is_null() {
        return;
    }
    // SAFETY: `context` is the `Box<Sender<String>>` pointer registered in
    // `nativeNew`; it lives until `nativeFree` clears the callback before
    // reclaiming the box.
    let tx = unsafe { &*(context as *const Sender<String>) };
    let owned = unsafe { CStr::from_ptr(json) }
        .to_string_lossy()
        .into_owned();
    // Dead receiver ⇒ silent no-op (D6).
    let _ = tx.send(owned);
}

// ─────────────────────────────────────────────────────────────────────────────
// JNI entry points — session lifecycle (mirror of `KernelBridge.swift`)
// ─────────────────────────────────────────────────────────────────────────────

/// `nativeNew()` — construct the kernel, wire the update callback, register the
/// Podcast projection. Mirror of `PodcastHandle.init()` in Swift.
///
/// Returns the boxed `Session` pointer as `jlong` (0 on any failure).
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeNew(
    _env: JNIEnv,
    _class: JClass,
) -> jlong {
    let app = nmp_app_new();
    if app.is_null() {
        return 0;
    }
    let (tx, rx) = std::sync::mpsc::channel::<String>();
    let tx = Box::into_raw(Box::new(tx));
    // `nmp_app_set_update_callback` is `pub extern "C" fn` (safe Rust at the
    // call site). `app` is valid (just allocated), `tx` is a fresh box, and
    // `on_update` matches the kernel's `UpdateCallback` C ABI.
    nmp_app_set_update_callback(app, tx as *mut c_void, Some(on_update));
    let podcast = nmp_app_podcast_register(app);
    let session = Box::new(Session {
        app,
        podcast,
        rx,
        tx,
    });
    Box::into_raw(session) as jlong
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
    if let Some(s) = session_ref(handle) {
        nmp_app_start(s.app, 0, visible_limit as u32, emit_hz as u32);
    }
}

/// `nativeStop(handle)` — halt the kernel actor (idempotent).
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeStop(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    if let Some(s) = session_ref(handle) {
        nmp_app_stop(s.app);
    }
}

/// `nativeIsAlive(handle)` — actor-liveness probe (D7).
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeIsAlive(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jint {
    match session_ref(handle) {
        Some(s) => nmp_app_is_alive(s.app) as jint,
        None => 0,
    }
}

/// `nativeLifecycleForeground(handle)` / `nativeLifecycleBackground(handle)` —
/// host lifecycle bridge (G3). Mirror of iOS scenePhase wiring.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeLifecycleForeground(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    if let Some(s) = session_ref(handle) {
        nmp_app_lifecycle_foreground(s.app);
    }
}

#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeLifecycleBackground(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    if let Some(s) = session_ref(handle) {
        nmp_app_lifecycle_background(s.app);
    }
}

/// `nativeFree(handle)` — tear down the kernel and the projection handle.
/// Exactly-once.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeFree(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    if handle == 0 {
        return;
    }
    // SAFETY: `handle` was produced by `nativeNew`; freed exactly once.
    let s = unsafe { Box::from_raw(handle as *mut Session) };
    if !s.podcast.is_null() {
        nmp_app_podcast_unregister(s.podcast);
    }
    nmp_app_set_update_callback(s.app, std::ptr::null_mut(), None);
    nmp_app_free(s.app);
    // SAFETY: callback has been cleared; the `Sender` box is no longer
    // reachable from the kernel thread.
    unsafe {
        drop(Box::from_raw(s.tx));
    }
}
