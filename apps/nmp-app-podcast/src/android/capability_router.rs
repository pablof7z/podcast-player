use std::sync::atomic::Ordering;

use crossbeam_channel::Sender;

use jni::objects::{GlobalRef, JClass, JObject, JString, JValue};
use jni::sys::jlong;
use jni::JNIEnv;
use jni::JavaVM;

use crate::ffi::guard::ffi_guard;

/// Wire constant — must match `nmp_signer_iface::EXTERNAL_SIGNER_NAMESPACE`
/// (and the `EXTERNAL_SIGNER_NAMESPACE` the NMP `nmp-android-ffi` trampoline
/// uses). The `external_signer` capability is interactive/async (an Amber
/// Intent round-trip), so it is split off the synchronous Kotlin router path
/// onto a channel drained by `nativeNextSignerRequest`. The string is part of
/// the stable capability wire; this crate does not depend on `nmp-signer-iface`.
const EXTERNAL_SIGNER_NAMESPACE: &str = "external_signer";

pub(super) struct AndroidCapabilityContext {
    vm: JavaVM,
    router: GlobalRef,
    /// ADR-0048 — clone of `Session.signer_requests`. The trampoline pushes the
    /// inner `external_signer` payload here instead of calling the synchronous
    /// Kotlin router; a Kotlin reader thread drains it via
    /// `nativeNextSignerRequest`.
    signer_requests: Sender<String>,
}

fn capability_error_envelope(message: &str) -> String {
    serde_json::json!({
        "namespace": "",
        "correlation_id": "",
        "result_json": serde_json::json!({"status": "error", "message": message}).to_string(),
    })
    .to_string()
}

/// Build the `{"namespace","correlation_id","result_json"}` ack envelope a
/// dispatched (channel-routed) `external_signer` request returns synchronously.
/// The real signer result arrives later through `nativeDeliverSignerResponse`.
fn capability_dispatched_envelope(correlation_id: &str) -> String {
    serde_json::json!({
        "namespace": EXTERNAL_SIGNER_NAMESPACE,
        "correlation_id": correlation_id,
        "result_json": r#"{"status":"dispatched"}"#,
    })
    .to_string()
}

/// If `request` carries the `external_signer` namespace, push its inner
/// `payload_json` onto the signer-request channel and return the `dispatched`
/// ack envelope. Returns `None` for every other namespace (the caller then
/// routes to the synchronous Kotlin capability router).
///
/// D6 — a dead channel (session torn down) or a malformed payload degrades to
/// an error envelope rather than a panic; the Rust-side correlation sender is
/// simply never resolved and the parked op times out.
fn maybe_dispatch_external_signer(
    ctx: &AndroidCapabilityContext,
    request: &str,
) -> Option<String> {
    let parsed: serde_json::Value = serde_json::from_str(request).ok()?;
    let namespace = parsed.get("namespace").and_then(|v| v.as_str())?;
    if namespace != EXTERNAL_SIGNER_NAMESPACE {
        return None;
    }
    let correlation_id = parsed
        .get("correlation_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let Some(payload) = parsed.get("payload_json").and_then(|v| v.as_str()) else {
        return Some(capability_error_envelope("missing-payload"));
    };
    match ctx.signer_requests.send(payload.to_string()) {
        Ok(()) => Some(capability_dispatched_envelope(correlation_id)),
        Err(_) => Some(capability_error_envelope("session-closed")),
    }
}

/// Capability-request handler installed via `nmp_uniffi_support::set_capability_callback`.
/// Receives the `CapabilityRequest` JSON as an owned `String` and returns the
/// `CapabilityEnvelope` JSON as an owned `String` — `nmp_uniffi_support` wraps
/// this closure in its own `catch_unwind` (falling back to a `sink-panicked`
/// error envelope), so `ffi_guard` here is defense-in-depth matching the rest
/// of this crate's FFI entry points, not the only panic backstop.
fn android_capability_handler(ctx: &AndroidCapabilityContext, request_json: String) -> String {
    ffi_guard(
        "android_capability_callback",
        || capability_error_envelope("panic"),
        || {
            // ADR-0048 — the `external_signer` namespace is async (an Amber
            // Intent round-trip cannot resolve inside this synchronous
            // callback). Split it onto the signer-request channel and ack
            // `dispatched`; the real result arrives later via
            // `nativeDeliverSignerResponse`. Every other namespace falls
            // through to the synchronous Kotlin router below (D7 — the host
            // never decides; this routing is a mechanical wire consequence).
            if let Some(envelope) = maybe_dispatch_external_signer(ctx, &request_json) {
                return envelope;
            }

            let mut env = match ctx.vm.attach_current_thread() {
                Ok(env) => env,
                Err(_) => return capability_error_envelope("attach-failed"),
            };
            let j_request = match env.new_string(&request_json) {
                Ok(s) => s,
                Err(_) => return capability_error_envelope("string-failed"),
            };
            let j_request_obj = JObject::from(j_request);
            let result = match env.call_method(
                ctx.router.as_obj(),
                "handle",
                "(Ljava/lang/String;)Ljava/lang/String;",
                &[JValue::Object(&j_request_obj)],
            ) {
                Ok(value) => value,
                Err(_) => return capability_error_envelope("router-call-failed"),
            };
            let obj = match result.l() {
                Ok(obj) if !obj.is_null() => obj,
                _ => return capability_error_envelope("router-returned-null"),
            };
            match env.get_string(&JString::from(obj)) {
                Ok(s) => s.to_string_lossy().into_owned(),
                Err(_) => capability_error_envelope("response-utf8-failed"),
            }
        },
    )
}

