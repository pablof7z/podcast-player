//! Episode-list merge helper used by `handle_refresh` to preserve a
//! user's playback position across a feed refresh.
//!
//! Extracted from `host_op_handler.rs` to keep that file under the
//! 500-line hard limit. The merge policy is intentionally narrow:
//! every entry that already exists in `existing` (matched by
//! `Episode::id`) carries forward its `position_secs`; everything else
//! on the freshly-parsed episode is kept as the source of truth. New
//! episodes (absent from `existing`) pass through unchanged.

use podcast_core::Episode;

/// Merge `fresh` (newly parsed from the feed) with `existing` (already
/// stored), preserving `position_secs` on episodes that appear in both
/// lists. Order follows `fresh`.
pub fn merge_episodes(fresh: Vec<Episode>, existing: Vec<Episode>) -> Vec<Episode> {
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
