//! NIP-74 podcast discovery (kind:30074 shows, kind:30075 episodes) —
//! port of `App/Sources/Services/NostrPodcastDiscoveryService.swift`.
//!
//! Event-driven: each subscription installs a [`Router`] that converts
//! incoming events into [`Delta`]s carrying [`PodcastShowRecord`] or
//! [`PodcastEpisodeRecord`]. No polling, no short-lived WebSocket — the
//! shared notification pump in [`crate::nostr_runtime`] streams events for
//! as long as the subscription lives.
//!
//! Wire format parity with Swift (`NostrPodcastDiscoveryService`):
//!   - show: `d`, `title`, `author`, `summary` (description), `image`, `t` (categories)
//!   - episode: `d`, `title`, `summary`, `imeta [url=, m=, x=, size=, duration=]`,
//!              optional `chapters` and `transcript` (with mime as 3rd field).

use std::str::FromStr;
use std::sync::Arc;

use nostr_sdk::prelude::*;
use sha2::{Digest, Sha256};

use crate::client::PodcastrCore;
use crate::errors::CoreError;
use crate::events::{DataChangeType, Delta};
use crate::models::{PodcastEpisodeRecord, PodcastShowRecord};
use crate::subscriptions::{CallbackSubscriptionId, Router};

const KIND_SHOW: u16 = 30074;
const KIND_EPISODE: u16 = 30075;

// ---------------------------------------------------------------------------
// Show router (kind:30074)
// ---------------------------------------------------------------------------

pub struct ShowRouter {
    callback_id: CallbackSubscriptionId,
}

impl ShowRouter {
    pub fn new(callback_id: CallbackSubscriptionId) -> Self {
        Self { callback_id }
    }
}

impl Router for ShowRouter {
    fn callback_id(&self) -> CallbackSubscriptionId {
        self.callback_id
    }

    fn on_event(&self, event: &Event, _relay_url: &RelayUrl) -> Vec<Delta> {
        if event.kind != Kind::Custom(KIND_SHOW) {
            return Vec::new();
        }
        match parse_show(event) {
            Some(show) => vec![Delta {
                subscription_id: self.callback_id,
                change: DataChangeType::PodcastShowDiscovered { show },
            }],
            None => Vec::new(),
        }
    }
}

// ---------------------------------------------------------------------------
// Episode router (kind:30075)
// ---------------------------------------------------------------------------

pub struct EpisodeRouter {
    callback_id: CallbackSubscriptionId,
    /// Coordinate of the parent show — used to anchor each parsed episode so
    /// Swift can route deltas to the right podcast row.
    show_coordinate: String,
}

impl EpisodeRouter {
    pub fn new(callback_id: CallbackSubscriptionId, show_coordinate: String) -> Self {
        Self {
            callback_id,
            show_coordinate,
        }
    }
}

impl Router for EpisodeRouter {
    fn callback_id(&self) -> CallbackSubscriptionId {
        self.callback_id
    }

    fn on_event(&self, event: &Event, _relay_url: &RelayUrl) -> Vec<Delta> {
        if event.kind != Kind::Custom(KIND_EPISODE) {
            return Vec::new();
        }
        match parse_episode(event, &self.show_coordinate) {
            Some(episode) => vec![Delta {
                subscription_id: self.callback_id,
                change: DataChangeType::PodcastEpisodeDiscovered { episode },
            }],
            None => Vec::new(),
        }
    }
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// First value (index 1) of the first tag whose key matches `name`.
fn first_tag_value<'a>(event: &'a Event, name: &str) -> Option<&'a str> {
    for tag in event.tags.iter() {
        let slice = tag.as_slice();
        if slice.first().map(String::as_str) == Some(name) {
            return slice.get(1).map(String::as_str);
        }
    }
    None
}

/// All `[1]` values of tags whose key matches `name`.
fn all_tag_values<'a>(event: &'a Event, name: &str) -> Vec<String> {
    event
        .tags
        .iter()
        .filter_map(|tag| {
            let slice = tag.as_slice();
            if slice.first().map(String::as_str) == Some(name) {
                slice.get(1).cloned()
            } else {
                None
            }
        })
        .collect()
}

/// First `imeta` tag, returned as the raw slice including the `imeta` key.
fn imeta_tag<'a>(event: &'a Event) -> Option<&'a [String]> {
    for tag in event.tags.iter() {
        let slice = tag.as_slice();
        if slice.first().map(String::as_str) == Some("imeta") {
            return Some(slice);
        }
    }
    None
}

