//! `nmp_app_podcast_download_report` — async iOS→Rust download-report channel.
//!
//! The iOS `DownloadCapability` fires this FFI entry point whenever its
//! background `URLSession` delegate has a new `DownloadReport` to deliver
//! (`Completed`, `Cancelled`, …). Rust projects the report onto both the
//! [`crate::download::DownloadQueue`] state machine and the persisted
//! [`crate::store::PodcastStore`] (for `local_path` on `Completed`), then
//! dispatches any follow-up [`crate::capability::DownloadCommand`]s that the
//! queue emits (e.g. `StartDownload` for the next queued item).
//!
//! ## Wire protocol
//!
//! * **Request**: `report_json` is a JSON-encoded
//!   [`crate::capability::DownloadReport`].
//! * **Response**: always `NULL` — follow-up commands are dispatched
//!   internally via `NmpApp::dispatch_capability` so iOS doesn't need to
//!   handle the multi-command case. The return pointer is reserved for a
//!   future "ack" shape without an ABI break.
//!
//! ## Lock discipline
//!
//! Each lock (queue, store) is held for the minimal duration:
//!   1. Lock queue → `handle_report()` → collect follow-up commands → drop.
//!   2. Lock store → `apply_download_report()` → drop.
//!   3. Bump `rev`.
//!   4. Dispatch follow-up commands (no lock held).
//! Never hold two locks at once; never hold either lock across a capability
//! dispatch.
//!
//! ## D6 — degrade silently
//!
//! Null pointers, invalid UTF-8, lock poison, and decode failures all
//! return `NULL`. Nothing panics across the FFI.

use std::ffi::{c_char, CStr};
use std::sync::atomic::Ordering;

use nmp_core::substrate::CapabilityRequest;

use super::handle::PodcastHandle;
use crate::capability::dispatch::apply_download_report;
use crate::capability::{DownloadReport, DOWNLOAD_CAPABILITY_NAMESPACE};

/// Deliver a JSON-encoded `DownloadReport` to the Rust kernel.
///
/// Routes the report through `DownloadQueue::handle_report` (queue state
/// machine) and `apply_download_report` (store persistence), then dispatches
/// any follow-up `DownloadCommand`s (e.g. `StartDownload` for the next queued
/// item) internally. Always returns `NULL` — see wire-protocol note above.
#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_download_report(
    handle: *mut PodcastHandle,
    report_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || report_json.is_null() {
        return std::ptr::null_mut();
    }

    let report_str = match unsafe { CStr::from_ptr(report_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let report: DownloadReport = match serde_json::from_str(report_str) {
        Ok(r) => r,
        Err(_) => return std::ptr::null_mut(), // D6: malformed JSON → silent no-op
    };

    let handle_ref = unsafe { &*handle };

    // 1. Queue projection — collect follow-up commands (lock dropped after).
    let follow_up_cmds = match handle_ref.download_queue.lock() {
        Ok(mut q) => q.handle_report(report.clone()),
        Err(_) => return std::ptr::null_mut(),
    };

    // 2. Store projection — persist local_path on Completed, clear on Cancelled.
    if let Ok(mut store) = handle_ref.store.lock() {
        apply_download_report(&mut store, report);
    }

    // 3. Bump rev so the next snapshot tick reflects both mutations.
    handle_ref.rev.fetch_add(1, Ordering::Relaxed);

    // 4. Dispatch follow-up commands (no locks held).
    let app_ref = unsafe { &*handle_ref.app };
    for cmd in &follow_up_cmds {
        if let Ok(payload_json) = serde_json::to_string(cmd) {
            let req = CapabilityRequest {
                namespace: DOWNLOAD_CAPABILITY_NAMESPACE.to_owned(),
                correlation_id: "download-queue-follow-up".to_owned(),
                payload_json,
            };
            let _ = app_ref.dispatch_capability(&req);
        }
    }

    std::ptr::null_mut()
}
