//! Free helper functions formerly inlined at the bottom of
//! `host_op_handler.rs`.
//!
//! Extracted to keep `host_op_handler.rs` under the 500-line hard limit.

use podcast_core::Episode;

/// Merge a freshly-parsed episode list against the prior in-store list,
/// preserving all user-local state so a feed refresh doesn't silently wipe it.
///
/// Fields preserved from the existing episode (not derivable from the feed):
/// `position_secs`, `played`, `is_starred`, `triage_decision`,
/// `triage_rationale`, `triage_is_hero`, `download_state`,
/// `transcript_state`, `ad_segments`, `generation_source`, `metadata_indexed`.
pub(crate) fn merge_episodes(fresh: Vec<Episode>, existing: Vec<Episode>) -> Vec<Episode> {
    fresh
        .into_iter()
        .map(|mut ep| {
            if let Some(prev) = existing.iter().find(|e| e.id == ep.id) {
                ep.position_secs = prev.position_secs;
                ep.played = prev.played;
                ep.is_starred = prev.is_starred;
                ep.triage_decision = prev.triage_decision.clone();
                ep.triage_rationale = prev.triage_rationale.clone();
                ep.triage_is_hero = prev.triage_is_hero;
                ep.download_state = prev.download_state.clone();
                ep.transcript_state = prev.transcript_state.clone();
                ep.ad_segments = prev.ad_segments.clone();
                ep.generation_source = prev.generation_source.clone();
                ep.metadata_indexed = prev.metadata_indexed;
            }
            ep
        })
        .collect()
}

#[cfg(test)]
#[path = "host_op_handler_helpers_tests.rs"]
mod tests;
