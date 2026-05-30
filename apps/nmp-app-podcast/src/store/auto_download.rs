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

/// Decide which freshly-parsed episodes deserve to be auto-queued for
/// download.
///
/// Inputs:
///
/// * `fresh` — the new episode list returned by the feed parser.
/// * `existing_guids` — `guid` set captured *before* the store
///   accepted the refresh (any guid in this set is by definition
///   known and is not a "new" episode).
/// * `local_paths` — currently-known on-disk paths keyed by
///   `EpisodeId`. Used as a belt-and-suspenders filter so a fresh
///   episode that somehow already has a local file recorded for it
///   isn't re-queued.
/// * `auto_download_on` — whether the user has enabled auto-download
///   for the owning podcast. Short-circuits to an empty Vec when
///   `false`.
///
/// Output: an ordered list of `(EpisodeId, enclosure_url)` pairs the
/// handler should dispatch as `DownloadCommand::StartDownload` (one per
/// command). Ordering mirrors the input `fresh` slice (newest-first
/// per the parser's contract).
///
/// * `wifi_only_on` — when `true`, only downloads when `is_on_wifi` is also
///   `true`. When `false`, downloads on any interface (cellular + Wi-Fi).
/// * `is_on_wifi` — current network-path state reported by
///   `nmp.network.capability`. Ignored when `wifi_only_on` is `false`.
pub fn episodes_to_auto_download(
    fresh: &[Episode],
    existing_guids: &HashSet<String>,
    local_paths: &HashMap<EpisodeId, String>,
    auto_download_on: bool,
    wifi_only_on: bool,
    is_on_wifi: bool,
) -> Vec<(EpisodeId, String)> {
    if !auto_download_on {
        return Vec::new();
    }
    if wifi_only_on && !is_on_wifi {
        return Vec::new();
    }
    fresh
        .iter()
        .filter(|ep| !existing_guids.contains(&ep.guid))
        .filter(|ep| !local_paths.contains_key(&ep.id))
        .map(|ep| (ep.id, ep.enclosure_url.to_string()))
        .collect()
}

#[cfg(test)]
#[path = "auto_download_tests.rs"]
mod tests;
