//! NIP-F4 podcast discovery — `kind:10154` show events.
//!
//! NIP-F4 redesigns NIP-74 around per-podcast keypairs:
//!
//! * `kind:10154` — show metadata, replaceable, signed by the podcast key.
//! * `kind:54` — episodes (regular events) signed by the podcast key.
//! * `kind:10064` — author claim (the agent claims a set of podcast pubkeys).
//!
//! Scope of this module: parsing `kind:10154` events for the AddShowSheet
//! discovery flow only. Episode (kind:54) and author-claim (kind:10064)
//! parsing belongs to the wider NIP-F4 migration tracked separately under
//! `docs/plan/pod0-nostr-publishing.md`.
//!
//! ## Tag layout (kind:10154)
//!
//! As specified by the PR-19 implementation brief:
//!
//! ```text
//! ["title", "My Show"]
//! ["summary", "..."]            // human-readable description
//! ["image", "https://..."]      // artwork url
//! ["feed", "https://..."]       // RSS/Atom feed url — load-bearing
//! ["category", "Technology"]    // repeated
//! ```
//!
//! The `feed` tag is the load-bearing field for discovery: the UI surfaces
//! a "Subscribe" button on each result, and "subscribe" reuses the
//! existing RSS pipeline (`podcast.subscribe { feed_url }`). A result
//! without a `feed` tag still parses (so we can show it greyed out in the
//! list) — the UI is responsible for disabling the subscribe button.
//!
//! ## Doctrine
//!
//! * **Pure** — no I/O, no async, no `nostr` crate dep. Mirrors the NIP-74
//!   parse layer doctrine in `crate::parse::show`.
//! * **Tolerant decoder** — unknown / extra tags are ignored; missing
//!   optional fields decode as `None`. The only hard requirement is a
//!   non-empty `title` (a result with no title is meaningless to the user).
//! * **No domain mapping yet** — `kind:10154` discoveries flow into the
//!   library by calling `podcast.subscribe { feed_url }`, not by
//!   constructing a `Podcast` row directly. The wider NIP-F4 cutover will
//!   add `nip_f4_show_to_podcast` when pure-Nostr (no RSS) podcasts land.

use serde::{Deserialize, Serialize};

use crate::types::ParseError;

/// NIP-F4 show event kind. Pinned in one place so callers don't drift.
pub const KIND_NIP_F4_SHOW: u32 = 10154;

/// NIP-F4 episode event kind. Exported as a constant for downstream
/// callers; the parser for kind:54 itself lands with the wider NIP-F4
/// migration.
pub const KIND_NIP_F4_EPISODE: u32 = 54;

/// NIP-F4 author-claim event kind. Exported for downstream callers; the
/// parser/builder lands with the wider NIP-F4 migration.
pub const KIND_NIP_F4_AUTHOR_CLAIM: u32 = 10064;

/// Parsed `kind:10154` NIP-F4 show event.
///
/// `event_id` is the hex event id from the Nostr envelope. `author_pubkey`
/// is the podcast's own pubkey (NIP-F4 uses per-podcast keys). Both come
/// from the wrapping event header, not from tags.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct NipF4Show {
    /// Event id (hex) from the wrapping Nostr envelope.
    pub event_id: String,
    /// Pubkey (hex) that signed the event. In NIP-F4 this is the
    /// podcast's own per-podcast key.
    pub author_pubkey: String,
    /// `["title", ...]`.
    pub title: String,
    /// `["summary", ...]` (or `None` when absent). Per task brief tag is
    /// `summary`, not `description` — see file-level doc.
    pub description: Option<String>,
    /// `["feed", "<rss-url>"]`. The load-bearing field for subscribing.
    pub feed_url: Option<String>,
    /// `["image", "<url>"]` — show artwork.
    pub artwork_url: Option<String>,
    /// Every `["category", "<name>"]` tag, in event order.
    pub categories: Vec<String>,
}

