//! Rust-owned storage projections.
//!
//! Native enumerates raw files because the downloads directory is an OS
//! capability. Rust owns the semantic join against the podcast library, orphan
//! classification, show grouping, totals, and ordering.

use std::collections::{HashMap, HashSet};
use std::ffi::{c_char, CStr, CString};

use serde::{Deserialize, Serialize};

use crate::store::PodcastStore;

use super::guard::ffi_guard;
use super::handle::PodcastHandle;

#[derive(Debug, Deserialize)]
struct StorageBreakdownRequest {
    #[serde(default)]
    files: Vec<StorageFileFact>,
}

#[derive(Debug, Deserialize)]
struct StorageFileFact {
    #[serde(default)]
    episode_id: Option<String>,
    #[serde(default)]
    url: String,
    #[serde(default)]
    bytes: i64,
}

#[derive(Debug, Serialize)]
struct StorageBreakdownResponse {
    total_bytes: i64,
    shows: Vec<StorageShowRow>,
    orphan_bytes: i64,
    orphan_count: usize,
    orphan_urls: Vec<String>,
}

#[derive(Debug, Serialize)]
struct StorageShowRow {
    subscription_id: String,
    title: String,
    bytes: i64,
    episode_count: usize,
    episode_ids: Vec<String>,
}

#[derive(Debug)]
struct ShowAccum {
    title: String,
    bytes: i64,
    episode_ids: HashSet<String>,
}

