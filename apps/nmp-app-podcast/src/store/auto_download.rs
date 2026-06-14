//! Pure auto-download policy helpers.
//!
//! Lifted out of [`super::PodcastStore`] / [`crate::host_op_handler`] so
//! the decision of *which* freshly-discovered episodes should be queued
//! for download can be unit-tested without standing up an `NmpApp` /
//! FFI mock.
//!
//! ## Doctrine
//!
//! * **D0 — Rust owns policy.** This module is the policy. The iOS
//!   `DownloadCapability` only executes the `StartDownload` commands
//!   the handler emits from these results.
//! * **D6 — pure data in/out.** No I/O, no logging, no side effects.
//!
//! ## D7 — Typed mode
//!
//! The kernel owns the typed `AutoDownloadMode` (Off / LatestN(u32) / AllNew).
//! iOS sends `mode` + `count` in the action; the kernel enforces the cap.
//! The projection surfaces `auto_download_mode` + `auto_download_count` so
//! the iOS picker can rehydrate real kernel state. A legacy `enabled: bool`
//! payload migrates: `true` → `AllNew`, `false` → `Off`.
//!
//! ## Identity
//!
//! Episodes are matched against the previously-known set by `guid` in the
//! first filter, with a belt-and-suspenders `EpisodeId` check in the second.
//! Both are now stable across refreshes: `Episode::new` derives the id via
//! UUIDv5 from `(feed_url, guid)`, and `guid` is the RSS-canonical stable key.
//! The accumulator (`podcast-feeds::rss::accumulator`) records all guids so
//! the first filter accurately reflects what the store already contains.

use std::collections::{HashMap, HashSet};

use podcast_core::{Episode, EpisodeId};
use serde::{Deserialize, Serialize};

/// Typed auto-download policy a show can be set to.
///
/// Wire representation: a JSON object `{"mode": "off"}`,
/// `{"mode": "all_new"}`, or `{"mode": "latest_n", "n": 5}`.
/// Rust uses `#[serde(tag = "mode", rename_all = "snake_case")]` so the
/// variant name maps to the `mode` field and `LatestN` carries an `n`
/// integer. This is the canonical form on both the action wire and the
/// projection wire — the iOS bridge's `.convertFromSnakeCase` turns
/// `auto_download_mode` → `autoDownloadMode` but the *value* of the
/// field is a plain String (`"all_new"`, `"latest_n"`, `"off"`), which
/// Swift handles separately from the key path.
///
/// Back-compat: `PersistedPodcast::auto_download_mode` is `Option<…>`;
/// absent (old file) ⇒ derived from the legacy `auto_download: bool`
/// field by `load_from_disk` (true→AllNew, false→Off).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "snake_case")]
pub enum AutoDownloadMode {
    /// Auto-download disabled. New episodes appear in the snapshot but are
    /// never queued for download automatically.
    Off,
    /// Keep the N most-recent undownloaded episodes on device. The backfill
    /// pass is bounded to `n` episodes; the fresh-feed pass takes at most `n`
    /// new arrivals per refresh.
    LatestN { n: u32 },
    /// Download every new episode the feed reports, with no episode cap.
    /// The backfill pass is library-size-aware: all episodes are queued for
    /// small/normal libraries; only genuinely large archives hit the
    /// `AUTO_DOWNLOAD_BACKFILL_SAFETY_CLAMP` ceiling to prevent queuing a
    /// 500-episode download storm on first enable.
    AllNew,
}

impl AutoDownloadMode {
    /// Returns `true` for any non-Off mode.
    pub fn is_enabled(self) -> bool {
        !matches!(self, AutoDownloadMode::Off)
    }

    /// Effective per-show backfill ceiling given the show's total episode count.
    ///
    /// - `Off` → 0 (caller short-circuits before this)
    /// - `LatestN(n)` → n as usize (exact count, unchanged)
    /// - `AllNew` → `candidate_count.min(AUTO_DOWNLOAD_BACKFILL_SAFETY_CLAMP)`
    ///   Queues every episode for normal-sized libraries; only engages the safety
    ///   clamp when the archive is genuinely large. This is a storage/bandwidth
    ///   guard on first-enable, not a product cap — forward-path episodes
    ///   (fresh-feed arrivals) are always uncapped via `fresh_cap()`.
    pub fn backfill_limit(self, candidate_count: usize) -> usize {
        match self {
            AutoDownloadMode::Off => 0,
            AutoDownloadMode::LatestN { n } => n as usize,
            AutoDownloadMode::AllNew => candidate_count.min(AUTO_DOWNLOAD_BACKFILL_SAFETY_CLAMP),
        }
    }

    /// Effective cap for the fresh-feed path:
    /// - `Off` → 0
    /// - `LatestN(n)` → Some(n as usize)
    /// - `AllNew` → None (no cap)
    pub fn fresh_cap(self) -> Option<usize> {
        match self {
            AutoDownloadMode::Off => Some(0),
            AutoDownloadMode::LatestN { n } => Some(n as usize),
            AutoDownloadMode::AllNew => None,
        }
    }
}

impl Default for AutoDownloadMode {
    /// Default for newly-subscribed shows: download every new episode.
    /// Matches `AutoDownloadPolicy.default` in Swift (`.allNew`).
    fn default() -> Self {
        AutoDownloadMode::AllNew
    }
}

