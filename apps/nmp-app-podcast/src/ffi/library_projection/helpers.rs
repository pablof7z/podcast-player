//! Shared helper functions for Library screen projections.

use std::ffi::{c_char, CString};

use podcast_core::{DownloadState, TriageDecision};
use serde::Serialize;

pub(super) fn default_limit() -> usize {
    5_000
}

pub(super) fn default_all_episodes_limit() -> usize {
    50
}

pub(super) fn encode<T: Serialize>(value: &T) -> *mut c_char {
    match serde_json::to_string(value) {
        Ok(json) => match CString::new(json) {
            Ok(c) => c.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

pub(super) fn is_archived(store: &crate::store::PodcastStore, episode: &podcast_core::Episode) -> bool {
    let episode_id = episode.id.0.to_string();
    let stored_triage = store.triage_for(&episode_id).map(|(d, _, _)| d);
    episode.triage_decision.as_ref() == Some(&TriageDecision::Archived)
        || stored_triage.map(|d| d.as_str()) == Some("archived")
}

pub(super) fn is_in_progress(episode: &podcast_core::Episode) -> bool {
    if episode.played {
        return false;
    }
    match episode.duration_secs {
        Some(total) if total > 0.0 => {
            let fraction = episode.position_secs / total;
            fraction > 0.0001 && fraction < 0.999
        }
        _ => episode.position_secs > 0.0,
    }
}

pub(super) fn episode_matches_filter(episode: &podcast_core::Episode, filter: &str) -> bool {
    match filter {
        "all" => true,
        "unplayed" => !episode.played && !is_in_progress(episode),
        "inProgress" | "in_progress" => is_in_progress(episode),
        "downloaded" => matches!(episode.download_state, DownloadState::Downloaded { .. }),
        "starred" => episode.is_starred,
        _ => true,
    }
}

pub(super) fn episode_matches_query(episode: &podcast_core::Episode, query: &str) -> bool {
    if query.is_empty() {
        return true;
    }
    let title = episode.title.to_lowercase();
    let description = episode.description.to_lowercase();
    title.contains(query) || description.contains(query)
}

pub(super) fn podcast_matches_query(podcast: &podcast_core::Podcast, query: &str) -> bool {
    if query.is_empty() {
        return true;
    }
    let title = podcast.title.to_lowercase();
    let author = podcast.author.to_lowercase();
    let feed_host = podcast
        .feed_url
        .as_ref()
        .and_then(|url| url.host_str())
        .unwrap_or("")
        .to_lowercase();
    title.contains(query) || author.contains(query) || feed_host.contains(query)
}
