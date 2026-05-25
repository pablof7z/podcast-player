//! Agent-generated TTS-episode handling (feature #43).
//!
//! The [`TtsEpisodeHandler`] owns the in-memory list of
//! [`TtsEpisodeSummary`] on the [`crate::ffi::PodcastHandle`] and routes
//! the three actions in the `podcast.tts` namespace:
//!
//! * `generate` — mint a new TTS episode with a placeholder script
//!   (LLM-script generation is a follow-up).
//! * `delete` — drop an episode from the list. Idempotent.
//! * `play` — emit a [`VoiceCommand::Speak`] to the iOS voice
//!   capability and flip the episode's `status` to `"played"`.
//!
//! Pulled into its own module to keep
//! [`crate::host_op_handler::PodcastHostOpHandler`] under the 500-LOC
//! ceiling. The handler holds the same `app: *mut NmpApp` raw pointer
//! and the shared `tts_episodes` / `rev` slots, mirrors the lock
//! discipline (release every mutex before `dispatch_capability`), and
//! returns the canonical `{"ok": …}` envelope per D6.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use chrono::Utc;
use nmp_core::substrate::CapabilityRequest;
use nmp_ffi::NmpApp;
use uuid::Uuid;

use crate::capability::voice::{VoiceCommand, VOICE_CAPABILITY_NAMESPACE};
use crate::ffi::actions::tts_module::TtsEpisodeAction;
use crate::ffi::projections::TtsEpisodeSummary;

/// Default length when `length_minutes` is omitted by the caller.
/// Matches the iOS sheet's initial stepper value so the two surfaces
/// stay aligned without an extra round-trip.
pub(crate) const DEFAULT_LENGTH_MINUTES: u32 = 5;

/// Maximum length the kernel accepts. Clamping here (vs. validating
/// in Swift) keeps policy in Rust per D7. The iOS sheet's `Stepper`
/// bounds match.
pub(crate) const MAX_LENGTH_MINUTES: u32 = 15;

/// Routes `podcast.tts.*` actions for [`crate::host_op_handler::PodcastHostOpHandler`].
///
/// Owns no extra state beyond the shared `tts_episodes`, `rev`, and
/// `app` pointer — the handler is a thin policy layer over the
/// in-memory list.
pub(crate) struct TtsEpisodeHandler {
    app: *mut NmpApp,
    tts_episodes: Arc<Mutex<Vec<TtsEpisodeSummary>>>,
    rev: Arc<AtomicU64>,
}

// SAFETY: same caller-contract as `PodcastHostOpHandler` — the
// `*mut NmpApp` is only ever read, never mutated, and the iOS
// caller fences any in-flight callbacks via the actor thread join
// in `nmp_app_free`.
unsafe impl Send for TtsEpisodeHandler {}
unsafe impl Sync for TtsEpisodeHandler {}

impl TtsEpisodeHandler {
    pub(crate) fn new(
        app: *mut NmpApp,
        tts_episodes: Arc<Mutex<Vec<TtsEpisodeSummary>>>,
        rev: Arc<AtomicU64>,
    ) -> Self {
        Self {
            app,
            tts_episodes,
            rev,
        }
    }

    /// Entry point — dispatch to one of the three op handlers.
    pub(crate) fn handle(
        &self,
        action: TtsEpisodeAction,
        correlation_id: &str,
    ) -> serde_json::Value {
        match action {
            TtsEpisodeAction::Generate {
                topic,
                length_minutes,
            } => self.handle_generate(topic, length_minutes),
            TtsEpisodeAction::Delete { episode_id } => self.handle_delete(episode_id),
            TtsEpisodeAction::Play { episode_id } => self.handle_play(episode_id, correlation_id),
        }
    }

