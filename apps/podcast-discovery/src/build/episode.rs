//! Build the tag set for a `kind:54` episode event (NIP-F4) from an [`Episode`].
//!
//! NIP-F4 episodes have no `d`, `a`, or `published_at` tags — the episode is a
//! regular (non-replaceable) event identified by its event `id`, and the parent
//! show is implicit from the shared podcast pubkey. Audio is represented as
//! `["audio", "<url>", "<mime>"]` instead of the old `imeta` block.

use podcast_core::types::episode::Episode;

/// Optional mime-type override for the `audio` tag. When absent, the builder
/// falls back to `episode.enclosure_mime_type` then `"audio/mp4"`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ImetaInfo {
    pub mime_type: Option<String>,
}

/// Build the canonical tags for a `kind:54` event (NIP-F4). Convenience wrapper
/// around [`episode_to_episode_tags_with_imeta`] for callers without a mime
/// override.
pub fn episode_to_episode_tags(episode: &Episode) -> Vec<Vec<String>> {
    episode_to_episode_tags_with_imeta(episode, &ImetaInfo::default())
}

/// Build the canonical tags for a `kind:54` event (NIP-F4) with an optional
/// mime-type override on the `audio` tag.
pub fn episode_to_episode_tags_with_imeta(
    episode: &Episode,
    imeta: &ImetaInfo,
) -> Vec<Vec<String>> {
    let mut tags: Vec<Vec<String>> = vec![vec!["title".into(), episode.title.clone()]];
    if !episode.description.is_empty() {
        tags.push(vec!["description".into(), episode.description.clone()]);
    }
    if let Some(dur) = episode.duration_secs {
        tags.push(vec!["duration".into(), (dur as i64).to_string()]);
    }
    if let Some(image) = &episode.image_url {
        tags.push(vec!["image".into(), image.as_str().to_string()]);
    }
    tags.push(build_audio_tag(episode, imeta));
    if let Some(chapters) = &episode.chapters_url {
        tags.push(vec![
            "chapters".into(),
            chapters.as_str().to_string(),
            "application/json+chapters".into(),
        ]);
    }
    if let Some(transcript) = &episode.publisher_transcript_url {
        tags.push(vec![
            "transcript".into(),
            transcript.as_str().to_string(),
            transcript_mime(&episode.publisher_transcript_type),
        ]);
    }
    tags
}

fn build_audio_tag(episode: &Episode, imeta: &ImetaInfo) -> Vec<String> {
    let mime = imeta
        .mime_type
        .clone()
        .or_else(|| episode.enclosure_mime_type.clone())
        .unwrap_or_else(|| "audio/mp4".into());
    vec!["audio".into(), episode.enclosure_url.to_string(), mime]
}

fn transcript_mime(kind: &Option<podcast_core::types::transcript::TranscriptKind>) -> String {
    use podcast_core::types::transcript::TranscriptKind;
    match kind {
        Some(TranscriptKind::Vtt) => "text/vtt".into(),
        Some(TranscriptKind::Srt) => "application/x-subrip".into(),
        Some(TranscriptKind::Json) => "application/json".into(),
        Some(TranscriptKind::Html) => "text/html".into(),
        Some(TranscriptKind::Text) => "text/plain".into(),
        None => "text/vtt".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{TimeZone, Utc};
    use podcast_core::types::episode::{Episode, EpisodeId};
    use podcast_core::types::podcast::PodcastId;
    use podcast_core::types::transcript::TranscriptKind;
    use url::Url;
    use uuid::Uuid;

    fn fixture() -> Episode {
        let mut ep = Episode::new(
            PodcastId::generate(),
            "https://media.example/feed.xml",
            "publisher-guid",
            "Pilot",
            Url::parse("https://media.example/ep.m4a").unwrap(),
            Utc.timestamp_opt(1_700_000_000, 0).unwrap(),
        );
        ep.id = EpisodeId::new(
            Uuid::parse_str("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee").unwrap(),
        );
        ep.description = "First episode".into();
        ep.duration_secs = Some(1800.0);
        ep
    }

    #[test]
    fn minimal_episode_emits_required_tags() {
        let ep = fixture();
        let tags = episode_to_episode_tags(&ep);
        let names: Vec<&str> =
            tags.iter().filter_map(|t| t.first().map(String::as_str)).collect();
        assert_eq!(names, vec!["title", "description", "duration", "audio"]);
    }

    #[test]
    fn no_d_published_at_a_or_imeta_tags_emitted() {
        let ep = fixture();
        let tags = episode_to_episode_tags(&ep);
        let names: Vec<&str> =
            tags.iter().filter_map(|t| t.first().map(String::as_str)).collect();
        assert!(!names.contains(&"d"), "no d tag in NIP-F4 episodes");
        assert!(!names.contains(&"published_at"), "no published_at tag in NIP-F4 episodes");
        assert!(!names.contains(&"a"), "no a tag in NIP-F4 episodes");
        assert!(!names.contains(&"imeta"), "no imeta tag in NIP-F4 episodes");
        assert!(!names.contains(&"summary"), "summary replaced by description");
    }

    #[test]
    fn audio_tag_uses_default_mime_when_not_supplied() {
        let ep = fixture();
        let tags = episode_to_episode_tags(&ep);
        let audio = tags
            .iter()
            .find(|t| t.first().map(String::as_str) == Some("audio"))
            .expect("audio tag present");
        assert_eq!(audio[1], "https://media.example/ep.m4a");
        assert_eq!(audio[2], "audio/mp4");
        assert_eq!(audio.len(), 3);
    }

    #[test]
    fn audio_tag_uses_supplied_mime() {
        let ep = fixture();
        let imeta_info = ImetaInfo { mime_type: Some("audio/m4a".into()) };
        let tags = episode_to_episode_tags_with_imeta(&ep, &imeta_info);
        let audio = tags
            .iter()
            .find(|t| t.first().map(String::as_str) == Some("audio"))
            .expect("audio tag present");
        assert_eq!(audio[1], "https://media.example/ep.m4a");
        assert_eq!(audio[2], "audio/m4a");
        assert_eq!(audio.len(), 3);
    }

    #[test]
    fn full_episode_includes_chapters_and_transcript() {
        let mut ep = fixture();
        ep.chapters_url = Some(Url::parse("https://c.example/c.json").unwrap());
        ep.publisher_transcript_url = Some(Url::parse("https://t.example/t.vtt").unwrap());
        ep.publisher_transcript_type = Some(TranscriptKind::Vtt);
        ep.image_url = Some(Url::parse("https://img.example/cover.jpg").unwrap());
        let tags = episode_to_episode_tags(&ep);
        let chapters = tags
            .iter()
            .find(|t| t.first().map(String::as_str) == Some("chapters"))
            .expect("chapters tag");
        assert_eq!(chapters[1], "https://c.example/c.json");
        assert_eq!(chapters[2], "application/json+chapters");
        let transcript = tags
            .iter()
            .find(|t| t.first().map(String::as_str) == Some("transcript"))
            .expect("transcript tag");
        assert_eq!(transcript[1], "https://t.example/t.vtt");
        assert_eq!(transcript[2], "text/vtt");
        let image = tags
            .iter()
            .find(|t| t.first().map(String::as_str) == Some("image"))
            .expect("image tag");
        assert_eq!(image[1], "https://img.example/cover.jpg");
    }
}
