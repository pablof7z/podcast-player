use crate::host_op_handler::PodcastHostOpHandler;

impl PodcastHostOpHandler {
    /// `podcast.player.enqueue` — alias for `podcast.queue.add_last`. Appends
    /// to the back of the **canonical** [`PlaybackQueue`] (`self.queue`), the
    /// same queue the snapshot's `Up Next` projection renders from. Validates
    /// the episode exists, then mutates + persists via the shared queue helper.
    pub(super) fn handle_enqueue(&self, episode_id: String) -> serde_json::Value {
        let exists = match self.state.library.store.lock() {
            Ok(s) => s.episode_playback_info(&episode_id).is_some(),
            Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
        };
        if !exists {
            return serde_json::json!({"ok": false, "error": format!("episode not found: {episode_id}")});
        }
        self.mutate_queue(|q| q.add_to_end(&episode_id))
    }

    /// `podcast.player.enqueue_next` — validates the episode exists, then pushes
    /// it to the front of the canonical queue.
    pub(super) fn handle_enqueue_next(&self, episode_id: String) -> serde_json::Value {
        let exists = match self.state.library.store.lock() {
            Ok(s) => s.episode_playback_info(&episode_id).is_some(),
            Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
        };
        if !exists {
            return serde_json::json!({"ok": false, "error": format!("episode not found: {episode_id}")});
        }
        self.mutate_queue(|q| q.add_to_front(&episode_id))
    }

    /// Validate and enqueue a bounded segment. Bounds are revalidated at play
    /// time against the latest stored resume point when `start_secs` is omitted.
    pub(super) fn handle_enqueue_segment(
        &self,
        episode_id: String,
        start_secs: Option<f64>,
        end_secs: f64,
        next: bool,
    ) -> serde_json::Value {
        let exists = match self.state.library.store.lock() {
            Ok(s) => s.episode_playback_info(&episode_id).is_some(),
            Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
        };
        if !exists {
            return serde_json::json!({"ok": false, "error": format!("episode not found: {episode_id}")});
        }
        if let Some(start) = start_secs {
            if !start.is_finite() {
                return serde_json::json!({"ok": false, "error": "playback start must be finite"});
            }
            if start < 0.0 {
                return serde_json::json!({"ok": false, "error": "playback start must be >= 0"});
            }
            if end_secs <= start {
                return serde_json::json!({"ok": false, "error": "playback end must be greater than start"});
            }
        }
        if !end_secs.is_finite() {
            return serde_json::json!({"ok": false, "error": "playback end must be finite"});
        }
        if next {
            self.mutate_queue(|q| q.add_segment_to_front(&episode_id, start_secs, Some(end_secs)))
        } else {
            self.mutate_queue(|q| q.add_segment_to_end(&episode_id, start_secs, Some(end_secs)))
        }
    }

    /// `podcast.player.dequeue` — alias for `podcast.queue.remove`. Removes the
    /// id from anywhere in the canonical queue (silent no-op when absent).
    pub(super) fn handle_dequeue(&self, episode_id: String) -> serde_json::Value {
        self.mutate_queue(|q| q.remove(&episode_id))
    }

    /// Remove one queue slot by Rust-owned slot id. This is the lossless path
    /// for duplicate bounded segments of the same episode.
    pub(super) fn handle_dequeue_slot(&self, queue_slot_id: String) -> serde_json::Value {
        self.mutate_queue(|q| q.remove_slot(&queue_slot_id))
    }

    /// Reorder existing queue slots by Rust-owned slot ids. Unknown/stale ids
    /// are ignored by the queue model and omitted existing ids are preserved at
    /// the tail, so Swift cannot accidentally drop queued work by sending a
    /// partial visible ordering.
    pub(super) fn handle_reorder_queue(&self, queue_slot_ids: Vec<String>) -> serde_json::Value {
        self.mutate_queue(|q| q.reorder_by_slot_ids(&queue_slot_ids))
    }

    /// `podcast.player.clear_queue` — alias for `podcast.queue.clear`. Empties
    /// the canonical queue.
    pub(super) fn handle_clear_queue(&self) -> serde_json::Value {
        self.mutate_queue(|q| q.clear())
    }

    /// Pop the front of the **canonical** queue and play it. Backs both the
    /// explicit `PlayNext` user action and the `Advance` op. Skips stale heads
    /// (ids whose episode is no longer resolvable in the store) so a removed
    /// episode at the front never strands the valid entries behind it — the
    /// same loop `maybe_auto_advance` runs, minus the `auto_play_next` gate
    /// (this is an explicit user action). Queue and store locks are taken
    /// separately per iteration (never nested) to avoid lock-order hazards.
    pub(super) fn handle_play_next(&self, correlation_id: &str) -> serde_json::Value {
        loop {
            let popped = match self.state.playback.queue.lock() {
                Ok(mut q) => q.next(),
                Err(_) => return serde_json::json!({"ok": false, "error": "queue poisoned"}),
            };
            let Some(item) = popped else {
                self.persist_queue();
                self.bump_domain(crate::state::Domain::Playback);
                return serde_json::json!({"ok": false, "error": "queue is empty"});
            };
            let resolvable = match self.state.library.store.lock() {
                Ok(s) => s.episode_playback_info(&item.episode_id).is_some(),
                Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
            };
            if resolvable {
                // Persist the new (popped) queue ordering before handing off to
                // `handle_play`, which dispatches Load+Play and bumps `rev`.
                self.persist_queue();
                return self.handle_play(
                    item.episode_id,
                    item.start_secs,
                    item.end_secs,
                    correlation_id,
                );
            }
            // Stale head already popped; continue to the next entry.
        }
    }

    /// Apply a mutation to the canonical [`PlaybackQueue`], persist the new
    /// ordering to `podcasts.json`, and bump `rev` so the next snapshot tick
    /// surfaces it. Mirrors `PlaybackState::handle_queue_action` so the
    /// `podcast.player` queue ops stay byte-identical to `podcast.queue`.
    pub(super) fn mutate_queue(
        &self,
        f: impl FnOnce(&mut crate::queue::PlaybackQueue),
    ) -> serde_json::Value {
        let items = match self.state.playback.queue.lock() {
            Ok(mut q) => {
                f(&mut q);
                q.playback_items()
            }
            Err(_) => return serde_json::json!({"ok": false, "error": "queue poisoned"}),
        };
        self.bump_domain(crate::state::Domain::Playback);
        if let Ok(mut s) = self.state.library.store.lock() {
            s.persist_with_queue(&items);
        }
        serde_json::json!({"ok": true})
    }

    /// Flush the current canonical queue ordering to `podcasts.json` without
    /// otherwise mutating it. Used after `handle_play_next` pops the head.
    pub(super) fn persist_queue(&self) {
        let items = match self.state.playback.queue.lock() {
            Ok(q) => q.playback_items(),
            Err(_) => return,
        };
        if let Ok(mut s) = self.state.library.store.lock() {
            s.persist_with_queue(&items);
        }
    }
}
