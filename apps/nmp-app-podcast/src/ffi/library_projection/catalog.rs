//! FFI projections for podcast catalog, categories, downloads, subscriptions, and library summary.

use std::ffi::{c_char, CStr};

use podcast_core::{DownloadState, PodcastId, TranscriptState};

use super::helpers::{encode, is_archived, podcast_matches_query};
use super::types::{
    AllPodcastsRequest, AllPodcastsResponse, CategoriesRequest, CategoriesResponse, CategoryRow,
    DownloadRowsResponse, FollowedPodcastsResponse, LibrarySummaryResponse, OwnedPodcastsResponse,
    PodcastStatsRequest, PodcastStatsResponse, PodcastStatsRow, SubscriptionStatusRequest,
    SubscriptionStatusResponse,
};
use crate::ffi::guard::ffi_guard;
use crate::ffi::handle::PodcastHandle;

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_all_podcasts(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_library_all_podcasts",
        std::ptr::null_mut,
        || {
            let request_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            let request: AllPodcastsRequest = match serde_json::from_str(request_str) {
                Ok(r) => r,
                Err(_) => return std::ptr::null_mut(),
            };
            let query = request.query.trim().to_lowercase();
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => {
                    let mut rows: Vec<(String, String)> = store
                        .all_podcasts()
                        .into_iter()
                        .filter(|(podcast, _)| podcast.id != PodcastId::unknown())
                        .filter(|(podcast, _)| podcast_matches_query(podcast, &query))
                        .map(|(podcast, _)| {
                            (podcast.title.to_lowercase(), podcast.id.0.to_string())
                        })
                        .collect();
                    rows.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)));
                    AllPodcastsResponse {
                        podcast_ids: rows.into_iter().map(|(_, id)| id).collect(),
                    }
                }
                Err(_) => AllPodcastsResponse {
                    podcast_ids: Vec::new(),
                },
            };
            encode(&response)
        },
    )
}

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_followed_podcasts(
    handle: *mut PodcastHandle,
) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_library_followed_podcasts",
        std::ptr::null_mut,
        || {
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => {
                    let mut rows: Vec<(String, String)> = store
                        .all_podcasts()
                        .into_iter()
                        .filter(|(podcast, _)| store.is_subscribed(podcast.id))
                        .filter(|(podcast, _)| podcast.feed_url.is_some())
                        .map(|(podcast, _)| {
                            (podcast.title.to_lowercase(), podcast.id.0.to_string())
                        })
                        .collect();
                    rows.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)));
                    FollowedPodcastsResponse {
                        podcast_ids: rows.into_iter().map(|(_, id)| id).collect(),
                    }
                }
                Err(_) => FollowedPodcastsResponse {
                    podcast_ids: Vec::new(),
                },
            };
            encode(&response)
        },
    )
}

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_owned_podcasts(
    handle: *mut PodcastHandle,
) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_library_owned_podcasts",
        std::ptr::null_mut,
        || {
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => {
                    let mut rows: Vec<(String, String)> = store
                        .all_podcasts()
                        .into_iter()
                        .filter(|(podcast, _)| podcast.owner_pubkey_hex.is_some())
                        .map(|(podcast, _)| {
                            (podcast.title.to_lowercase(), podcast.id.0.to_string())
                        })
                        .collect();
                    rows.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)));
                    OwnedPodcastsResponse {
                        podcast_ids: rows.into_iter().map(|(_, id)| id).collect(),
                    }
                }
                Err(_) => OwnedPodcastsResponse {
                    podcast_ids: Vec::new(),
                },
            };
            encode(&response)
        },
    )
}

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_categories(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_library_categories",
        std::ptr::null_mut,
        || {
            let request_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            let request: CategoriesRequest = match serde_json::from_str(request_str) {
                Ok(r) => r,
                Err(_) => return std::ptr::null_mut(),
            };
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => {
                    let library = store.all_podcasts();
                    let mut rows: Vec<(String, String, CategoryRow)> = request
                        .categories
                        .into_iter()
                        .map(|category| {
                            let requested: Vec<String> = category
                                .podcast_ids
                                .into_iter()
                                .map(|id| id.to_lowercase())
                                .collect();
                            let mut podcast_rows: Vec<(String, String, bool)> = requested
                                .into_iter()
                                .filter_map(|id| {
                                    library
                                        .iter()
                                        .find(|(podcast, _)| {
                                            podcast.id.0.to_string() == id
                                                && store.is_subscribed(podcast.id)
                                                && podcast.feed_url.is_some()
                                        })
                                        .map(|(podcast, _)| {
                                            (
                                                podcast.title.to_lowercase(),
                                                id,
                                                store.is_transcription_enabled(&podcast.id),
                                            )
                                        })
                                })
                                .collect();
                            podcast_rows.sort_by(|a, b| {
                                a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1))
                            });
                            let all_transcription_enabled = if podcast_rows.is_empty() {
                                None
                            } else {
                                Some(podcast_rows.iter().all(|(_, _, enabled)| *enabled))
                            };
                            let row = CategoryRow {
                                category_id: category.category_id.clone(),
                                all_transcription_enabled,
                                podcast_ids: podcast_rows
                                    .into_iter()
                                    .map(|(_, id, _)| id)
                                    .collect(),
                            };
                            (category.name.to_lowercase(), category.category_id, row)
                        })
                        .collect();
                    rows.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)));
                    CategoriesResponse {
                        categories: rows.into_iter().map(|(_, _, row)| row).collect(),
                    }
                }
                Err(_) => CategoriesResponse {
                    categories: Vec::new(),
                },
            };
            encode(&response)
        },
    )
}

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_download_rows(
    handle: *mut PodcastHandle,
) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_library_download_rows",
        std::ptr::null_mut,
        || {
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => {
                    let mut active = Vec::new();
                    let mut failed = Vec::new();
                    let mut downloaded = Vec::new();
                    for (_, episodes) in store.all_podcasts() {
                        for episode in episodes {
                            let row = (episode.pub_date.timestamp(), episode.id.0.to_string());
                            match episode.download_state {
                                DownloadState::Queued => active.push((0, row.0, row.1)),
                                DownloadState::Downloading { .. } => active.push((1, row.0, row.1)),
                                DownloadState::Failed { .. } => failed.push(row),
                                DownloadState::Downloaded { .. } => downloaded.push(row),
                                DownloadState::NotDownloaded => {}
                            }
                        }
                    }
                    active.sort_by(|a, b| {
                        a.0.cmp(&b.0)
                            .then_with(|| b.1.cmp(&a.1))
                            .then_with(|| a.2.cmp(&b.2))
                    });
                    failed.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
                    downloaded.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
                    DownloadRowsResponse {
                        active_episode_ids: active.into_iter().map(|(_, _, id)| id).collect(),
                        failed_episode_ids: failed.into_iter().map(|(_, id)| id).collect(),
                        downloaded_episode_ids: downloaded.into_iter().map(|(_, id)| id).collect(),
                    }
                }
                Err(_) => DownloadRowsResponse {
                    active_episode_ids: Vec::new(),
                    failed_episode_ids: Vec::new(),
                    downloaded_episode_ids: Vec::new(),
                },
            };
            encode(&response)
        },
    )
}

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_subscription_status(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_library_subscription_status",
        std::ptr::null_mut,
        || {
            let request_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            let request: SubscriptionStatusRequest = match serde_json::from_str(request_str) {
                Ok(r) => r,
                Err(_) => return std::ptr::null_mut(),
            };
            let podcast_id = request.podcast_id.as_deref();
            let feed_url = request.feed_url.as_deref();
            let owner_pubkey = request.owner_pubkey.as_deref();
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => {
                    let matched = store.all_podcasts().into_iter().find(|(podcast, _)| {
                        // Case-insensitive: Swift sends UUID.uuidString (uppercase);
                        // Rust's Uuid::to_string() is always lowercase. A plain `==`
                        // never matches, making every subscribed podcast appear as
                        // "Follow" in the UI. Use eq_ignore_ascii_case — same pattern
                        // as episode_playback_info and other store lookups.
                        let id_match = podcast_id
                            .map(|expected| {
                                podcast.id.0.to_string().eq_ignore_ascii_case(expected)
                            })
                            .unwrap_or(false)
                            && store.is_subscribed(podcast.id);
                        let feed_match = feed_url
                            .zip(podcast.feed_url.as_ref())
                            .map(|(expected, actual)| actual.as_str() == expected)
                            .unwrap_or(false)
                            && store.is_subscribed(podcast.id);
                        let owner_match = owner_pubkey
                            .zip(podcast.owner_pubkey_hex.as_deref())
                            .map(|(expected, actual)| actual == expected)
                            .unwrap_or(false);
                        id_match || feed_match || owner_match
                    });
                    if let Some((podcast, episodes)) = matched {
                        SubscriptionStatusResponse {
                            is_already_subscribed: true,
                            podcast_id: Some(podcast.id.0.to_string()),
                            title: Some(podcast.title.clone()),
                            author: Some(podcast.author.clone()),
                            feed_url: podcast.feed_url.as_ref().map(|url| url.to_string()),
                            episode_count: Some(episodes.len()),
                        }
                    } else {
                        SubscriptionStatusResponse {
                            is_already_subscribed: false,
                            podcast_id: None,
                            title: None,
                            author: None,
                            feed_url: None,
                            episode_count: None,
                        }
                    }
                }
                Err(_) => SubscriptionStatusResponse {
                    is_already_subscribed: false,
                    podcast_id: None,
                    title: None,
                    author: None,
                    feed_url: None,
                    episode_count: None,
                },
            };
            encode(&response)
        },
    )
}

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_summary(handle: *mut PodcastHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard("nmp_app_podcast_library_summary", std::ptr::null_mut, || {
        let handle_ref = unsafe { &*handle };
        let response = match handle_ref.state.library.store.lock() {
            Ok(store) => {
                let library = store.all_podcasts();
                let episode_count = library.iter().map(|(_, episodes)| episodes.len()).sum();
                let followed_podcast_count = library
                    .iter()
                    .filter(|(podcast, _)| store.is_subscribed(podcast.id))
                    .count();
                let has_unfollowed_podcasts = library.iter().any(|(podcast, _)| {
                    podcast.id != PodcastId::unknown() && !store.is_subscribed(podcast.id)
                });
                let total_unplayed = library
                    .iter()
                    .flat_map(|(_, episodes)| episodes.iter())
                    .filter(|episode| !episode.played && !is_archived(&store, episode))
                    .count();
                LibrarySummaryResponse {
                    episode_count,
                    followed_podcast_count,
                    has_unfollowed_podcasts,
                    total_unplayed,
                }
            }
            Err(_) => LibrarySummaryResponse {
                episode_count: 0,
                followed_podcast_count: 0,
                has_unfollowed_podcasts: false,
                total_unplayed: 0,
            },
        };
        encode(&response)
    })
}

