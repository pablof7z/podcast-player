//! Small shared helpers for the Podcast FFI surface: a null-aware C-string
//! reader for the bespoke Podcast registration entry points.

use std::ffi::{c_char, CStr};

pub(super) fn c_string_opt(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    // SAFETY: caller guarantees `ptr` (when non-null) is a valid
    // nul-terminated C string for the duration of this call.
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .ok()
        .map(std::borrow::ToOwned::to_owned)
}
