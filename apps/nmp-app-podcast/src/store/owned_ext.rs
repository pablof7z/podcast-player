//! `PodcastStore` extensions for NIP-F4 owned-podcast publishing
//! (features #27/#28).
//!
//! Lives in a sibling file to keep [`super::mod`] under the 500-LOC hard
//! limit (AGENTS.md). The methods are plain `impl PodcastStore` —
//! Rust's coherence rules allow multiple `impl` blocks for the same
//! type within a crate.

use podcast_core::{Episode, Podcast};

use super::PodcastStore;

impl PodcastStore {
    /// Stamp `owner_pubkey_hex` onto a podcast row, flushing to disk
    /// when a data dir is bound. Silent no-op when the podcast isn't
    /// found — the caller (NIP-F4 publish module) has already
    /// generated a key and treats a missing podcast as "out of band".
    pub fn set_owner_pubkey_hex(&mut self, podcast_id_str: &str, pubkey_hex: String) {
        if let Some(id) = self.id_for_str(podcast_id_str) {
            if let Some(p) = self.podcasts.get_mut(&id) {
                p.owner_pubkey_hex = Some(pubkey_hex);
                self.persist();
            }
        }
    }

    /// Clear the owner pubkey on a podcast row. Mirror of
    /// [`Self::set_owner_pubkey_hex`] for the `remove_owned_podcast` op.
    pub fn clear_owner_pubkey_hex(&mut self, podcast_id_str: &str) {
        if let Some(id) = self.id_for_str(podcast_id_str) {
            if let Some(p) = self.podcasts.get_mut(&id) {
                p.owner_pubkey_hex = None;
                self.persist();
            }
        }
    }

    /// Resolve an episode UUID string to a cloned `(Podcast, Episode)`
    /// pair. Used by the NIP-F4 publish module to build a `kind:54`
    /// event without holding the store lock across the tag construction.
    pub fn episode_with_podcast_clone(
        &self,
        episode_id_str: &str,
    ) -> Option<(Podcast, Episode)> {
        for (podcast_id, episodes) in &self.episodes {
            if let Some(ep) = episodes.iter().find(|e| e.id.0.to_string() == episode_id_str) {
                if let Some(p) = self.podcasts.get(podcast_id) {
                    return Some((p.clone(), ep.clone()));
                }
            }
        }
        None
    }

    /// Helper — resolve the string form of a podcast UUID back to the
    /// typed key. Returns `None` when nothing matches.
    fn id_for_str(&self, podcast_id_str: &str) -> Option<podcast_core::PodcastId> {
        self.podcasts
            .values()
            .find(|p| p.id.0.to_string() == podcast_id_str)
            .map(|p| p.id)
    }
}

#[cfg(test)]
#[path = "owned_ext_tests.rs"]
mod tests;
