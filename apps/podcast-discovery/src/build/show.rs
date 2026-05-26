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
mod tests {
    use super::*;
    use podcast_core::types::podcast::{Podcast, PodcastId};
    use url::Url;
    use uuid::Uuid;

    fn fixture() -> Podcast {
        let mut p = Podcast::new("My Show");
        p.id = PodcastId::new(Uuid::parse_str("12345678-1234-1234-1234-1234567890ab").unwrap());
        p.author = "Host".into();
        p.description = "A great show".into();
        p.image_url = Some(Url::parse("https://img.example/cover.jpg").unwrap());
        p.language = Some("en".into());
        p.categories = vec!["Technology".into(), "News".into()];
        p
    }

    #[test]
    fn minimal_show_emits_title_only() {
        let p = Podcast::new("Title Only");
        let tags = podcast_to_show_tags(&p, "podcast-pk");
        assert_eq!(tags.len(), 1);
        assert_eq!(tags[0], vec!["title".to_string(), "Title Only".into()]);
    }

    #[test]
    fn full_show_emits_every_tag_in_publisher_order() {
        let p = fixture();
        let tags = podcast_to_show_tags(&p, "podcast-pk");
        let names: Vec<&str> =
            tags.iter().filter_map(|t| t.first().map(String::as_str)).collect();
        assert_eq!(names, vec!["title", "description", "p", "image", "language", "t", "t"]);
        assert_eq!(tags[2], vec!["p".to_string(), "podcast-pk".into()]);
        assert_eq!(tags[5], vec!["t".to_string(), "Technology".into()]);
        assert_eq!(tags[6], vec!["t".to_string(), "News".into()]);
    }

    #[test]
    fn no_d_tag_emitted() {
        let p = fixture();
        let tags = podcast_to_show_tags(&p, "podcast-pk");
        assert!(
            tags.iter().all(|t| t.first().map(String::as_str) != Some("d")),
            "NIP-F4 shows must not emit a d tag"
        );
    }

    #[test]
    fn show_content_uses_podcast_description() {
        assert_eq!(show_content(&fixture()), "A great show");
        assert_eq!(show_content(&Podcast::new("Empty")), "");
    }
}
