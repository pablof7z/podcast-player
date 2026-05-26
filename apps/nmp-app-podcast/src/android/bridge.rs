//! Android JNI entry points for dispatch, sign-in, snapshot, and
//! capability reporting.
//!
//! Extracted from `android/mod.rs` to keep that file within the 300-line
//! soft limit. All symbols here are `#[no_mangle] pub extern "system" fn`
//! and thus land in the same cdylib symbol table as the entry points in
//! `mod.rs`.

use std::ffi::{CStr, CString};
use std::sync::mpsc::RecvTimeoutError;
use std::time::Duration;

use jni::objects::{JClass, JString};
use jni::sys::{jint, jlong, jstring};
use jni::JNIEnv;

use nmp_ffi::{nmp_app_dispatch_action, nmp_app_free_string, nmp_app_signin_nsec};

use crate::ffi::{nmp_app_podcast_snapshot, nmp_app_podcast_snapshot_free};

use super::session_ref;

/// `nativeDispatchAction(handle, namespace, actionJson)` — generic
/// namespace-keyed action dispatch. Returns the JSON envelope as a Java
/// `String`, or `null` on any failure (D6).
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeDispatchAction<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    handle: jlong,
    namespace: JString<'l>,
    action_json: JString<'l>,
) -> jstring {
    let null = std::ptr::null_mut();
    let Some(s) = session_ref(handle) else {
        return null;
    };
    let ns = match env.get_string(&namespace) {
        Ok(s) => s.to_string_lossy().into_owned(),
        Err(_) => return null,
    };
    let body = match env.get_string(&action_json) {
        Ok(s) => s.to_string_lossy().into_owned(),
        Err(_) => return null,
    };
    let Ok(c_ns) = CString::new(ns) else {
        return null;
    };
    let Ok(c_body) = CString::new(body) else {
        return null;
    };
    let envelope_ptr = nmp_app_dispatch_action(s.app, c_ns.as_ptr(), c_body.as_ptr());
    if envelope_ptr.is_null() {
        return null;
    }
    // SAFETY: `envelope_ptr` is heap-owned by the kernel. Copy out before
    // returning, then release through the documented `nmp_app_free_string`
    // path — same convention `KernelBridge.swift` follows. Using
    // `CString::from_raw` would bypass any future bookkeeping the kernel adds
    // to that free.
    let owned = unsafe { CStr::from_ptr(envelope_ptr) }
        .to_string_lossy()
        .into_owned();
    nmp_app_free_string(envelope_ptr);
    match env.new_string(owned) {
        Ok(js) => js.into_raw(),
        Err(_) => null,
    }
}

/// `nativeSigninNsec(handle, nsec)` — one-shot sign-in via local nsec.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeSigninNsec<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    handle: jlong,
    nsec: JString<'l>,
) {
    let Some(s) = session_ref(handle) else {
        return;
    };
    let secret = match env.get_string(&nsec) {
        Ok(s) => s.to_string_lossy().into_owned(),
        Err(_) => return,
    };
    let Ok(c_secret) = CString::new(secret) else {
        return;
    };
    nmp_app_signin_nsec(s.app, c_secret.as_ptr());
}

/// `nativeNextUpdate(handle)` — blocking drain of the snapshot channel with a
/// 250 ms timeout. Returns `null` on timeout or closed channel.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeNextUpdate<'l>(
    env: JNIEnv<'l>,
    _class: JClass<'l>,
    handle: jlong,
) -> jstring {
    let null = std::ptr::null_mut();
    let Some(s) = session_ref(handle) else {
        return null;
    };
    match s.rx.recv_timeout(Duration::from_millis(250)) {
        Ok(json) => match env.new_string(json) {
            Ok(js) => js.into_raw(),
            Err(_) => null,
        },
        Err(RecvTimeoutError::Timeout) | Err(RecvTimeoutError::Disconnected) => null,
    }
}

/// `nativePodcastSnapshot(handle)` — pull the Podcast projection JSON.
/// Returns `null` if no snapshot is available.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativePodcastSnapshot<'l>(
    env: JNIEnv<'l>,
    _class: JClass<'l>,
    handle: jlong,
) -> jstring {
    let null = std::ptr::null_mut();
    let Some(s) = session_ref(handle) else {
        return null;
    };
    if s.podcast.is_null() {
        return null;
    }
    let ptr = nmp_app_podcast_snapshot(s.podcast);
    if ptr.is_null() {
        return null;
    }
    // SAFETY: `ptr` is a heap-owned `CString` from `nmp_app_podcast_snapshot`.
    let json = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned();
    nmp_app_podcast_snapshot_free(ptr);
    match env.new_string(json) {
        Ok(js) => js.into_raw(),
        Err(_) => null,
    }
}

/// `nmpActionDispatch(actionJson)` — M13.A stub for the namespace-agnostic
/// action dispatch surface. Returns `-1` on any parse failure; `0` on success.
///
/// **D6:** never panics, never throws.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nmpActionDispatch<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    action_json: JString<'l>,
) -> jint {
    let Ok(body) = env.get_string(&action_json) else {
        return -1;
    };
    let body = body.to_string_lossy().into_owned();
    let parsed: serde_json::Value = match serde_json::from_str(&body) {
        Ok(v) => v,
        Err(_) => return -1,
    };
    let action_id = parsed
        .get("id")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("<missing>");
    // M13.B will wire this through the kernel's action dispatch path.
    let _ = action_id;
    0
}

/// `nmpCapabilityReport(namespace, reportJson)` — M13.A stub for the
/// host → kernel capability-report channel. Returns `-1` on any input failure;
/// `0` on success.
///
/// **D6:** never panics, never throws.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nmpCapabilityReport<'l>(
    mut env: JNIEnv<'l>,
    _class: JClass<'l>,
    namespace: JString<'l>,
    report_json: JString<'l>,
) -> jint {
    let Ok(ns) = env.get_string(&namespace) else {
        return -1;
    };
    let Ok(body) = env.get_string(&report_json) else {
        return -1;
    };
    let ns = ns.to_string_lossy().into_owned();
    let body = body.to_string_lossy().into_owned();
    // Validate the JSON shape early.
    if serde_json::from_str::<serde_json::Value>(&body).is_err() {
        return -1;
    }
    // M13.B will dispatch this through the kernel's capability report sink.
    let _ = (ns, body);
    0
}
