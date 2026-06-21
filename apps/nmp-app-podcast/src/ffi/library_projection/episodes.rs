//! FFI projections for episode-oriented library queries.

use std::ffi::{c_char, CStr};

use super::helpers::{encode, episode_matches_filter, episode_matches_query, is_archived};
use super::types::{
    AllEpisodesRequest, AllEpisodesResponse, EpisodeForAudioUrlRequest, EpisodeForAudioUrlResponse,
    EpisodeLookupRequest, EpisodeLookupResponse, ShowEpisodesRequest, ShowEpisodesResponse,
    StarredEpisodesResponse,
};
use crate::ffi::guard::ffi_guard;
use crate::ffi::handle::PodcastHandle;

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_show_episodes(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_library_show_episodes",
        std::ptr::null_mut,
        || {
            let request_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            let request: ShowEpisodesRequest = match serde_json::from_str(request_str) {
                Ok(r) => r,
                Err(_) => return std::ptr::null_mut(),
            };
            let podcast_id = request.podcast_id.to_lowercase();
            let limit = request.limit.clamp(1, 10_000);
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => {
                    let mut rows = Vec::new();
                    for (podcast, episodes) in store.all_podcasts() {
                        if podcast.id.0.to_string() != podcast_id {
                            continue;
                        }
                        rows = episodes
                            .into_iter()
                            .filter(|episode| !is_archived(&store, episode))
                            .map(|episode| (episode.pub_date.timestamp(), episode.id.0.to_string()))
                            .collect();
                        break;
                    }
                    rows.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
                    ShowEpisodesResponse {
                        episode_ids: rows.into_iter().take(limit).map(|(_, id)| id).collect(),
                    }
                }
                Err(_) => ShowEpisodesResponse {
                    episode_ids: Vec::new(),
                },
            };
            encode(&response)
        },
    )
}

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_all_episodes(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_library_all_episodes",
        std::ptr::null_mut,
        || {
            let request_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            let request: AllEpisodesRequest = match serde_json::from_str(request_str) {
                Ok(r) => r,
                Err(_) => return std::ptr::null_mut(),
            };
            let query = request.query.trim().to_lowercase();
            let limit = request.limit.clamp(1, 10_000);
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => {
                    let mut rows: Vec<(i64, String)> = store
                        .all_podcasts()
                        .into_iter()
                        .flat_map(|(_, episodes)| episodes)
                        .filter(|episode| !is_archived(&store, episode))
                        .filter(|episode| episode_matches_filter(episode, &request.filter))
                        .filter(|episode| episode_matches_query(episode, &query))
                        .map(|episode| (episode.pub_date.timestamp(), episode.id.0.to_string()))
                        .collect();
                    rows.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
                    let total_count = rows.len();
                    AllEpisodesResponse {
                        episode_ids: rows.into_iter().take(limit).map(|(_, id)| id).collect(),
                        total_count,
                    }
                }
                Err(_) => AllEpisodesResponse {
                    episode_ids: Vec::new(),
                    total_count: 0,
                },
            };
            encode(&response)
        },
    )
}

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_starred_episodes(
    handle: *mut PodcastHandle,
) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_library_starred_episodes",
        std::ptr::null_mut,
        || {
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => {
                    let mut rows: Vec<(i64, String)> = store
                        .all_podcasts()
                        .into_iter()
                        .flat_map(|(_, episodes)| episodes)
                        .filter(|episode| episode.is_starred && !is_archived(&store, episode))
                        .map(|episode| (episode.pub_date.timestamp(), episode.id.0.to_string()))
                        .collect();
                    rows.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
                    StarredEpisodesResponse {
                        episode_ids: rows.into_iter().map(|(_, id)| id).collect(),
                    }
                }
                Err(_) => StarredEpisodesResponse {
                    episode_ids: Vec::new(),
                },
            };
            encode(&response)
        },
    )
}

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_episode_lookup(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_library_episode_lookup",
        std::ptr::null_mut,
        || {
            let request_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            let request: EpisodeLookupRequest = match serde_json::from_str(request_str) {
                Ok(r) => r,
                Err(_) => return std::ptr::null_mut(),
            };
            let reference = request.reference.to_lowercase();
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => {
                    let episode_id = store
                        .all_podcasts()
                        .into_iter()
                        .flat_map(|(_, episodes)| episodes)
                        .find(|episode| {
                            episode.id.0.to_string() == reference
                                || episode.guid.to_lowercase() == reference
                        })
                        .map(|episode| episode.id.0.to_string());
                    EpisodeLookupResponse { episode_id }
                }
                Err(_) => EpisodeLookupResponse { episode_id: None },
            };
            encode(&response)
        },
    )
}

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_episode_for_audio_url(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_library_episode_for_audio_url",
        std::ptr::null_mut,
        || {
            let request_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            let request: EpisodeForAudioUrlRequest = match serde_json::from_str(request_str) {
                Ok(r) => r,
                Err(_) => return std::ptr::null_mut(),
            };
            let podcast_id = request.podcast_id.to_lowercase();
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => {
                    let episode_id = store
                        .all_podcasts()
                        .into_iter()
                        .find(|(podcast, _)| podcast.id.0.to_string() == podcast_id)
                        .and_then(|(_, episodes)| {
                            episodes
                                .into_iter()
                                .find(|episode| episode.enclosure_url.as_str() == request.audio_url)
                                .map(|episode| episode.id.0.to_string())
                        });
                    EpisodeForAudioUrlResponse { episode_id }
                }
                Err(_) => EpisodeForAudioUrlResponse { episode_id: None },
            };
            encode(&response)
        },
    )
}
