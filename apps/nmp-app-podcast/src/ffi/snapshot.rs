//! Snapshot + unregister entry points the host calls against a
//! [`PodcastHandle`] returned by [`super::register::nmp_app_podcast_register`].

use std::ffi::{c_char, CString};

use super::handle::PodcastHandle;

/// Serialize the current app state into a JSON C string.
///
/// Returns null on any failure (null handle, JSON encode error, `CString`
/// nul-byte conflict). The returned pointer is owned by the caller; pass it
/// to [`nmp_app_podcast_snapshot_free`] when done.
///
/// The stub payload is `{"running":true,"rev":0,"schema_version":1}`.
/// Podcast-domain fields (feed list, playback state, episode queue, etc.)
/// will be added in subsequent milestones as the corresponding projections
/// are implemented.
#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_snapshot(handle: *mut PodcastHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    // SAFETY: caller guarantees `handle` is a valid pointer returned by
    // `nmp_app_podcast_register` and not yet freed.
    let _handle = unsafe { &*handle };

    // Stub snapshot — replaced in subsequent milestones with a real projection
    // serialization (NIP-74 feed list, playback state, episode queue, etc.).
    let payload = r#"{"running":true,"rev":0,"schema_version":1}"#;
    let Ok(cstr) = CString::new(payload) else {
        return std::ptr::null_mut();
    };
    cstr.into_raw()
}

/// Free a snapshot string previously returned by [`nmp_app_podcast_snapshot`].
/// Null pointer is a silent no-op.
#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_snapshot_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    // SAFETY: caller guarantees `ptr` came from `CString::into_raw` in
    // `nmp_app_podcast_snapshot` and has not been freed.
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

/// Drop the handle and free associated resources.
/// Idempotent: null pointer is a silent no-op. The handle MUST NOT be used
/// after this call.
#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_unregister(handle: *mut PodcastHandle) {
    if handle.is_null() {
        return;
    }
    // SAFETY: caller guarantees `handle` came from `nmp_app_podcast_register`
    // and has not already been freed.
    let boxed = unsafe { Box::from_raw(handle) };
    // Future milestones will use `boxed.app` to call
    // `app_ref.unregister_event_observer(observer_id)` for each registered
    // projection. For now the handle carries the `app` pointer so subsequent
    // milestones can add unregister logic here without changing the FFI type.
    let _ = boxed.app;
    // boxed dropped here.
}
