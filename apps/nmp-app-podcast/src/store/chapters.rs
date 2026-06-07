use podcast_core::Chapter;

use super::PodcastStore;

impl PodcastStore {
    pub fn episode_chapters_state(&self, id_str: &str) -> Option<(Option<url::Url>, bool)> {
        for episodes in self.episodes.values() {
            if let Some(ep) = episodes.iter().find(|e| e.id.0.to_string() == id_str) {
                let loaded = ep.chapters.as_ref().map(|c| !c.is_empty()).unwrap_or(false);
                return Some((ep.chapters_url.clone(), loaded));
            }
        }
        None
    }

    /// Look up the published duration of an episode (`Episode::duration_secs`).
    ///
    /// Returns `None` when the episode is missing or when the RSS feed did
    /// not advertise a duration. The AI chapter compiler ([`crate::ai_chapters`])
    /// gates on this — without a duration there's no way to compute
    /// equally-spaced chapter offsets.
    pub fn episode_duration_secs(&self, id_str: &str) -> Option<f64> {
        for episodes in self.episodes.values() {
            if let Some(ep) = episodes.iter().find(|e| e.id.0.to_string() == id_str) {
                return ep.duration_secs;
            }
        }
        None
    }

    pub fn set_episode_chapters(&mut self, id_str: &str, chapters: Vec<Chapter>) -> bool {
        for episodes in self.episodes.values_mut() {
            if let Some(ep) = episodes.iter_mut().find(|e| e.id.0.to_string() == id_str) {
                ep.chapters = if chapters.is_empty() {
                    None
                } else {
                    Some(chapters)
                };
                self.persist();
                return true;
            }
        }
        false
    }
}

#[cfg(test)]
#[path = "chapters_tests.rs"]
mod tests;
