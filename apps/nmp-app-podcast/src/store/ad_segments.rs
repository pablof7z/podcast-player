//! Per-episode ad-segment side-map + auto-skip toggle accessors.
//!
//! Lives in its own file (rather than expanding `mod.rs`) so the store
//! stays focused on podcast/episode storage and the ad bookkeeping
//! can grow independently when the detection ingest pipeline lands.
//!
//! Persistence is handled by the parent module's `to_persisted` /
//! `load_from_disk` glue — every mutator here calls `self.persist()`
//! so the change survives an app restart.

use crate::player::AdSegment;

use super::PodcastStore;

impl PodcastStore {
    /// Return the stored ad-break list for `episode_id_str` (UUID
    /// hyphenated string form) or an empty slice when none is
    /// recorded. Empty result is the "no annotations yet" signal the
    /// UI uses to suppress skip indicators.
    pub fn ad_segments_for(&self, episode_id_str: &str) -> &[AdSegment] {
        self.ad_segments
            .get(episode_id_str)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }

    /// True when the AI compile pipeline has run ad detection for this
    /// episode and committed a result (even an empty one). Distinct from
    /// `ad_segments_for(..).is_empty()` because an empty segment list means
    /// "ran, found nothing" while `ad_detection_ran == false` means "never ran".
    ///
    /// Matches the Swift `episode.adSegments != nil` gate in `AIChapterCompiler`.
    pub fn ad_detection_ran(&self, episode_id_str: &str) -> bool {
        self.ad_segments.contains_key(episode_id_str)
    }

    /// Replace the ad-break list for `episode_id_str`. An empty
    /// `segments` vec records "detection ran, found nothing" (distinct
    /// from "never ran" — the key stays in the map either way, so
    /// [`PodcastStore::ad_detection_ran`] returns `true` after this call).
    ///
    /// Flushes to disk via `persist()` so the annotations survive a
    /// relaunch.
    pub fn set_ad_segments_for(
        &mut self,
        episode_id_str: impl Into<String>,
        segments: Vec<AdSegment>,
    ) {
        let key = episode_id_str.into();
        // Keep an empty vec so ad_detection_ran() can distinguish
        // "ran + found nothing" from "never ran". The wire projection
        // uses `skip_serializing_if = Vec::is_empty` so empty arrays
        // never pollute the snapshot JSON.
        self.ad_segments.insert(key, segments);
        self.persist();
    }

    /// Read the user's auto-skip-ads toggle. Mirrored into the
    /// settings projection on every snapshot tick.
    pub fn auto_skip_ads_enabled(&self) -> bool {
        self.auto_skip_ads_enabled
    }

    /// Set the auto-skip-ads toggle. Flushes to disk so a relaunch
    /// restores the user's choice. Idempotent — silently no-op when
    /// the value matches the current state.
    pub fn set_auto_skip_ads_enabled(&mut self, enabled: bool) {
        if self.auto_skip_ads_enabled == enabled {
            return;
        }
        self.auto_skip_ads_enabled = enabled;
        self.persist();
    }
}

#[cfg(test)]
#[path = "ad_segments_tests.rs"]
mod tests;
