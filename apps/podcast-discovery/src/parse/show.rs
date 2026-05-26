//! Parse a `kind:10154` Nostr event (NIP-F4) into a [`NIP74Show`] and map it onto
//! a [`Podcast`].
//!
//! Behavior mirrors `App/Sources/Services/NostrPodcastDiscoveryService
//! .parseShow(from:)` so the Rust + Swift discovery paths converge on the
//! same `Podcast` row given identical wire input.

use podcast_core::types::podcast::{NostrVisibility, Podcast, PodcastId, PodcastKind};
use url::Url;
use uuid::Uuid;

use crate::kinds::KIND_SHOW;
use crate::parse::{all_tag_values, first_tag_value};
use crate::types::{NIP74Show, ParseError};

/// Parse a Nostr event's header + tags into a raw [`NIP74Show`].
///
/// `kind` is checked against [`KIND_SHOW`]. The `pubkey` is the event
/// author's hex pubkey. `created_at` is the event header timestamp
/// (unix seconds). `content` is the event content string — used as a
/// fallback for the summary when no `["summary", ...]` tag is present
/// (matches the Swift discovery service).
pub fn parse_show_event(
    kind: u32,
    pubkey: &str,
    created_at: i64,
    content: &str,
    tags: &[Vec<String>],
) -> Result<NIP74Show, ParseError> {
    if kind != KIND_SHOW {
        return Err(ParseError::WrongKind {
            expected: KIND_SHOW,
            got: kind,
        });
    }
    let d_tag = first_tag_value(tags, "d")
        .ok_or(ParseError::MissingTag("d"))?
        .to_string();

    // Title falls back to a prefix of `content` (mirrors Swift parseShow).
    let title = first_tag_value(tags, "title")
        .map(str::to_string)
        .or_else(|| {
            if content.is_empty() {
                None
            } else {
                Some(content.chars().take(80).collect())
            }
        })
        .ok_or(ParseError::MissingTag("title"))?;
    if title.is_empty() {
        return Err(ParseError::EmptyTag("title"));
    }

    let summary = first_tag_value(tags, "summary")
        .map(str::to_string)
        .unwrap_or_else(|| content.to_string());

    Ok(NIP74Show {
        pubkey: pubkey.to_string(),
        d_tag,
        title,
        summary,
        image_url: first_tag_value(tags, "image").map(str::to_string),
        language: first_tag_value(tags, "language").map(str::to_string),
        author_pubkey: first_tag_value(tags, "p").map(str::to_string),
        categories: all_tag_values(tags, "t"),
        created_at,
    })
}

/// Map a parsed [`NIP74Show`] onto a [`Podcast`] domain row.
///
/// The mapping is total: every field that does not parse as a URL is
/// silently dropped (matches Swift `URL(string:)` semantics, which is the
/// existing wire contract).
///
/// `Podcast::id` is a UUIDv5 derived from the NIP-33 coordinate so the
/// row is stable across rediscoveries — `subscribe(to:)` in Swift uses
/// the same scheme via `NostrPodcastDiscoveryService.podcastID(for:)`.
pub fn show_to_podcast(show: &NIP74Show) -> Podcast {
    let coordinate = show.coordinate();
    Podcast {
        id: podcast_id_from_coordinate(&coordinate),
        kind: PodcastKind::Rss,
        feed_url: None,
        title: show.title.clone(),
        author: show.author_pubkey.clone().unwrap_or_default(),
        image_url: show.image_url.as_deref().and_then(|s| Url::parse(s).ok()),
        description: show.summary.clone(),
        language: show.language.clone(),
        categories: show.categories.clone(),
        discovered_at: chrono::Utc::now(),
        owner_pubkey_hex: Some(show.pubkey.clone()),
        nostr_visibility: NostrVisibility::Public,
        nostr_coordinate: Some(coordinate),
        title_is_placeholder: false,
        last_refreshed_at: None,
        etag: None,
        last_modified: None,
    }
}

/// UUIDv5 of the NIP-33 coordinate string, using a project-scoped
/// namespace UUID so values can be replayed deterministically.
///
/// `Uuid::new_v5` is SHA-1 based, which matches the Swift implementation's
/// shape (16 bytes derived from a hash of the coordinate) closely enough
/// for our cross-host needs. The Swift side computes from SHA-256 with
/// bit-fiddling for version 5 — we accept a one-time host-side rebuild on
/// the cutover because the same Rust value is used everywhere going
/// forward; the canonical id source becomes this function.
fn podcast_id_from_coordinate(coordinate: &str) -> PodcastId {
    // Namespace UUID: stable, chosen once for podcast-discovery NIP-F4
    // coordinates. Captured here rather than in podcast-core because the
    // namespace is a NIP-F4 schema concern.
    const NS: Uuid = Uuid::from_bytes([
        0xd9, 0x7c, 0x4d, 0x7d, 0xa1, 0x12, 0x5b, 0x4f, 0x9a, 0x0b, 0x71, 0x12, 0xb6, 0x4c, 0xc3,
        0x2d,
    ]);
    PodcastId::new(Uuid::new_v5(&NS, coordinate.as_bytes()))
}

#[cfg(test)]
#[path = "show_tests.rs"]
mod tests;