    fn handle_generate(
        &self,
        topic: String,
        length_minutes: Option<u32>,
    ) -> serde_json::Value {
        let trimmed = topic.trim();
        if trimmed.is_empty() {
            return serde_json::json!({"ok": false, "error": "topic is empty"});
        }
        let length = length_minutes
            .unwrap_or(DEFAULT_LENGTH_MINUTES)
            .clamp(1, MAX_LENGTH_MINUTES);
        let id = Uuid::new_v4().to_string();
        let script = placeholder_script(trimmed);
        let title = derive_title(trimmed);
        let episode = TtsEpisodeSummary {
            id: id.clone(),
            title,
            script,
            duration_estimate_secs: (length as f64) * 60.0,
            created_at: Utc::now().timestamp(),
            status: "ready".into(),
            voice_id: None,
        };
        match self.tts_episodes.lock() {
            Ok(mut list) => list.push(episode),
            Err(_) => return serde_json::json!({"ok": false, "error": "tts list poisoned"}),
        }
        self.rev.fetch_add(1, Ordering::Relaxed);
        serde_json::json!({"ok": true, "episode_id": id})
    }

    fn handle_delete(&self, episode_id: String) -> serde_json::Value {
        let removed = match self.tts_episodes.lock() {
            Ok(mut list) => {
                let before = list.len();
                list.retain(|ep| ep.id != episode_id);
                before != list.len()
            }
            Err(_) => return serde_json::json!({"ok": false, "error": "tts list poisoned"}),
        };
        if removed {
            self.rev.fetch_add(1, Ordering::Relaxed);
        }
        // Idempotent — a delete for an unknown id is still `ok`.
        serde_json::json!({"ok": true})
    }

    fn handle_play(&self, episode_id: String, correlation_id: &str) -> serde_json::Value {
        // Extract script + flip status under the lock; release before
        // `dispatch_capability` so a slow voice executor can't block
        // snapshot reads.
        let (script, voice_id) = match self.tts_episodes.lock() {
            Ok(mut list) => {
                let Some(ep) = list.iter_mut().find(|e| e.id == episode_id) else {
                    return serde_json::json!({
                        "ok": false,
                        "error": format!("tts episode not found: {episode_id}")
                    });
                };
                ep.status = "played".into();
                (ep.script.clone(), ep.voice_id.clone())
            }
            Err(_) => return serde_json::json!({"ok": false, "error": "tts list poisoned"}),
        };
        self.rev.fetch_add(1, Ordering::Relaxed);

        let cmd = VoiceCommand::Speak {
            text: script,
            voice_id,
            request_id: format!("tts-{episode_id}"),
        };
        let payload_json = match serde_json::to_string(&cmd) {
            Ok(s) => s,
            Err(e) => return serde_json::json!({"ok": false, "error": e.to_string()}),
        };
        let req = CapabilityRequest {
            namespace: VOICE_CAPABILITY_NAMESPACE.to_owned(),
            correlation_id: correlation_id.to_owned(),
            payload_json,
        };
        // SAFETY: `app` is a stable `*mut NmpApp` that outlives this
        // handler (the iOS caller calls `nmp_app_podcast_unregister`
        // before `nmp_app_free`, which joins the actor thread).
        let _ = unsafe { &*self.app }.dispatch_capability(&req);
        serde_json::json!({"ok": true})
    }
}

/// Produces the fixed placeholder script the iOS executor will speak.
///
/// The shape is intentionally stable so the iOS list can render a
/// preview without conditional logic. Once the LLM follow-up lands,
/// this function gets swapped for the real generator and the wire
/// shape stays the same.
fn placeholder_script(topic: &str) -> String {
    format!(
        "This is an AI-generated episode about {topic}. Full script generation via LLM is a follow-up feature."
    )
}