/// Look up a space-separated subfield inside an `imeta` tag.
///
/// `imeta` tags are arrays of `"key value"` strings, e.g. `["imeta", "url https://…", "m audio/mp4", …]`.
fn imeta_field(imeta: &[String], prefix: &str) -> Option<String> {
    let needle = format!("{prefix} ");
    imeta
        .iter()
        .skip(1)
        .find(|part| part.starts_with(&needle))
        .map(|part| part[needle.len()..].to_string())
}

fn parse_show(event: &Event) -> Option<PodcastShowRecord> {
    let d_tag = first_tag_value(event, "d")?.to_string();
    if d_tag.is_empty() {
        return None;
    }

    let title = first_tag_value(event, "title")
        .map(str::to_string)
        .unwrap_or_else(|| event.content.chars().take(80).collect());
    if title.is_empty() {
        return None;
    }

    let author = first_tag_value(event, "author")
        .map(str::to_string)
        .unwrap_or_default();
    let description = first_tag_value(event, "summary")
        .map(str::to_string)
        .unwrap_or_else(|| event.content.clone());
    let image_url = first_tag_value(event, "image").map(str::to_string);
    let categories = all_tag_values(event, "t");

    let pubkey = event.pubkey.to_hex();
    let coordinate = format!("{}:{}:{}", KIND_SHOW, pubkey, d_tag);

    Some(PodcastShowRecord {
        coordinate,
        pubkey,
        d_tag,
        title,
        author,
        description,
        image_url,
        categories,
        created_at: event.created_at.as_u64() as i64,
    })
}

fn parse_episode(event: &Event, show_coordinate: &str) -> Option<PodcastEpisodeRecord> {
    let d_tag = first_tag_value(event, "d")?.to_string();
    if d_tag.is_empty() {
        return None;
    }

    // Audio URL: prefer `imeta url=…`, fall back to top-level `url` tag.
    let imeta = imeta_tag(event);
    let audio_url = imeta
        .and_then(|t| imeta_field(t, "url"))
        .or_else(|| first_tag_value(event, "url").map(str::to_string))?;

    let title = first_tag_value(event, "title")
        .map(str::to_string)
        .unwrap_or_default();
    let description = first_tag_value(event, "summary")
        .map(str::to_string)
        .unwrap_or_else(|| event.content.clone());

    let mime_type = imeta.and_then(|t| imeta_field(t, "m"));
    let sha256 = imeta.and_then(|t| imeta_field(t, "x"));
    let size = imeta
        .and_then(|t| imeta_field(t, "size"))
        .and_then(|s| s.parse::<u64>().ok());
    let duration = imeta
        .and_then(|t| imeta_field(t, "duration"))
        .or_else(|| first_tag_value(event, "duration").map(str::to_string))
        .and_then(|s| s.parse::<u64>().ok());

    let chapters_url = first_tag_value(event, "chapters").map(str::to_string);
    let transcript_url = first_tag_value(event, "transcript").map(str::to_string);

    Some(PodcastEpisodeRecord {
        event_id: event.id.to_hex(),
        pubkey: event.pubkey.to_hex(),
        d_tag,
        show_coordinate: show_coordinate.to_string(),
        title,
        description,
        audio_url,
        mime_type,
        sha256,
        size,
        duration,
        chapters_url,
        transcript_url,
        created_at: event.created_at.as_u64() as i64,
    })
}

// ---------------------------------------------------------------------------
// Public API on PodcastrCore
// ---------------------------------------------------------------------------

#[uniffi::export(async_runtime = "tokio")]
impl PodcastrCore {
    /// Subscribe to all kind:30074 podcast show events on the configured relay
    /// pool. Each show event arrives as a [`DataChangeType::PodcastShowDiscovered`]
    /// delta on `callback_subscription_id`.
    pub async fn subscribe_podcast_shows(
        &self,
        callback_subscription_id: u64,
    ) -> Result<String, CoreError> {
        let sub_id = SubscriptionId::generate();
        let filter = Filter::new().kind(Kind::Custom(KIND_SHOW));
        let router = Arc::new(ShowRouter::new(callback_subscription_id));
        self.runtime()
            .subscribe(sub_id.clone(), filter, router)
            .await?;
        Ok(sub_id.as_str().to_string())
    }

