//! Pure metadata-index backfill policy helpers.
//!
//! Lifted out of the Swift `EpisodeMetadataIndexer.runBackfill` shell so the
//! decision of *which* episodes should be embedded (and in what batch size /
//! pacing) is kernel-owned and unit-testable without the iOS executor.
//!
//! ## Doctrine
//!
//! * **D0 — Rust owns policy.** This module is the policy. The iOS
//!   `EpisodeMetadataIndexer` only executes the embed call + dispatches
//!   `MarkEpisodesMetadataIndexed` on success.
//! * **D6 — pure data in/out.** No I/O, no logging, no side effects.
//!
//! ## How it surfaces to the shell
//!
//! `metadata_index_backfill_candidates` is called from the Library domain
//! payload builder and its result rides the push frame as
//! `PodcastUpdate.pending_metadata_index_ids`.  The shell drains this list,
//! calls `upsert(chunks:)`, and dispatches `MarkEpisodesMetadataIndexed` on
//! success.  On failure it stops (halt-on-failure parity) and waits for the
//! next frame — the kernel will re-surface the same candidates until they are
//! marked indexed.
//!
//! ## Ordering
//!
//! Episodes are returned in publication-date order (oldest-first within each
//! podcast, pods iterated by internal HashMap order — consistent within a
//! single run but not guaranteed across restarts).  A stable ordering is not
//! required for correctness; the shell is free to re-order for UX.
//!
//! ## Why a flat batch instead of per-show batches
//!
//! Metadata indexing is a library-wide concern (the Swift `EpisodeMetadataIndexer`
//! already treated it that way).  Grouping by podcast adds no correctness benefit
//! and complicates the shell executor without improving the user experience.

use super::PodcastStore;

/// Number of episode IDs surfaced per projection frame.
///
/// Chosen to match the value the Swift shell previously used (`batchSize = 32`).
/// Capped at 32 so a 5,000-episode cold-start backfill stays responsive and
/// respects rate limits on the embeddings provider.  Each batch completes before
/// the next frame is emitted (the shell dispatches `MarkEpisodesMetadataIndexed`
/// which bumps `Domain::Library`, triggering a new projection frame with the
/// next batch).
pub const METADATA_INDEX_BACKFILL_BATCH_SIZE: usize = 32;

/// Pause between backfill batches in milliseconds.
///
/// Surfaces to Swift as `PodcastUpdate.metadata_index_inter_batch_delay_ms`.
/// The shell uses this as the sleep duration between successive embed calls.
/// Chosen to match the former Swift constant (`interBatchDelayNanoseconds =
/// 200_000_000`, i.e. 200 ms) — cheap insurance against rate-limiting the
/// embeddings provider on a cold launch with a large library.
pub const METADATA_INDEX_INTER_BATCH_DELAY_MS: u32 = 200;

impl PodcastStore {
    /// Return the next batch of episode IDs that need metadata indexing.
    ///
    /// Scans all known episodes (across every podcast), filters out those whose
    /// `metadata_indexed` flag is already set, and returns at most
    /// [`METADATA_INDEX_BACKFILL_BATCH_SIZE`] episode IDs (hyphenated UUID strings).
    ///
    /// **Returns an empty `Vec` when everything is already indexed** — the shell
    /// must stop its executor loop when the returned slice is empty.
    ///
    /// The scan is episode-level (not show-level) so one problematic podcast's
    /// episodes don't block the rest of the library.
    ///
    /// ## Ordering
    ///
    /// Episodes are iterated in the order stored per-podcast.  Within a show
    /// episodes are stored newest-first (RSS parser contract), so the returned
    /// batch is a mix of episodes from different shows — the shell may see a
    /// mix of old and new episodes across shows.  This is fine: the embed
    /// quality is not ordering-sensitive.
    pub fn metadata_index_backfill_candidates(&self) -> Vec<String> {
        let mut candidates = Vec::with_capacity(METADATA_INDEX_BACKFILL_BATCH_SIZE);
        'outer: for episodes in self.episodes.values() {
            for ep in episodes {
                let id_str = ep.id.0.to_string();
                if !self.metadata_indexed_episodes.contains(&id_str) {
                    candidates.push(id_str);
                    if candidates.len() >= METADATA_INDEX_BACKFILL_BATCH_SIZE {
                        break 'outer;
                    }
                }
            }
        }
        candidates
    }
}

#[cfg(test)]
#[path = "metadata_index_backfill_tests.rs"]
mod tests;
