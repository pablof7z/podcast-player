use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use url::Url;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct PodcastId(pub Uuid);

impl PodcastId {
    pub fn new(id: Uuid) -> Self {
        Self(id)
    }

    pub fn generate() -> Self {
        Self(Uuid::new_v4())
    }

    /// Stable sentinel parent for episodes that arrived without a known podcast.
    /// Matches the Swift `Podcast.unknownID` UUID so persisted episode foreign
    /// keys keep resolving across the migration.
    pub fn unknown() -> Self {
        Self(Uuid::parse_str("00000000-EEEE-EEEE-EEEE-000000000000").unwrap())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NostrVisibility {
    Private,
    Public,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Podcast {
    pub id: PodcastId,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub feed_url: Option<Url>,
    pub title: String,
    pub author: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub image_url: Option<Url>,
    pub description: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    pub categories: Vec<String>,
    pub discovered_at: DateTime<Utc>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub owner_pubkey_hex: Option<String>,
    pub nostr_visibility: NostrVisibility,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nostr_coordinate: Option<String>,
    pub title_is_placeholder: bool,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_refreshed_at: Option<DateTime<Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub etag: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_modified: Option<String>,
}

impl Podcast {
    pub fn new(title: impl Into<String>) -> Self {
        Self {
            id: PodcastId::generate(),
            feed_url: None,
            title: title.into(),
            author: String::new(),
            image_url: None,
            description: String::new(),
            language: None,
            categories: Vec::new(),
            discovered_at: Utc::now(),
            owner_pubkey_hex: None,
            nostr_visibility: NostrVisibility::Public,
            nostr_coordinate: None,
            title_is_placeholder: false,
            last_refreshed_at: None,
            etag: None,
            last_modified: None,
        }
    }

    pub fn id(&self) -> PodcastId {
        self.id
    }

    pub fn unknown() -> Self {
        Self {
            id: PodcastId::unknown(),
            title: "Unknown".into(),
            ..Self::new("Unknown")
        }
    }
}

#[cfg(test)]
#[path = "podcast_tests.rs"]
mod tests;