    /// Subscribe to kind:30075 episode events anchored at `show_coordinate`
    /// (format `<kind>:<pubkey>:<dTag>`). Each event arrives as a
    /// [`DataChangeType::PodcastEpisodeDiscovered`] delta on
    /// `callback_subscription_id`.
    pub async fn subscribe_podcast_episodes(
        &self,
        show_coordinate: String,
        callback_subscription_id: u64,
    ) -> Result<String, CoreError> {
        let coord = Coordinate::from_str(&show_coordinate)
            .map_err(|e| CoreError::InvalidInput(format!("bad coordinate: {e}")))?;

        let sub_id = SubscriptionId::generate();
        let filter = Filter::new()
            .kind(Kind::Custom(KIND_EPISODE))
            .author(coord.public_key)
            .custom_tag(SingleLetterTag::lowercase(Alphabet::A), &show_coordinate);

        let router = Arc::new(EpisodeRouter::new(
            callback_subscription_id,
            show_coordinate,
        ));
        self.runtime()
            .subscribe(sub_id.clone(), filter, router)
            .await?;
        Ok(sub_id.as_str().to_string())
    }

    /// Tear down a podcast subscription installed via
    /// [`Self::subscribe_podcast_shows`] or [`Self::subscribe_podcast_episodes`].
    pub async fn unsubscribe_podcast(&self, sub_id: String) {
        let id = SubscriptionId::new(sub_id);
        self.runtime().unsubscribe(id).await;
    }
}

// ---------------------------------------------------------------------------
// Deterministic UUID helper (mirrors `NostrPodcastDiscoveryService.podcastID(for:)`)
// ---------------------------------------------------------------------------

/// Derive a stable UUID v5-shaped string from a NIP-74 coordinate.
///
/// Algorithm — matches Swift `NostrPodcastDiscoveryService.podcastID(for:)`:
/// 1. SHA-256 the UTF-8 bytes of the coordinate.
/// 2. Take the first 16 bytes.
/// 3. Force version 5 (`bytes[6] = (bytes[6] & 0x0F) | 0x50`).
/// 4. Force variant 1 (`bytes[8] = (bytes[8] & 0x3F) | 0x80`).
/// 5. Emit canonical 8-4-4-4-12 lowercase hex.
#[uniffi::export]
pub fn podcast_id_for_coordinate(coordinate: String) -> String {
    let digest = Sha256::digest(coordinate.as_bytes());
    let mut bytes = [0u8; 16];
    bytes.copy_from_slice(&digest[..16]);
    bytes[6] = (bytes[6] & 0x0F) | 0x50;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    let mut hex_buf = [0u8; 32];
    hex::encode_to_slice(bytes, &mut hex_buf).expect("32 bytes fits 16-byte input");
    // SAFETY: `hex::encode_to_slice` only emits ASCII hex digits.
    let hex_str = std::str::from_utf8(&hex_buf).expect("hex output is ASCII");

    format!(
        "{}-{}-{}-{}-{}",
        &hex_str[0..8],
        &hex_str[8..12],
        &hex_str[12..16],
        &hex_str[16..20],
        &hex_str[20..32],
    )
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deterministic_uuid_is_stable() {
        let a = podcast_id_for_coordinate(
            "30074:0000000000000000000000000000000000000000000000000000000000000001:show1"
                .to_string(),
        );
        let b = podcast_id_for_coordinate(
            "30074:0000000000000000000000000000000000000000000000000000000000000001:show1"
                .to_string(),
        );
        assert_eq!(a, b);
        // Canonical UUID shape (lowercase, dashed 8-4-4-4-12).
        assert_eq!(a.len(), 36);
        assert_eq!(&a[14..15], "5"); // version nibble
        let variant = u8::from_str_radix(&a[19..20], 16).unwrap();
        assert!((variant & 0b1100) == 0b1000); // variant 1 (top two bits 10)
    }

    #[test]
    fn deterministic_uuid_changes_with_input() {
        let a = podcast_id_for_coordinate("30074:abc:show1".to_string());
        let b = podcast_id_for_coordinate("30074:abc:show2".to_string());
        assert_ne!(a, b);
    }

    #[test]
    fn deterministic_uuid_matches_swift_algorithm() {
        // Reference value computed from the same SHA-256 + UUIDv5-shape
        // algorithm that `NostrPodcastDiscoveryService.podcastID(for:)` runs.
        // Swift returns UPPERCASE via `UUID.uuidString`; we emit lowercase
        // because `Foundation.UUID(uuidString:)` accepts either case and the
        // canonical lowercase form is the conventional FFI wire shape.
        let got = podcast_id_for_coordinate("30074:abc:show1".to_string());
        assert_eq!(got, "85939419-c7a6-5117-9b4e-73c50b941c00");
    }
}
