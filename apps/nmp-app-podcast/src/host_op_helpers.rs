//! Free-function helpers used by [`crate::host_op_handler`].
//!
//! Extracted so `host_op_handler.rs` stays under the 500-LOC hard cap.
//! No kernel state — pure transforms.

use podcast_core::Episode;

/// Merge a freshly-parsed episode list onto an existing one, carrying forward
/// per-episode `position_secs` so a feed refresh doesn't reset resume points.
pub(crate) fn merge_episodes(fresh: Vec<Episode>, existing: Vec<Episode>) -> Vec<Episode> {
    fresh
        .into_iter()
        .map(|mut ep| {
            if let Some(prev) = existing.iter().find(|e| e.id == ep.id) {
                ep.position_secs = prev.position_secs;
            }
            ep
        })
        .collect()
}
