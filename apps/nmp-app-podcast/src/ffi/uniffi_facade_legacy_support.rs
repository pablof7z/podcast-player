//! Shared adapters while explicit UniFFI methods still call the old Rust C-ABI internals.

use std::ffi::{c_char, CStr, CString};

use super::handle::PodcastHandle;

pub(super) type LegacyHandleJsonFn =
    extern "C" fn(*mut PodcastHandle, *const c_char) -> *mut c_char;
pub(super) type LegacyHandleFn = extern "C" fn(*mut PodcastHandle) -> *mut c_char;
pub(super) type LegacyGlobalJsonFn = extern "C" fn(*const c_char) -> *mut c_char;

pub(super) fn call_legacy_handle_json(
    handle: &PodcastHandle,
    request_json: &str,
    func: LegacyHandleJsonFn,
) -> Option<String> {
    let request = CString::new(request_json).ok()?;
    take_legacy_c_string(func(
        handle as *const PodcastHandle as *mut PodcastHandle,
        request.as_ptr(),
    ))
}

pub(super) fn call_legacy_handle(handle: &PodcastHandle, func: LegacyHandleFn) -> Option<String> {
    take_legacy_c_string(func(handle as *const PodcastHandle as *mut PodcastHandle))
}

pub(super) fn call_legacy_global_json(
    request_json: &str,
    func: LegacyGlobalJsonFn,
) -> Option<String> {
    let request = CString::new(request_json).ok()?;
    take_legacy_c_string(func(request.as_ptr()))
}

fn take_legacy_c_string(ptr: *mut c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let value = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe {
        drop(CString::from_raw(ptr));
    }
    Some(value)
}
