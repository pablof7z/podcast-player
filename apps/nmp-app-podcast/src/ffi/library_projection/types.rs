//! DTO structs for Library screen projections.

use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub(super) struct ShowEpisodesRequest {
    pub(super) podcast_id: String,
    #[serde(default = "super::helpers::default_limit")]
    pub(super) limit: usize,
}

#[derive(Debug, Serialize)]
pub(super) struct ShowEpisodesResponse {
    pub(super) episode_ids: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub(super) struct PodcastStatsRequest {
    #[serde(default)]
    pub(super) podcast_ids: Vec<String>,
}

#[derive(Debug, Serialize)]
pub(super) struct PodcastStatsResponse {
    pub(super) podcasts: Vec<PodcastStatsRow>,
}

#[derive(Debug, Serialize)]
pub(super) struct PodcastStatsRow {
    pub(super) podcast_id: String,
    pub(super) episode_count: usize,
    pub(super) unplayed_count: usize,
    pub(super) has_downloaded_episode: bool,
    pub(super) has_transcribed_episode: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) latest_episode_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub(super) struct LibrarySummaryResponse {
    pub(super) episode_count: usize,
    pub(super) followed_podcast_count: usize,
    pub(super) has_unfollowed_podcasts: bool,
    pub(super) total_unplayed: usize,
}

#[derive(Debug, Deserialize)]
pub(super) struct EpisodeForAudioUrlRequest {
    pub(super) podcast_id: String,
    pub(super) audio_url: String,
}

#[derive(Debug, Serialize)]
pub(super) struct EpisodeForAudioUrlResponse {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) episode_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(super) struct AllEpisodesRequest {
    pub(super) filter: String,
    #[serde(default)]
    pub(super) query: String,
    #[serde(default = "super::helpers::default_all_episodes_limit")]
    pub(super) limit: usize,
}

#[derive(Debug, Serialize)]
pub(super) struct AllEpisodesResponse {
    pub(super) episode_ids: Vec<String>,
    pub(super) total_count: usize,
}

#[derive(Debug, Deserialize)]
pub(super) struct AllPodcastsRequest {
    #[serde(default)]
    pub(super) query: String,
}

#[derive(Debug, Serialize)]
pub(super) struct AllPodcastsResponse {
    pub(super) podcast_ids: Vec<String>,
}

#[derive(Debug, Serialize)]
pub(super) struct FollowedPodcastsResponse {
    pub(super) podcast_ids: Vec<String>,
}

#[derive(Debug, Serialize)]
pub(super) struct OwnedPodcastsResponse {
    pub(super) podcast_ids: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub(super) struct CategoriesRequest {
    #[serde(default)]
    pub(super) categories: Vec<CategoryScope>,
}

#[derive(Debug, Deserialize)]
pub(super) struct CategoryScope {
    pub(super) category_id: String,
    #[serde(default)]
    pub(super) name: String,
    #[serde(default)]
    pub(super) podcast_ids: Vec<String>,
}

#[derive(Debug, Serialize)]
pub(super) struct CategoriesResponse {
    pub(super) categories: Vec<CategoryRow>,
}

#[derive(Debug, Serialize)]
pub(super) struct CategoryRow {
    pub(super) category_id: String,
    pub(super) podcast_ids: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) all_transcription_enabled: Option<bool>,
}

#[derive(Debug, Serialize)]
pub(super) struct DownloadRowsResponse {
    pub(super) active_episode_ids: Vec<String>,
    pub(super) failed_episode_ids: Vec<String>,
    pub(super) downloaded_episode_ids: Vec<String>,
}

#[derive(Debug, Serialize)]
pub(super) struct StarredEpisodesResponse {
    pub(super) episode_ids: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub(super) struct EpisodeLookupRequest {
    pub(super) reference: String,
}

#[derive(Debug, Serialize)]
pub(super) struct EpisodeLookupResponse {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) episode_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(super) struct SubscriptionStatusRequest {
    #[serde(default)]
    pub(super) podcast_id: Option<String>,
    #[serde(default)]
    pub(super) feed_url: Option<String>,
    #[serde(default)]
    pub(super) owner_pubkey: Option<String>,
}

#[derive(Debug, Serialize)]
pub(super) struct SubscriptionStatusResponse {
    pub(super) is_already_subscribed: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) podcast_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) author: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) feed_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) episode_count: Option<usize>,
}
