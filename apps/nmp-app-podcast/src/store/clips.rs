//! User-saved clip accessors on [`PodcastStore`].
//!
//! Persistence is handled by the parent module's `to_persisted` /
//! `load_from_disk` glue.  Every mutator calls `self.persist()` so the
//! change survives an app restart (D0).

use crate::clip_handler::ClipRecord;

use super::PodcastStore;

impl PodcastStore {
    /// Return an immutable reference to the full clip list.
    pub fn clips(&self) -> &[ClipRecord] {
        &self.clips
    }

    /// Replace the whole clip list and flush to disk.
    ///
    /// Used by `ClipHandler` after every create / delete so the persisted
    /// state is always in sync with the in-memory `Slot`.
    pub fn set_clips(&mut self, clips: Vec<ClipRecord>) {
        self.clips = clips;
        self.persist();
    }
}