/// Parse a `kind:10154` Nostr event into a [`NipF4Show`].
///
/// Hard requirements:
/// * `kind` must equal [`KIND_NIP_F4_SHOW`] (returns `WrongKind` otherwise).
/// * Either a `["title", ...]` tag with a non-empty value, or non-empty
///   `content` to fall back to (mirrors `parse_show_event` for NIP-74).
///
/// Everything else is best-effort. Tolerant of foreign tags.
pub fn parse_kind_10154(
    kind: u32,
    event_id: &str,
    pubkey: &str,
    content: &str,
    tags: &[Vec<String>],
) -> Result<NipF4Show, ParseError> {
    if kind != KIND_NIP_F4_SHOW {
        return Err(ParseError::WrongKind {
            expected: KIND_NIP_F4_SHOW,
            got: kind,
        });
    }

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

    let description = first_tag_value(tags, "summary")
        .map(str::to_string)
        .or_else(|| {
            if content.is_empty() {
                None
            } else {
                Some(content.to_string())
            }
        });

    Ok(NipF4Show {
        event_id: event_id.to_string(),
        author_pubkey: pubkey.to_string(),
        title,
        description,
        feed_url: first_tag_value(tags, "feed").map(str::to_string),
        artwork_url: first_tag_value(tags, "image").map(str::to_string),
        categories: all_tag_values(tags, "category"),
    })
}

/// Parsed `kind:54` NIP-F4 episode event.
///
/// `event_id` and `author_pubkey` come from the wrapping event header. The
/// `author_pubkey` is the podcast's own per-podcast key — the same key that
/// signed the parent `kind:10154` show event, so it serves as the stable
/// show ↔ episode link.
///
/// Tag layout (mirror of `build/episode.rs::episode_to_episode_tags`):
///
/// ```text
/// ["title", "My Episode"]
/// ["description", "..."]            // optional — falls back to content
/// ["duration", "<seconds>"]         // optional integer seconds
/// ["image", "https://..."]          // optional per-episode artwork
/// ["audio", "<url>", "<mime>"]      // required — the enclosure URL
/// ["chapters", "<url>", "<mime>"]   // optional Podcasting 2.0 chapters
/// ["transcript", "<url>", "<mime>"] // optional transcript
/// ```
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct NipF4Episode {
    /// Event id (hex) from the wrapping Nostr envelope.
    pub event_id: String,
    /// Pubkey (hex) that signed the event — the podcast's per-podcast key.
    pub author_pubkey: String,
    /// `["title", ...]`.
    pub title: String,
    /// `["description", ...]` — falls back to `Event.content`.
    pub description: Option<String>,
    /// `["duration", <seconds>]` — integer seconds.
    pub duration_secs: Option<f64>,
    /// `["image", <url>]` — per-episode artwork.
    pub image_url: Option<String>,
    /// `["audio", "<url>", ...]` — the enclosure URL (required).
    pub audio_url: String,
    /// MIME type from the second component of the `audio` tag.
    pub audio_mime_type: Option<String>,
    /// `["chapters", <url>, <mime>]`.
    pub chapters_url: Option<String>,
    /// `["transcript", <url>, <mime>]`.
    pub transcript_url: Option<String>,
    /// MIME type from the second component of the `transcript` tag.
    pub transcript_mime_type: Option<String>,
    /// Event header `created_at` (unix seconds). Used as `published_at`.
    pub created_at: i64,
}

