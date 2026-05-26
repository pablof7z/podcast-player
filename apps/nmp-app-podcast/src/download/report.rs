//! `DownloadQueue` report handler — ingest `DownloadReport` events from the
//! iOS download capability into queue state mutations.
//!
//! Extracted from `download/mod.rs` to keep that file within the 300-line
//! soft limit. The public entry point is [`DownloadQueue::handle_report`].

use crate::capability::{DownloadCommand, DownloadReport};

use super::{DownloadItemState, DownloadQueue};

impl DownloadQueue {
    /// Ingest a [`DownloadReport`] event and update per-episode state.
    ///
    /// Returns any follow-up [`DownloadCommand`]s that should be dispatched
    /// back to the iOS download capability (e.g. `StartDownload` for the next
    /// queued item when a slot frees up).
    pub fn handle_report(&mut self, report: DownloadReport) -> Vec<DownloadCommand> {
        match report {
            DownloadReport::Progress {
                episode_id,
                bytes_downloaded,
                total_bytes,
            } => {
                if let Some(item) = self.items.get_mut(&episode_id) {
                    item.bytes_downloaded = bytes_downloaded;
                    if total_bytes.is_some() {
                        item.total_bytes = total_bytes;
                    }
                    // A `Progress` on a `Paused` item indicates the executor
                    // resumed faster than our pause command landed; reconcile.
                    if item.state == DownloadItemState::Paused {
                        item.state = DownloadItemState::Active;
                    }
                }
                Vec::new()
            }
            DownloadReport::Completed {
                episode_id,
                local_path,
            } => {
                if let Some(item) = self.items.get_mut(&episode_id) {
                    item.state = DownloadItemState::Completed;
                    item.local_path = Some(local_path);
                    item.error = None;
                    // Once complete, the totals are authoritative; if the
                    // server never reported Content-Length, fall back to
                    // bytes_downloaded so progress_fraction() reads 1.0.
                    if item.total_bytes.is_none() {
                        item.total_bytes = Some(item.bytes_downloaded);
                    }
                }
                self.start_next_queued()
            }
            DownloadReport::Failed { episode_id, error } => {
                if let Some(item) = self.items.get_mut(&episode_id) {
                    item.state = DownloadItemState::Failed;
                    item.error = Some(error);
                }
                self.start_next_queued()
            }
            DownloadReport::Cancelled { episode_id } => {
                if let Some(item) = self.items.get_mut(&episode_id) {
                    item.state = DownloadItemState::Cancelled;
                }
                self.start_next_queued()
            }
            DownloadReport::Paused {
                episode_id,
                bytes_downloaded,
            } => {
                if let Some(item) = self.items.get_mut(&episode_id) {
                    item.state = DownloadItemState::Paused;
                    item.bytes_downloaded = bytes_downloaded;
                    // Paused keeps the slot — don't start anything new.
                }
                Vec::new()
            }
        }
    }

    /// Pull the next FIFO `Queued` item up to the concurrency cap and emit
    /// `StartDownload` commands for each. Called from terminal transitions
    /// (`Completed`, `Failed`, `Cancelled`); a no-op when the queue is empty
    /// or the cap is already saturated.
    fn start_next_queued(&mut self) -> Vec<DownloadCommand> {
        let mut commands = Vec::new();
        while self.active_count() < self.max_concurrent {
            let Some(next_id) = self.queue_order.first().cloned() else {
                break;
            };
            self.queue_order.remove(0);
            let Some(item) = self.items.get_mut(&next_id) else {
                continue;
            };
            // Defensive: if the item was cancelled while still queued
            // (cancel() handles that synchronously), skip it.
            if item.state != DownloadItemState::Queued {
                continue;
            }
            item.state = DownloadItemState::Active;
            commands.push(DownloadCommand::start(item.url.clone(), next_id, None));
        }
        commands
    }
}

