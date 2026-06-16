//! Small shared helpers for the Podcast FFI surface: a null-aware C-string
//! reader and an HTML-to-plaintext converter for RSS show notes.

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

/// Strip HTML tags and decode common entities from an RSS `<description>`
/// field so the host receives plain text. Both iOS and Android benefit from
/// this at the kernel level (D0 — policy in Rust).
///
/// Thin delegate to the canonical [`podcast_core::strip_html`] so the FFI
/// snapshot projection and the kernel knowledge metadata-index path share one
/// implementation (one canonical representation, AGENTS.md §Engineering
/// discipline).
pub(super) fn strip_html(raw: &str) -> String {
    podcast_core::strip_html(raw)
}

#[cfg(test)]
#[path = "helpers_tests.rs"]
mod tests;