#[no_mangle]
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub extern "C" fn nmp_app_podcast_library_podcast_stats(
    handle: *mut PodcastHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request_json.is_null() {
        return std::ptr::null_mut();
    }
    ffi_guard(
        "nmp_app_podcast_library_podcast_stats",
        std::ptr::null_mut,
        || {
            let request_str = match unsafe { CStr::from_ptr(request_json) }.to_str() {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            let request: PodcastStatsRequest = match serde_json::from_str(request_str) {
                Ok(r) => r,
                Err(_) => return std::ptr::null_mut(),
            };
            let requested_ids: Vec<String> = request
                .podcast_ids
                .into_iter()
                .map(|id| id.to_lowercase())
                .collect();
            let handle_ref = unsafe { &*handle };
            let response = match handle_ref.state.library.store.lock() {
                Ok(store) => {
                    let library = store.all_podcasts();
                    let rows = requested_ids
                        .into_iter()
                        .filter_map(|requested_id| {
                            library
                                .iter()
                                .find(|(podcast, _)| podcast.id.0.to_string() == requested_id)
                                .map(|(_, episodes)| PodcastStatsRow {
                                    latest_episode_id: episodes
                                        .iter()
                                        .filter(|episode| !is_archived(&store, episode))
                                        .max_by(|a, b| a.pub_date.cmp(&b.pub_date))
                                        .map(|episode| episode.id.0.to_string()),
                                    podcast_id: requested_id,
                                    episode_count: episodes.len(),
                                    unplayed_count: episodes
                                        .iter()
                                        .filter(|episode| !episode.played && !is_archived(&store, episode))
                                        .count(),
                                    has_downloaded_episode: episodes.iter().any(|episode| {
                                        matches!(episode.download_state, DownloadState::Downloaded { .. })
                                    }),
                                    has_transcribed_episode: episodes.iter().any(|episode| {
                                        matches!(episode.transcript_state, TranscriptState::Ready { .. })
                                    }),
                                })
                        })
                        .collect();
                    PodcastStatsResponse { podcasts: rows }
                }
                Err(_) => PodcastStatsResponse {
                    podcasts: Vec::new(),
                },
            };
            encode(&response)
        },
    )
}