/// Derives a short title from the topic. Trims, collapses internal
/// whitespace, and caps at 80 chars so the iOS list cell renders
/// predictably. Empty topics are caught upstream so we don't have to
/// guard here.
fn derive_title(topic: &str) -> String {
    let collapsed: String = topic.split_whitespace().collect::<Vec<_>>().join(" ");
    if collapsed.chars().count() <= 80 {
        collapsed
    } else {
        let truncated: String = collapsed.chars().take(77).collect();
        format!("{truncated}…")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn empty_handler() -> (TtsEpisodeHandler, Arc<Mutex<Vec<TtsEpisodeSummary>>>) {
        let list = Arc::new(Mutex::new(Vec::new()));
        let rev = Arc::new(AtomicU64::new(0));
        // `app` pointer is only used by `handle_play` to call
        // `dispatch_capability`. The other handlers don't deref it, so
        // a null pointer is safe for these tests.
        let h = TtsEpisodeHandler::new(std::ptr::null_mut(), list.clone(), rev);
        (h, list)
    }

    #[test]
    fn generate_with_default_length_yields_5_minute_estimate() {
        let (h, list) = empty_handler();
        let response = h.handle(
            TtsEpisodeAction::Generate {
                topic: "AI news".into(),
                length_minutes: None,
            },
            "corr-1",
        );
        assert_eq!(response["ok"], true);
        let episode_id = response["episode_id"].as_str().expect("episode_id");
        let stored = list.lock().unwrap();
        assert_eq!(stored.len(), 1);
        assert_eq!(stored[0].id, episode_id);
        assert_eq!(stored[0].title, "AI news");
        assert_eq!(stored[0].duration_estimate_secs, 300.0);
        assert_eq!(stored[0].status, "ready");
        assert!(stored[0].script.contains("AI news"));
    }

    #[test]
    fn generate_clamps_length_to_15_minutes() {
        let (h, list) = empty_handler();
        h.handle(
            TtsEpisodeAction::Generate {
                topic: "Too long".into(),
                length_minutes: Some(99),
            },
            "corr-1",
        );
        assert_eq!(list.lock().unwrap()[0].duration_estimate_secs, 15.0 * 60.0);
    }

    #[test]
    fn generate_clamps_length_to_at_least_one_minute() {
        let (h, list) = empty_handler();
        h.handle(
            TtsEpisodeAction::Generate {
                topic: "Zero".into(),
                length_minutes: Some(0),
            },
            "corr-1",
        );
        assert_eq!(list.lock().unwrap()[0].duration_estimate_secs, 60.0);
    }

    #[test]
    fn generate_rejects_empty_topic() {
        let (h, list) = empty_handler();
        let response = h.handle(
            TtsEpisodeAction::Generate {
                topic: "   ".into(),
                length_minutes: None,
            },
            "corr-1",
        );
        assert_eq!(response["ok"], false);
        assert!(list.lock().unwrap().is_empty());
    }

    #[test]
    fn delete_removes_matching_episode() {
        let (h, list) = empty_handler();
        let response = h.handle(
            TtsEpisodeAction::Generate {
                topic: "Topic".into(),
                length_minutes: None,
            },
            "corr-1",
        );
        let id = response["episode_id"].as_str().unwrap().to_string();
        assert_eq!(list.lock().unwrap().len(), 1);
        let del = h.handle(TtsEpisodeAction::Delete { episode_id: id }, "corr-1");
        assert_eq!(del["ok"], true);
        assert!(list.lock().unwrap().is_empty());
    }

    #[test]
    fn delete_unknown_id_is_idempotent_ok() {
        let (h, _list) = empty_handler();
        let del = h.handle(
            TtsEpisodeAction::Delete {
                episode_id: "nope".into(),
            },
            "corr-1",
        );
        assert_eq!(del["ok"], true);
    }

    #[test]
    fn play_unknown_id_returns_error() {
        let (h, _list) = empty_handler();
        let response = h.handle(
            TtsEpisodeAction::Play {
                episode_id: "nope".into(),
            },
            "corr-1",
        );
        assert_eq!(response["ok"], false);
    }

    #[test]
    fn derive_title_collapses_whitespace_and_caps_length() {
        assert_eq!(derive_title("  hello   world  "), "hello world");
        let long = "x".repeat(200);
        let title = derive_title(&long);
        // 77 chars + "…"
        assert_eq!(title.chars().count(), 78);
        assert!(title.ends_with('…'));
    }

    #[test]
    fn placeholder_script_contains_topic() {
        let script = placeholder_script("Rustlang");
        assert!(script.contains("Rustlang"));
    }
}
