use crate::capability::{AudioCommand, DownloadCommand};
use crate::host_op_handler::PodcastHostOpHandler;

impl PodcastHostOpHandler {
    /// Relative seek by `delta_secs` (positive = forward, negative = backward).
    /// Reads the current position from the live actor state so the shell never
    /// needs to track position client-side (D0).
    pub(super) fn handle_skip(&self, delta_secs: f64, correlation_id: &str) -> serde_json::Value {
        let current = match self.state.playback.player.lock() {
            Ok(a) => {
                let state = a.state();
                if state.episode_id.is_none() {
                    return serde_json::json!({"ok": false, "error": "nothing is currently loaded"});
                }
                state.position_secs
            }
            Err(_) => return serde_json::json!({"ok": false, "error": "player_actor poisoned"}),
        };
        let target = (current + delta_secs).max(0.0);
        self.dispatch_audio_json(AudioCommand::seek(target), correlation_id)
    }

    pub(super) fn handle_player_download(
        &self,
        episode_id: String,
        url: String,
        correlation_id: &str,
    ) -> serde_json::Value {
        let exists = match self.state.library.store.lock() {
            Ok(s) => s.episode_enclosure_url(&episode_id).is_some(),
            Err(_) => return serde_json::json!({"ok": false, "error": "store poisoned"}),
        };
        if !exists {
            return serde_json::json!({
                "ok": false,
                "error": format!("episode not found: {episode_id}")
            });
        }

        // Route through the one canonical download path so this initiator shares
        // concurrency control, the download-queue snapshot, and the per-episode
        // event log with the `podcast.download` op — otherwise a download started
        // here would emit no pipeline events and the Diagnostics log would stay
        // empty for it.
        match self.start_episode_download(&episode_id, &url, correlation_id, false) {
            Ok(()) => serde_json::json!({"ok": true}),
            Err(e) => serde_json::json!({"ok": false, "error": e}),
        }
    }

    pub(super) fn handle_download_command(
        &self,
        f: impl FnOnce(&mut crate::download::DownloadQueue) -> Option<DownloadCommand>,
        correlation_id: &str,
    ) -> serde_json::Value {
        let command = match self.state.playback.downloads.lock() {
            Ok(mut q) => f(&mut q),
            Err(_) => return serde_json::json!({"ok": false, "error": "download_queue poisoned"}),
        };
        self.bump_domain(crate::state::Domain::Downloads);
        match command {
            Some(cmd) => self.dispatch_download_json(cmd, correlation_id),
            None => serde_json::json!({"ok": true}),
        }
    }
}
