use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::mpsc::Sender;

use jni::objects::{GlobalRef, JClass, JObject, JString, JValue};
use jni::sys::jlong;
use jni::JNIEnv;
use jni::JavaVM;
use nmp_ffi::nmp_app_set_capability_callback;

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

fn capability_error_envelope(message: &str) -> *mut c_char {
    let json = format!(
        "{{\"namespace\":\"\",\"correlation_id\":\"\",\"result_json\":\"{{\\\"status\\\":\\\"error\\\",\\\"message\\\":\\\"{message}\\\"}}\"}}"
    );
    CString::new(json)
        .unwrap_or_else(|_| CString::new("{}").expect("static JSON has no NUL"))
        .into_raw()
}

/// Build the `{"namespace","correlation_id","result_json"}` ack envelope a
/// dispatched (channel-routed) `external_signer` request returns synchronously.
/// The real signer result arrives later through `nativeDeliverSignerResponse`.
fn capability_dispatched_envelope(correlation_id: &str) -> *mut c_char {
    let json = serde_json::json!({
        "namespace": EXTERNAL_SIGNER_NAMESPACE,
        "correlation_id": correlation_id,
        "result_json": r#"{"status":"dispatched"}"#,
    })
    .to_string();
    CString::new(json)
        .unwrap_or_else(|_| CString::new("{}").expect("static JSON has no NUL"))
        .into_raw()
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
) -> Option<*mut c_char> {
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

extern "C" fn android_capability_callback(
    context: *mut c_void,
    request_json: *const c_char,
) -> *mut c_char {
    if context.is_null() || request_json.is_null() {
        return capability_error_envelope("null-args");
    }
    ffi_guard(
        "android_capability_callback",
        || capability_error_envelope("panic"),
        || {
            // SAFETY: registered by nativeSetCapabilityRouter; cleared before
            // drop. AssertUnwindSafe is sound — ptr is null-checked above and
            // not observed again on the panic path.
            let ctx = unsafe { &*(context as *const AndroidCapabilityContext) };
            let request = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return capability_error_envelope("bad-utf8"),
            };

            // ADR-0048 — the `external_signer` namespace is async (an Amber
            // Intent round-trip cannot resolve inside this synchronous
            // callback). Split it onto the signer-request channel and ack
            // `dispatched`; the real result arrives later via
            // `nativeDeliverSignerResponse`. Every other namespace falls
            // through to the synchronous Kotlin router below (D7 — the host
            // never decides; this routing is a mechanical wire consequence).
            if let Some(envelope) = maybe_dispatch_external_signer(ctx, request) {
                return envelope;
            }

            let mut env = match ctx.vm.attach_current_thread() {
                Ok(env) => env,
                Err(_) => return capability_error_envelope("attach-failed"),
            };
            let j_request = match env.new_string(request) {
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
            let response = match env.get_string(&JString::from(obj)) {
                Ok(s) => s.to_string_lossy().into_owned(),
                Err(_) => return capability_error_envelope("response-utf8-failed"),
            };
            CString::new(response)
                .unwrap_or_else(|_| CString::new("{}").expect("static JSON has no NUL"))
                .into_raw()
        },
    )
}

pub(super) fn clear_capability_router(session: &super::Session) {
    nmp_app_set_capability_callback(session.app, std::ptr::null_mut(), None);
    if let Ok(mut slot) = session.capability_ctx.lock() {
        if let Some(ctx) = slot.take() {
            // SAFETY: allocated with Box::into_raw in nativeSetCapabilityRouter.
            unsafe {
                drop(Box::from_raw(ctx));
            }
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
        clear_capability_router(s);
        if router.is_null() {
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
        let ctx = Box::into_raw(Box::new(AndroidCapabilityContext {
            vm,
            router: global,
            // ADR-0048 — the trampoline pushes `external_signer` requests onto
            // the session's signer channel; clone its sender into the context.
            signer_requests: s.signer_requests.clone(),
        }));
        nmp_app_set_capability_callback(
            s.app,
            ctx as *mut c_void,
            Some(android_capability_callback),
        );
        if let Ok(mut slot) = s.capability_ctx.lock() {
            *slot = Some(ctx);
        } else {
            nmp_app_set_capability_callback(s.app, std::ptr::null_mut(), None);
            // SAFETY: the callback has been cleared, so reclaim the new box.
            unsafe {
                drop(Box::from_raw(ctx));
            }
        }
    });
}