/// Storage/bandwidth guard for `AllNew` backfill on first-enable of a large archive.
///
/// `backfill_limit()` for `AllNew` returns `candidate_count.min(this)`:
/// - Normal-sized libraries (episode count ≤ this) backfill ALL eligible episodes.
/// - Genuinely large archives (> this) are capped here to prevent queuing a
///   500-episode download storm the moment a user enables "All new".
///
/// This is NOT a product limit — it only governs the one-shot catch-up pass.
/// Every new episode arriving via a future feed refresh is still queued
/// unconditionally by the forward path (`fresh_cap()` for `AllNew` is `None`).
///
/// Does NOT apply to `LatestN(n)` (which uses `n` directly) or to the
/// fresh-feed path.
pub const AUTO_DOWNLOAD_BACKFILL_SAFETY_CLAMP: usize = 50;

/// Decide which freshly-parsed episodes deserve to be auto-queued for
/// download.
///
/// Inputs:
///
/// * `fresh` — the new episode list returned by the feed parser, newest-first.
/// * `existing_guids` — `guid` set captured *before* the store
///   accepted the refresh (any guid in this set is by definition
///   known and is not a "new" episode).
/// * `local_paths` — currently-known on-disk paths keyed by
///   `EpisodeId`. Belt-and-suspenders filter to avoid re-queuing a
///   fresh episode that somehow already has a local file.
/// * `mode` — the typed auto-download policy for this podcast.
///   `Off` short-circuits to an empty result immediately.
///   `LatestN(n)` caps the output to the `n` newest candidates.
///   `AllNew` imposes no cap.
/// * `wifi_only_on` — when `true`, only downloads when `is_on_wifi` is also
///   `true`. When `false`, downloads on any interface (cellular + Wi-Fi).
/// * `is_on_wifi` — current network-path state reported by
///   `nmp.network.capability`. Ignored when `wifi_only_on` is `false`.
///
/// Returns `(ready, deferred)` where:
/// - `ready` — episodes to dispatch for download immediately.
/// - `deferred` — episodes that would auto-download but are gated on Wi-Fi
///   while the device is currently on cellular. The caller must persist these
///   so they can be dispatched when `NetworkReport::ConnectivityChanged`
///   reports Wi-Fi restored; otherwise their guids become "existing" on the
///   next refresh and they are permanently skipped.
pub fn episodes_to_auto_download(
    fresh: &[Episode],
    existing_guids: &HashSet<String>,
    local_paths: &HashMap<EpisodeId, String>,
    mode: AutoDownloadMode,
    wifi_only_on: bool,
    is_on_wifi: bool,
) -> (Vec<(EpisodeId, String)>, Vec<(EpisodeId, String)>) {
    if !mode.is_enabled() {
        return (Vec::new(), Vec::new());
    }
    let cap = mode.fresh_cap(); // None = uncapped (AllNew), Some(n) = cap to n
    let candidates: Vec<(EpisodeId, String)> = fresh
        .iter()
        .filter(|ep| !existing_guids.contains(&ep.guid))
        .filter(|ep| !local_paths.contains_key(&ep.id))
        .take(cap.unwrap_or(usize::MAX))
        .map(|ep| (ep.id, ep.enclosure_url.to_string()))
        .collect();

    if wifi_only_on && !is_on_wifi {
        // Defer rather than discard: the caller persists these so they can be
        // dispatched when Wi-Fi is restored.
        return (Vec::new(), candidates);
    }
    (candidates, Vec::new())
}

impl super::PodcastStore {
    /// Scan the *current* library for episodes that auto-download policy says
    /// should be on disk but aren't — the catch-up counterpart to
    /// [`episodes_to_auto_download`], which only sees freshly-parsed feed
    /// episodes. Runs on cold start (the foreground `RefreshAll` is skipped on
    /// the first activation) and when the user enables auto-download on a show
    /// that already has episodes (the fresh-GUID filter would otherwise skip
    /// every existing episode, so flipping the toggle downloaded nothing).
    ///
    /// For each podcast with auto-download enabled, takes its most-recent
    /// `mode.backfill_limit(episode_count)` episodes that have no recorded local
    /// file, splitting them into `(ready, deferred)` by the show's Wi-Fi-only
    /// policy and the current `is_on_wifi` state. Episodes already in flight
    /// are filtered by the caller's idempotent enqueue, so re-running is safe.
    ///
    /// For `AllNew` shows the limit is library-size-aware: small/normal libraries
    /// backfill all episodes; only archives exceeding `AUTO_DOWNLOAD_BACKFILL_SAFETY_CLAMP`
    /// are capped. `LatestN(n)` always uses exactly `n`.
    ///
    /// The `limit_per_show` parameter is kept for API stability but is now
    /// overridden per-show by `mode.backfill_limit(episode_count)`.
    pub fn auto_download_backfill_candidates(
        &self,
        is_on_wifi: bool,
        _limit_per_show: usize,
    ) -> (Vec<(EpisodeId, String)>, Vec<(EpisodeId, String)>) {
        let mut ready = Vec::new();
        let mut deferred = Vec::new();
        for (&podcast_id, episodes) in self.episodes.iter() {
            let mode = self.auto_download_mode_for(podcast_id);
            if !mode.is_enabled() {
                continue;
            }
            // Pass the show's episode count so AllNew can be library-size-aware.
            let limit = mode.backfill_limit(episodes.len());
            let wifi_only = self.wifi_only_for(podcast_id);
            let mut taken = 0usize;
            for ep in episodes.iter() {
                if taken >= limit {
                    break;
                }
                if self.local_paths().contains_key(&ep.id) {
                    continue;
                }
                taken += 1;
                let item = (ep.id, ep.enclosure_url.to_string());
                if wifi_only && !is_on_wifi {
                    deferred.push(item);
                } else {
                    ready.push(item);
                }
            }
        }
        (ready, deferred)
    }
}

#[cfg(test)]
#[path = "auto_download_tests.rs"]
mod tests;