fn encode<T: Serialize>(value: &T) -> *mut c_char {
    match serde_json::to_string(value) {
        Ok(json) => match CString::new(json) {
            Ok(c) => c.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

fn add_show_bytes(
    by_show: &mut HashMap<String, ShowAccum>,
    podcast_id: String,
    title: String,
    episode_id: String,
    bytes: i64,
) {
    let entry = by_show.entry(podcast_id).or_insert_with(|| ShowAccum {
        title,
        bytes: 0,
        episode_ids: HashSet::new(),
    });
    entry.bytes += bytes;
    entry.episode_ids.insert(episode_id);
}

fn build_storage_breakdown(
    store: &PodcastStore,
    files: Vec<StorageFileFact>,
) -> StorageBreakdownResponse {
    let mut episode_to_show: HashMap<String, (String, String)> = HashMap::new();
    let mut tracked_downloads: Vec<(String, String, String, i64)> = Vec::new();
    for (podcast, episodes) in store.all_podcasts() {
        let podcast_id = podcast.id.0.to_string();
        let title = if podcast.title.is_empty() {
            "Unknown show".to_string()
        } else {
            podcast.title.clone()
        };
        for episode in episodes {
            let episode_id = episode.id.0.to_string().to_lowercase();
            episode_to_show.insert(episode_id.clone(), (podcast_id.clone(), title.clone()));
            if store.local_path_for(&episode.id).is_some() {
                tracked_downloads.push((
                    episode_id,
                    podcast_id.clone(),
                    title.clone(),
                    store.file_size_for(&episode.id).unwrap_or(0).max(0),
                ));
            }
        }
    }

    let mut total_bytes = 0;
    let mut orphan_bytes = 0;
    let mut orphan_urls = HashSet::new();
    let mut by_show: HashMap<String, ShowAccum> = HashMap::new();
    let mut native_episode_ids = HashSet::new();

    for file in files {
        let bytes = file.bytes.max(0);
        total_bytes += bytes;
        let matched = file
            .episode_id
            .as_deref()
            .map(|id| id.to_lowercase())
            .and_then(|id| episode_to_show.get(&id).cloned().map(|show| (id, show)));
        match matched {
            Some((episode_id, (podcast_id, title))) => {
                native_episode_ids.insert(episode_id.clone());
                add_show_bytes(&mut by_show, podcast_id, title, episode_id, bytes);
            }
            None => {
                orphan_bytes += bytes;
                orphan_urls.insert(file.url);
            }
        }
    }

    for (episode_id, podcast_id, title, bytes) in tracked_downloads {
        if native_episode_ids.contains(&episode_id) {
            continue;
        }
        total_bytes += bytes;
        add_show_bytes(&mut by_show, podcast_id, title, episode_id, bytes);
    }

    let mut shows: Vec<StorageShowRow> = by_show
        .into_iter()
        .map(|(subscription_id, entry)| {
            let mut episode_ids: Vec<String> = entry.episode_ids.into_iter().collect();
            episode_ids.sort();
            StorageShowRow {
                subscription_id,
                title: entry.title,
                bytes: entry.bytes,
                episode_count: episode_ids.len(),
                episode_ids,
            }
        })
        .collect();
    shows.sort_by(|a, b| {
        b.bytes
            .cmp(&a.bytes)
            .then_with(|| a.title.to_lowercase().cmp(&b.title.to_lowercase()))
            .then_with(|| a.subscription_id.cmp(&b.subscription_id))
    });
    let mut orphan_urls: Vec<String> = orphan_urls.into_iter().collect();
    orphan_urls.sort();
    StorageBreakdownResponse {
        total_bytes,
        shows,
        orphan_bytes,
        orphan_count: orphan_urls.len(),
        orphan_urls,
    }
}

#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub fn nmp_app_podcast_storage_breakdown(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_storage_breakdown",
        std::ptr::null_mut,
        || {
            let request_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            let request: StorageBreakdownRequest = match serde_json::from_str(request_str) {
                Ok(r) => r,
                Err(_) => return std::ptr::null_mut(),
            };
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => build_storage_breakdown(&store, request.files),
                Err(_) => StorageBreakdownResponse {
                    total_bytes: 0,
                    shows: Vec::new(),
                    orphan_bytes: 0,
                    orphan_count: 0,
                    orphan_urls: Vec::new(),
                },
            };
            encode(&response)
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use podcast_core::{Episode, Podcast};

    fn make_episode(podcast_id: podcast_core::PodcastId) -> Episode {
        Episode::new(
            podcast_id,
            "https://example.com/feed.xml",
            "seeded-episode",
            "Seeded episode",
            url::Url::parse("https://example.com/audio/default.mp3").unwrap(),
            chrono::Utc::now(),
        )
    }

    fn store_with_downloaded_episode(bytes: i64) -> (PodcastStore, String) {
        let mut store = PodcastStore::new();
        let podcast = Podcast::new("This American Life");
        let podcast_id = podcast.id;
        let episode = make_episode(podcast_id);
        let episode_id = episode.id.0.to_string().to_lowercase();
        store.subscribe(podcast, vec![episode.clone()]);
        store.set_local_path(episode.id, "/tmp/seeded.mp3".to_string(), bytes);
        (store, episode_id)
    }

    #[test]
    fn storage_breakdown_counts_tracked_download_when_native_file_walk_is_empty() {
        let (store, episode_id) = store_with_downloaded_episode(240_000);

        let response = build_storage_breakdown(&store, Vec::new());

        assert_eq!(response.total_bytes, 240_000);
        assert_eq!(response.orphan_bytes, 0);
        assert_eq!(response.shows.len(), 1);
        assert_eq!(response.shows[0].title, "This American Life");
        assert_eq!(response.shows[0].bytes, 240_000);
        assert_eq!(response.shows[0].episode_ids, vec![episode_id]);
    }

    #[test]
    fn storage_breakdown_does_not_double_count_native_file_for_tracked_episode() {
        let (store, episode_id) = store_with_downloaded_episode(240_000);

        let response = build_storage_breakdown(
            &store,
            vec![StorageFileFact {
                episode_id: Some(episode_id),
                url: "/tmp/seeded.mp3".to_string(),
                bytes: 250_000,
            }],
        );

        assert_eq!(response.total_bytes, 250_000);
        assert_eq!(response.shows[0].bytes, 250_000);
        assert_eq!(response.orphan_bytes, 0);
    }

    #[test]
    fn storage_breakdown_keeps_unknown_files_as_orphans() {
        let (store, _) = store_with_downloaded_episode(240_000);

        let response = build_storage_breakdown(
            &store,
            vec![StorageFileFact {
                episode_id: None,
                url: "/tmp/stranded.mp3".to_string(),
                bytes: 4_096,
            }],
        );

        assert_eq!(response.total_bytes, 244_096);
        assert_eq!(response.shows[0].bytes, 240_000);
        assert_eq!(response.orphan_bytes, 4_096);
        assert_eq!(response.orphan_count, 1);
        assert_eq!(response.orphan_urls, vec!["/tmp/stranded.mp3"]);
    }
}
