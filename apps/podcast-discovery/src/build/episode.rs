//! Build the tag set for a `kind:54` episode event (NIP-F4) from an [`Episode`].
//!
//! The Swift publisher composes the `imeta` block from the post-upload
//! audio URL + raw audio bytes (for SHA-256). At the M10.A layer we don't
//! have direct access to those bytes — the kernel-side action module
//! computes them once during Blossom upload and threads them in via
//! [`ImetaInfo`]. The simpler [`episode_to_episode_tags`] entry point
//! matches the task spec (URL only; no hash/size) and is the value
//! callers reach for when they don't have the upload metadata.

use podcast_core::types::episode::Episode;

use crate::kinds::KIND_SHOW;

/// Optional `imeta` enrichment available after a Blossom upload.
///
/// `mime_type` defaults to `"audio/mp4"` (matches the Swift publisher's
/// hard-coded value) when callers don't supply one.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ImetaInfo {
    pub mime_type: Option<String>,
    pub sha256_hex: Option<String>,
    pub size_bytes: Option<u64>,
    pub duration_secs: Option<u64>,
}

/// Build the canonical tags for a `kind:54` event (NIP-F4). Convenience wrapper
/// around [`episode_to_episode_tags_with_imeta`] for callers that do not
/// have post-upload metadata in hand.
pub fn episode_to_episode_tags(
    episode: &Episode,
    show_pubkey: &str,
    show_d: &str,
) -> Vec<Vec<String>> {
    episode_to_episode_tags_with_imeta(episode, show_pubkey, show_d, &ImetaInfo::default())
}

/// Build the canonical tags for a `kind:54` event (NIP-F4) with full `imeta`
/// metadata. Mirrors the tag order in
/// `App/Sources/Services/NostrPodcastPublisher.publishEpisode`.
pub fn episode_to_episode_tags_with_imeta(
    episode: &Episode,
    show_pubkey: &str,
    show_d: &str,
    imeta: &ImetaInfo,
) -> Vec<Vec<String>> {
    let pub_date_unix = episode.pub_date.timestamp().to_string();
    let mut tags: Vec<Vec<String>> = vec![
        vec!["d".into(), episode_d_tag(episode)],
        vec!["title".into(), episode.title.clone()],
        vec!["published_at".into(), pub_date_unix],
        vec![
            "a".into(),
            format!("{KIND_SHOW}:{show_pubkey}:{show_d}"),
        ],
    ];
    if !episode.description.is_empty() {
        tags.push(vec!["summary".into(), episode.description.clone()]);
    }
    if let Some(dur) = episode.duration_secs {
        tags.push(vec!["duration".into(), (dur as i64).to_string()]);
    }
    if let Some(image) = &episode.image_url {
        tags.push(vec!["image".into(), image.as_str().to_string()]);
    }
    tags.push(build_imeta_tag(episode, imeta));
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

/// Stable `d` tag value for an episode. Mirrors Swift
/// `"podcast:item:guid:\(episode.id.uuidString.lowercased())"`.
pub fn episode_d_tag(episode: &Episode) -> String {
    format!(
        "podcast:item:guid:{}",
        episode.id.0.simple().to_string().to_ascii_lowercase()
    )
}

fn build_imeta_tag(episode: &Episode, imeta: &ImetaInfo) -> Vec<String> {
    let mut parts: Vec<String> = vec!["imeta".into()];
    parts.push(format!("url {}", episode.enclosure_url));
    let mime = imeta
        .mime_type
        .clone()
        .or_else(|| episode.enclosure_mime_type.clone())
        .unwrap_or_else(|| "audio/mp4".into());
    parts.push(format!("m {mime}"));
    if let Some(hash) = &imeta.sha256_hex {
        parts.push(format!("x {hash}"));
    }
    if let Some(size) = imeta.size_bytes {
        parts.push(format!("size {size}"));
    }
    let duration = imeta
        .duration_secs
        .or_else(|| episode.duration_secs.map(|d| d as u64));
    if let Some(dur) = duration {
        parts.push(format!("duration {dur}"));
    }
    parts
}

fn transcript_mime(
    kind: &Option<podcast_core::types::transcript::TranscriptKind>,
) -> String {
    use podcast_core::types::transcript::TranscriptKind;
    match kind {
        Some(TranscriptKind::Vtt) => "text/vtt".into(),
        Some(TranscriptKind::Srt) => "application/x-subrip".into(),
        Some(TranscriptKind::Json) => "application/json".into(),
        Some(TranscriptKind::Html) => "text/html".into(),
        Some(TranscriptKind::Text) => "text/plain".into(),
        // Conservative default — the publisher's primary MIME has historically
        // been VTT (Podcasting 2.0 transcripts ship as VTT by default).
        None => "text/vtt".into(),
    }
}

#[cfg(test)]
#[path = "episode_tests.rs"]
mod tests;