/// Parse a `kind:54` NIP-F4 episode event into a [`NipF4Episode`].
///
/// This is the exact inverse of `build/episode.rs::episode_to_episode_tags`:
/// `["audio", "<url>", "<mime>"]` is the required enclosure tag.
///
/// Hard requirements:
/// * `kind` must equal [`KIND_NIP_F4_EPISODE`].
/// * A `["audio", "<url>", ...]` tag with a non-empty URL.
///
/// Everything else is best-effort (D6 — tolerant decoder).
pub fn parse_kind_54(
    kind: u32,
    event_id: &str,
    pubkey: &str,
    created_at: i64,
    content: &str,
    tags: &[Vec<String>],
) -> Result<NipF4Episode, ParseError> {
    if kind != KIND_NIP_F4_EPISODE {
        return Err(ParseError::WrongKind {
            expected: KIND_NIP_F4_EPISODE,
            got: kind,
        });
    }

    // `audio` tag is the required enclosure — mirrors `build_audio_tag`.
    let audio_tag = tags
        .iter()
        .find(|t| t.first().map(String::as_str) == Some("audio"))
        .ok_or(ParseError::MissingTag("audio"))?;
    let audio_url = audio_tag
        .get(1)
        .filter(|s| !s.is_empty())
        .ok_or(ParseError::MissingAudioUrl)?
        .clone();
    let audio_mime_type = audio_tag.get(2).filter(|s| !s.is_empty()).cloned();

    let title = first_tag_value(tags, "title")
        .map(str::to_string)
        .unwrap_or_default();

    let description = first_tag_value(tags, "description")
        .map(str::to_string)
        .or_else(|| if content.is_empty() { None } else { Some(content.to_string()) });

    let duration_secs = first_tag_value(tags, "duration")
        .and_then(|v| v.parse::<f64>().ok());

    let image_url = first_tag_value(tags, "image").map(str::to_string);

    let chapters_tag = tags
        .iter()
        .find(|t| t.first().map(String::as_str) == Some("chapters"));
    let chapters_url = chapters_tag
        .and_then(|t| t.get(1))
        .filter(|s| !s.is_empty())
        .cloned();

    let transcript_tag = tags
        .iter()
        .find(|t| t.first().map(String::as_str) == Some("transcript"));
    let transcript_url = transcript_tag
        .and_then(|t| t.get(1))
        .filter(|s| !s.is_empty())
        .cloned();
    let transcript_mime_type = transcript_tag
        .and_then(|t| t.get(2))
        .filter(|s| !s.is_empty())
        .cloned();

    Ok(NipF4Episode {
        event_id: event_id.to_string(),
        author_pubkey: pubkey.to_string(),
        title,
        description,
        duration_secs,
        image_url,
        audio_url,
        audio_mime_type,
        chapters_url,
        transcript_url,
        transcript_mime_type,
        created_at,
    })
}

/// Parse a JSON `kind:10154` event payload (as delivered by a relay HTTP
/// gateway) into a [`NipF4Show`]. Returns `None` on any decode failure —
/// the discovery handler treats malformed events as silently dropped (D6).
///
/// Expected JSON shape (NIP-01 event envelope):
///
/// ```text
/// {"id":"<hex>","pubkey":"<hex>","kind":10154,"created_at":<unix>,
///  "content":"...","tags":[["title","X"], ...]}
/// ```
pub fn parse_event_json(event_json: &str) -> Option<NipF4Show> {
    #[derive(Deserialize)]
    struct Event {
        id: String,
        pubkey: String,
        kind: u32,
        #[serde(default)]
        content: String,
        #[serde(default)]
        tags: Vec<Vec<String>>,
    }
    let ev: Event = serde_json::from_str(event_json).ok()?;
    parse_kind_10154(ev.kind, &ev.id, &ev.pubkey, &ev.content, &ev.tags).ok()
}

// ── Tag helpers (local copies kept private to this module so the NIP-F4
//     parse path stays independent of the NIP-74 parse module).

fn first_tag_value<'a>(tags: &'a [Vec<String>], name: &str) -> Option<&'a str> {
    tags.iter()
        .find(|tag| tag.first().map(String::as_str) == Some(name))
        .and_then(|tag| tag.get(1).map(String::as_str))
        .filter(|s| !s.is_empty())
}

fn all_tag_values(tags: &[Vec<String>], name: &str) -> Vec<String> {
    tags.iter()
        .filter(|tag| tag.first().map(String::as_str) == Some(name))
        .filter_map(|tag| tag.get(1).cloned())
        .filter(|v| !v.is_empty())
        .collect()
}

#[cfg(test)]
#[path = "nip_f4_tests.rs"]
mod tests;
