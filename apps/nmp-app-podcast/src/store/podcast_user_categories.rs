//! Kernel-owned user-curated podcast categorization.
//!
//! Stores a mapping from `PodcastId` (string form) to a set of string labels
//! the user has assigned to a podcast. Labels are free-form strings (e.g.
//! `"AI"`, `"News"`, `"Tech"`) — NOT the kernel's AI-derived
//! `CategoryBrowseItem` taxonomy, which is orthogonal.
//!
//! Persisted alongside the library in `podcasts.json` under
//! `podcast_user_categories`. `#[serde(default)]` ensures older files decode.

use super::PodcastStore;

impl PodcastStore {
    /// Set the user-curated labels for a podcast.
    ///
    /// Returns `true` when the stored value actually changed (so the caller can
    /// bump the Library domain rev). Returns `false` on a no-op. An empty
    /// `categories` vec clears the entry (idempotent).
    pub fn set_podcast_user_categories(
        &mut self,
        podcast_id: &str,
        categories: Vec<String>,
    ) -> bool {
        let current = self.podcast_user_categories.get(podcast_id);
        let changed = match current {
            None => !categories.is_empty(),
            Some(existing) => existing != &categories,
        };
        if !changed {
            return false;
        }
        if categories.is_empty() {
            self.podcast_user_categories.remove(podcast_id);
        } else {
            self.podcast_user_categories
                .insert(podcast_id.to_owned(), categories);
        }
        self.persist();
        true
    }

    /// Return the user-curated labels for a podcast, or an empty slice.
    pub fn podcast_user_categories_for(&self, podcast_id: &str) -> &[String] {
        self.podcast_user_categories
            .get(podcast_id)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }
}

#[cfg(test)]
mod tests {
    use crate::store::PodcastStore;

    #[test]
    fn set_returns_true_on_change() {
        let mut store = PodcastStore::new();
        assert!(store.set_podcast_user_categories("pod-1", vec!["AI".into()]));
        assert_eq!(store.podcast_user_categories_for("pod-1"), &["AI"]);
    }

    #[test]
    fn set_returns_false_on_noop() {
        let mut store = PodcastStore::new();
        store.set_podcast_user_categories("pod-1", vec!["AI".into()]);
        assert!(!store.set_podcast_user_categories("pod-1", vec!["AI".into()]));
    }

    #[test]
    fn empty_vec_clears_entry() {
        let mut store = PodcastStore::new();
        store.set_podcast_user_categories("pod-1", vec!["AI".into()]);
        assert!(store.set_podcast_user_categories("pod-1", vec![]));
        assert!(store.podcast_user_categories_for("pod-1").is_empty());
    }

    #[test]
    fn categories_persist_and_reload() {
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let n = SEQ.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("nmp-ucat-persist-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();

        {
            let mut store = PodcastStore::new();
            store.set_data_dir(dir.clone());
            store.set_podcast_user_categories("pod-abc", vec!["News".into(), "Tech".into()]);
        }

        let mut store2 = PodcastStore::new();
        store2.set_data_dir(dir.clone());
        assert_eq!(
            store2.podcast_user_categories_for("pod-abc"),
            &["News", "Tech"]
        );

        let _ = std::fs::remove_dir_all(&dir);
    }
}
