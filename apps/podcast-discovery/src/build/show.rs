//! Build the tag set for a `kind:10154` show event (NIP-F4) from a [`Podcast`].
//!
//! Port of `NostrPodcastPublisher.publishShow` — the iOS publisher emits tags
//! in a specific order. Preserving that order keeps round-trips deterministic
//! (some relays and the Swift discovery service prefer the first match per tag
//! name).

use podcast_core::types::podcast::Podcast;

/// The string emitted as the event's `content` field.
pub fn show_content(podcast: &Podcast) -> String {
    podcast.description.clone()
}

/// Build the tag list for a `kind:10154` show event (NIP-F4).
///
/// `podcast_pubkey` is the hex pubkey of the per-podcast key that signs the
/// event. Threaded explicitly because this function is pure data — the signer
/// is owned by the kernel-side action module.
///
/// NIP-F4 shows have no `d` tag; the show is identified by pubkey alone.
pub fn podcast_to_show_tags(podcast: &Podcast, podcast_pubkey: &str) -> Vec<Vec<String>> {
    let mut tags: Vec<Vec<String>> = vec![vec!["title".into(), podcast.title.clone()]];
    if !podcast.description.is_empty() {
        tags.push(vec!["description".into(), podcast.description.clone()]);
    }
    if !podcast.author.is_empty() {
        tags.push(vec!["p".into(), podcast_pubkey.to_string()]);
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
