//! Build the tag set for a `kind:10154` show event (NIP-F4) from a [`Podcast`].
//!
//! Port of `NostrPodcastPublisher.publishShow` — the iOS publisher sets
//! the `["d", "podcast:guid:<uuid>"]` prefix and emits tags in a specific
//! order. The order is part of the wire contract because some relays
//! (and the Swift discovery service) prefer the first match per tag
//! name; preserving it keeps round-trips deterministic.

use podcast_core::types::podcast::Podcast;

/// Prefix used for the show `d` tag — matches Swift
/// `"podcast:guid:\(podcast.id.uuidString.lowercased())"`. Kept private
/// so callers go through [`podcast_to_show_tags`] / [`show_d_tag`] and
/// the prefix lives in one place.
const SHOW_D_PREFIX: &str = "podcast:guid:";

/// Build the canonical `d` tag value for a podcast.
pub fn show_d_tag(podcast: &Podcast) -> String {
    format!("{SHOW_D_PREFIX}{}", podcast.id.0.simple().to_string().to_ascii_lowercase())
}

/// The string emitted as the event's `content` field.
///
/// The Swift publisher passes `podcast.description` as content; we mirror
/// that so other Nostr clients (which read `content` rather than the
/// `summary` tag) see the same description text.
pub fn show_content(podcast: &Podcast) -> String {
    podcast.description.clone()
}

/// Build the tag list for a `kind:10154` show event (NIP-F4).
///
/// `agent_pubkey` is the hex pubkey of the signer (the agent key that
/// publishes the show). It's threaded explicitly because this function
/// is pure data — the signer is owned by the kernel-side action module.
pub fn podcast_to_show_tags(podcast: &Podcast, agent_pubkey: &str) -> Vec<Vec<String>> {
    let mut tags: Vec<Vec<String>> = vec![
        vec!["d".into(), show_d_tag(podcast)],
        vec!["title".into(), podcast.title.clone()],
    ];
    if !podcast.description.is_empty() {
        tags.push(vec!["summary".into(), podcast.description.clone()]);
    }
    if !podcast.author.is_empty() {
        tags.push(vec!["p".into(), agent_pubkey.to_string()]);
    }
    if let Some(image) = &podcast.image_url {
        tags.push(vec!["image".into(), image.as_str().to_string()]);
    }
    if let Some(lang) = &podcast.language {
        if !lang.is_empty() {
            tags.push(vec!["language".into(), lang.clone()]);
        }
    }
    for category in &podcast.categories {
        tags.push(vec!["t".into(), category.clone()]);
    }
    tags
}

#[cfg(test)]
#[path = "show_tests.rs"]
mod tests;