pub(super) fn clear_capability_router(session: &super::Session) {
    // The null-callback write and the `installed` flag clear MUST happen
    // inside the same lock that protects installs in
    // `nativeSetCapabilityRouter`. Moving the NMP call before the lock
    // creates a window where install writes a new sink to the slot after the
    // null write, silently reverting the fresh install.
    if let Ok(mut installed) = session.capability_ctx.lock() {
        if *installed {
            // SAFETY: `session.app` is a live pointer for the lifetime of the
            // Session (freed only in `Session::drop`, which runs after this
            // call returns — see the `nativeFree` ordering invariant).
            let sink: Option<Box<AndroidCapabilityContext>> = None;
            nmp_uniffi_support::set_capability_callback(
                unsafe { &*session.app },
                sink,
                android_capability_handler,
            );
            *installed = false;
        }
    }
}

/// `nativeSetCapabilityRouter(handle, router)` — register or clear Android's
/// `CapabilityRequest` router.
#[no_mangle]
pub extern "system" fn Java_io_f7z_podcast_KernelBridge_nativeSetCapabilityRouter<'l>(
    env: JNIEnv<'l>,
    _class: JClass<'l>,
    handle: jlong,
    router: JObject<'l>,
) {
    ffi_guard("nativeSetCapabilityRouter", || (), || {
        let Some(s) = super::session_ref(handle) else {
            return;
        };
        // Null router ⇒ clear only (safe to call concurrently with nativeFree;
        // capability_ctx lock inside clear_capability_router provides the gate).
        if router.is_null() {
            clear_capability_router(&s);
            return;
        }
        let vm = match env.get_java_vm() {
            Ok(vm) => vm,
            Err(_) => return,
        };
        let global = match env.new_global_ref(router) {
            Ok(g) => g,
            Err(_) => return,
        };
        // ADR-0048 — clone the sender out of the Mutex<Option<...>> while
        // guarding against a concurrent nativeFree that may have already taken
        // and dropped it (#600). If None, the session is being torn down; bail.
        let signer_tx = match s.signer_requests.lock().ok().and_then(|g| g.as_ref().cloned()) {
            Some(tx) => tx,
            None => return,
        };
        // All of: teardown check and the new callback install happen inside
        // the capability_ctx lock. This prevents a race where nativeFree's
        // clear_capability_router already ran (installed=false) before we
        // install, leaving the new sink untracked on an app being freed.
        //
        // Invariant: nativeFree sets shutting_down BEFORE calling
        // clear_capability_router. If we observe shutting_down=true here, either
        // clear_capability_router already ran (installed=false — install would
        // leak the sink past teardown) or it is waiting for this lock (in which
        // case it will clean up after we release). The flag check lets us
        // short-circuit the first case.
        let Ok(mut installed) = s.capability_ctx.lock() else {
            return;
        };
        if s.shutting_down.load(Ordering::Acquire) {
            return;
        }
        let ctx = AndroidCapabilityContext {
            vm,
            router: global,
            signer_requests: signer_tx,
        };
        // `nmp_uniffi_support::set_capability_callback` replaces (and drops)
        // any previously installed sink internally — no manual old-ctx clear
        // needed before installing the new one.
        // SAFETY: `s.app` is a live pointer for the lifetime of the Session.
        nmp_uniffi_support::set_capability_callback(
            unsafe { &*s.app },
            Some(Box::new(ctx)),
            android_capability_handler,
        );
        *installed = true;
        // Lock released here. If nativeFree was waiting on this lock, its
        // clear_capability_router will see `installed = true` and clean up.
    });
}
