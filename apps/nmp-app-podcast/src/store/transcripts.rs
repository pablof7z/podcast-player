//! Episode → transcript-source accessor.
//!
//! The transcript *cache* (parsed entries keyed by episode id) lives on
//! `PodcastHandle` next to `search_results` — transcripts are transient,
//! per-session state owned by the FFI handle rather than the persisted
//! `PodcastStore`. This module only exposes the lookup the host op handler
//! needs to discover *where* to fetch the transcript bytes from, plus what
//! parser to use once the bytes arrive.

use podcast_core::TranscriptKind;

use super::PodcastStore;

impl PodcastStore {
    /// Resolve an episode UUID string to its publisher transcript URL +
    /// declared format.
    ///
    /// Returns `None` when the episode is unknown or when the RSS feed did
    /// not advertise a `<podcast:transcript>` tag. The kind defaults to
    /// `TranscriptKind::Json` (Podcasting 2.0) when the publisher URL is
    /// present but the `type` attribute is missing — that's the most common
    /// shape in the wild.
    /// Return the cached raw-text transcript for `id_str`, if one has been
    /// stored via the transcript write path.
    pub fn transcript_for(&self, id_str: &str) -> Option<&str> {
        self.transcripts.get(id_str).map(String::as_str)
    }

    /// Store a raw-text transcript for `episode_id_str`. Overwrites any
    /// previously cached transcript for the same id.
    pub fn set_transcript(&mut self, episode_id_str: String, text: String) {
        self.transcripts.insert(episode_id_str, text);
    }

    pub fn episode_publisher_transcript(&self, id_str: &str) -> Option<(String, TranscriptKind)> {
        for episodes in self.episodes.values() {
            if let Some(ep) = episodes.iter().find(|e| e.id.0.to_string() == id_str) {
                let url = ep.publisher_transcript_url.as_ref()?;
                let kind = ep
                    .publisher_transcript_type
                    .unwrap_or(TranscriptKind::Json);
                return Some((url.to_string(), kind));
            }
        }
        None
    }
}

#[cfg(test)]
#[path = "transcripts_tests.rs"]
mod tests;
