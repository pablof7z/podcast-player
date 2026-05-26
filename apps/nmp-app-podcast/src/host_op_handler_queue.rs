//! Queue-action handler for `podcast.queue.*` host ops.
//!
//! Extracted into a sibling module so [`crate::host_op_handler`] stays under
//! the 500-line ceiling. The function operates over the same shared state
//! (`PlaybackQueue` + `rev`) the `PodcastHostOpHandler` carries, but does
//! not need the `NmpApp` pointer or any capability dispatcher — queue
//! mutations are pure in-memory writes.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use crate::ffi::actions::queue_module::QueueAction;
use crate::queue::PlaybackQueue;

/// Apply a [`QueueAction`] to the shared queue and bump `rev` so the next
/// snapshot poll surfaces the change.
///
/// Returns the canonical `{"ok": true}` envelope on success; a typed error
/// envelope when the queue mutex is poisoned (D6).
pub(crate) fn handle_queue_action(
    queue: &Arc<Mutex<PlaybackQueue>>,
    rev: &Arc<AtomicU64>,
    action: QueueAction,
) -> serde_json::Value {
    let mut q = match queue.lock() {
        Ok(q) => q,
        Err(_) => return serde_json::json!({"ok": false, "error": "queue poisoned"}),
    };
    match action {
        QueueAction::AddNext { episode_id } => q.add_to_front(&episode_id),
        QueueAction::AddLast { episode_id } => q.add_to_end(&episode_id),
        QueueAction::Remove { episode_id } => q.remove(&episode_id),
        QueueAction::Clear => q.clear(),
    }
    drop(q);
    rev.fetch_add(1, Ordering::Relaxed);
    serde_json::json!({"ok": true})
}

#[cfg(test)]
#[path = "host_op_handler_queue_tests.rs"]
mod tests;
