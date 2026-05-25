//! Free helper functions formerly inlined at the bottom of
//! `host_op_handler.rs`.
//!
//! Extracted to keep `host_op_handler.rs` under the 500-line hard limit.

use podcast_core::Episode;

/// Merge a freshly-parsed episode list against the prior in-store list,
/// preserving `position_secs` so a refresh does not lose listening progress.
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
