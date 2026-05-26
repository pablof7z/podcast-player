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
/// `kind` is checked against [`KIND_SHOW`]. The `pubkey` is the podcast's own
/// hex pubkey (NIP-F4 per-podcast key). `created_at` is the event header
/// timestamp (unix seconds). `content` is the event content string — used as a
/// fallback for `description` when no `["description", ...]` tag is present.
///
/// NIP-F4 shows have no `d` tag; the show is identified by pubkey alone.
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

    let description = first_tag_value(tags, "description")
        .map(str::to_string)
        .unwrap_or_else(|| content.to_string());

    Ok(NIP74Show {
        pubkey: pubkey.to_string(),
        title,
        description,
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
/// `Podcast::id` is a UUIDv5 derived from the NIP-F4 coordinate so the
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
        description: show.description.clone(),
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

/// UUIDv5 of the NIP-F4 coordinate string, using a project-scoped
/// namespace UUID so values can be replayed deterministically.
fn podcast_id_from_coordinate(coordinate: &str) -> PodcastId {
    const NS: Uuid = Uuid::from_bytes([
        0xd9, 0x7c, 0x4d, 0x7d, 0xa1, 0x12, 0x5b, 0x4f, 0x9a, 0x0b, 0x71, 0x12, 0xb6, 0x4c, 0xc3,
        0x2d,
    ]);
    PodcastId::new(Uuid::new_v5(&NS, coordinate.as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn minimal_tags() -> Vec<Vec<String>> {
        vec![vec!["title".into(), "My Show".into()]]
    }

    #[test]
    fn parse_minimal_show_succeeds() {
        let show = parse_show_event(KIND_SHOW, "podcast-pk", 1_700_000_000, "", &minimal_tags())
            .expect("parse");
        assert_eq!(show.title, "My Show");
        assert_eq!(show.pubkey, "podcast-pk");
        assert_eq!(show.description, ""); // no description tag, no content
        assert!(show.image_url.is_none());
        assert!(show.author_pubkey.is_none());
        assert!(show.categories.is_empty());
        assert_eq!(show.created_at, 1_700_000_000);
    }

    #[test]
    fn parse_full_show_collects_every_field() {
        let tags = vec![
            vec!["title".into(), "Full Show".into()],
            vec!["description".into(), "A great show".into()],
            vec!["image".into(), "https://img.example/cover.jpg".into()],
            vec!["language".into(), "en".into()],
            vec!["p".into(), "podcast-pk".into()],
            vec!["t".into(), "Technology".into()],
            vec!["t".into(), "News".into()],
        ];
        let show = parse_show_event(KIND_SHOW, "podcast-pk", 100, "", &tags).expect("parse");
        assert_eq!(show.description, "A great show");
        assert_eq!(show.image_url.as_deref(), Some("https://img.example/cover.jpg"));
        assert_eq!(show.language.as_deref(), Some("en"));
        assert_eq!(show.author_pubkey.as_deref(), Some("podcast-pk"));
        assert_eq!(show.categories, vec!["Technology".to_string(), "News".into()]);
    }

    #[test]
    fn parse_rejects_wrong_kind() {
        let err = parse_show_event(1, "pk", 0, "", &minimal_tags()).unwrap_err();
        assert!(matches!(
            err,
            ParseError::WrongKind {
                expected: KIND_SHOW,
                got: 1
            }
        ));
    }

    #[test]
    fn parse_falls_back_title_to_content_prefix() {
        let show =
            parse_show_event(KIND_SHOW, "pk", 0, "Content as title fallback", &[]).expect("parse");
        assert_eq!(show.title, "Content as title fallback");
    }

    #[test]
    fn parse_rejects_when_no_title_and_no_content() {
        let err = parse_show_event(KIND_SHOW, "pk", 0, "", &[]).unwrap_err();
        assert_eq!(err, ParseError::MissingTag("title"));
    }

    #[test]
    fn description_falls_back_to_content() {
        let tags = vec![vec!["title".into(), "My Show".into()]];
        let show =
            parse_show_event(KIND_SHOW, "pk", 0, "Content description", &tags).expect("parse");
        assert_eq!(show.description, "Content description");
    }

    #[test]
    fn show_to_podcast_maps_fields() {
        let show = NIP74Show {
            pubkey: "pk".into(),
            title: "T".into(),
            description: "S".into(),
            image_url: Some("https://img.example/c.png".into()),
            language: Some("en".into()),
            author_pubkey: Some("pk".into()),
            categories: vec!["Tech".into()],
            created_at: 100,
        };
        let p = show_to_podcast(&show);
        assert_eq!(p.title, "T");
        assert_eq!(p.description, "S");
        assert_eq!(p.language.as_deref(), Some("en"));
        assert_eq!(p.categories, vec!["Tech".to_string()]);
        assert_eq!(p.owner_pubkey_hex.as_deref(), Some("pk"));
        assert_eq!(p.nostr_coordinate.as_deref(), Some("10154:pk"));
        assert_eq!(p.image_url.as_ref().map(Url::as_str), Some("https://img.example/c.png"));
    }

    #[test]
    fn show_to_podcast_id_is_stable_per_pubkey() {
        let make = |pk: &str| NIP74Show {
            pubkey: pk.into(),
            title: "T".into(),
            description: String::new(),
            image_url: None,
            language: None,
            author_pubkey: None,
            categories: vec![],
            created_at: 0,
        };
        let a = show_to_podcast(&make("pk-1"));
        let b = show_to_podcast(&make("pk-1"));
        let c = show_to_podcast(&make("pk-2"));
        assert_eq!(a.id, b.id, "same pubkey → same id");
        assert_ne!(a.id, c.id, "different pubkey → different id");
    }
}
