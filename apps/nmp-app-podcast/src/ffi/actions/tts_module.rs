//! Compound TTS-episode ActionModule — routes all `"podcast.tts"` dispatches.
//!
//! Feature #43 (NMP migration) — agent-generated short "podcast" episodes
//! produced by an LLM and read aloud via the on-device TTS engine
//! (`AVSpeechSynthesizer` for now; ElevenLabs is a follow-up).
//!
//! ## Wire shape
//!
//! Swift encodes every TTS action as `{"op":"<variant>", ...fields}`. The
//! `#[serde(tag = "op", rename_all = "snake_case")]` discriminator maps the
//! string `op` value to the enum variant:
//!
//! ```text
//! podcast.tts.generate — TtsEpisodeAction::Generate { topic, length_minutes? }
//! podcast.tts.delete   — TtsEpisodeAction::Delete { episode_id }
//! podcast.tts.play     — TtsEpisodeAction::Play { episode_id }
//! ```
//!
//! ## Routing
//!
//! Following the same pattern as [`super::podcast_module::PodcastActionModule`],
//! `execute` forwards the entire action as `ActorCommand::DispatchHostOp` so
//! the host op handler (running on the actor thread) can mutate the in-memory
//! `tts_episodes` slot on the handle and dispatch the voice capability for
//! `play` without the kernel naming podcast-domain nouns (D0).

use serde::{Deserialize, Serialize};

use nmp_core::substrate::ActionModule;
use nmp_core::ActorCommand;

/// Namespace string for every action this module routes.
pub const TTS_NAMESPACE: &str = "podcast.tts";

/// `podcast.tts.generate` — mint a new TTS episode for the given topic.
pub const ACTION_TTS_GENERATE: &str = "podcast.tts.generate";
/// `podcast.tts.delete` — drop a TTS episode from the in-memory list.
pub const ACTION_TTS_DELETE: &str = "podcast.tts.delete";
/// `podcast.tts.play` — speak the episode's script via the voice capability.
pub const ACTION_TTS_PLAY: &str = "podcast.tts.play";

/// Wire enum for all `"podcast.tts"` namespace actions.
///
/// `#[serde(tag = "op", rename_all = "snake_case")]` makes the JSON
/// discriminator the lowercase snake-case variant name:
/// `Generate` → `{"op":"generate","topic":"…"}`.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum TtsEpisodeAction {
    /// Mint a new TTS episode.
    ///
    /// `length_minutes` is optional. When unset the handler picks a 5
    /// minute default; the same default lives in the iOS sheet's
    /// stepper initial value so the two surfaces stay aligned. The
    /// requested length only influences the displayed duration
    /// estimate; the actual script is a fixed placeholder until the
    /// LLM follow-up.
    Generate {
        topic: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        length_minutes: Option<u32>,
    },
    /// Remove the TTS episode with the given id. Idempotent — a delete
    /// for an unknown id returns `{"ok":true}` so the iOS list view
    /// can swipe-delete without race-checking the snapshot.
    Delete { episode_id: String },
    /// Speak the script of the TTS episode with the given id through
    /// the active voice capability. Flips the episode's `status` to
    /// `"played"` synchronously (regardless of whether the iOS-side
    /// `VoiceReport::Finished` ever arrives — the executor failure
    /// surface is the voice projection, not the TTS-episode list).
    Play { episode_id: String },
}

/// Single action module for the whole `"podcast.tts"` namespace.
///
/// `execute` serializes the typed [`TtsEpisodeAction`] back to JSON and
/// hands it to the actor as `ActorCommand::DispatchHostOp`. The installed
/// `PodcastHostOpHandler` deserializes it and runs the op. All policy
/// (id minting, status transitions, voice-capability dispatch) lives in
/// the handler; this module is pure routing — same pattern as
/// [`super::podcast_module::PodcastActionModule`].
pub struct TtsEpisodeModule;

impl ActionModule for TtsEpisodeModule {
    const NAMESPACE: &'static str = TTS_NAMESPACE;

    type Action = TtsEpisodeAction;

    fn is_async_completing() -> bool {
        false
    }

    fn execute(
        action: Self::Action,
        correlation_id: &str,
        send: &dyn Fn(ActorCommand),
    ) -> Result<(), String> {
        let action_json = serde_json::to_string(&action).map_err(|e| e.to_string())?;
        send(ActorCommand::DispatchHostOp {
            action_json,
            correlation_id: correlation_id.to_owned(),
        });
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn namespace_matches_documented_string() {
        assert_eq!(TTS_NAMESPACE, "podcast.tts");
        assert_eq!(TtsEpisodeModule::NAMESPACE, "podcast.tts");
    }

    #[test]
    fn action_ids_match_documented_strings() {
        assert_eq!(ACTION_TTS_GENERATE, "podcast.tts.generate");
        assert_eq!(ACTION_TTS_DELETE, "podcast.tts.delete");
        assert_eq!(ACTION_TTS_PLAY, "podcast.tts.play");
    }

    #[test]
    fn generate_action_round_trips_with_length() {
        let action = TtsEpisodeAction::Generate {
            topic: "AI news this week".into(),
            length_minutes: Some(7),
        };
        let json = serde_json::to_string(&action).expect("encode");
        assert!(json.contains(r#""op":"generate""#));
        assert!(json.contains(r#""topic":"AI news this week""#));
        assert!(json.contains(r#""length_minutes":7"#));
        let decoded: TtsEpisodeAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, action);
    }

    #[test]
    fn generate_action_omits_none_length() {
        let action = TtsEpisodeAction::Generate {
            topic: "Anything".into(),
            length_minutes: None,
        };
        let json = serde_json::to_string(&action).expect("encode");
        assert_eq!(json, r#"{"op":"generate","topic":"Anything"}"#);
        let decoded: TtsEpisodeAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, action);
    }

    #[test]
    fn delete_action_round_trips() {
        let action = TtsEpisodeAction::Delete {
            episode_id: "tts-1".into(),
        };
        let json = serde_json::to_string(&action).expect("encode");
        assert!(json.contains(r#""op":"delete""#));
        assert!(json.contains(r#""episode_id":"tts-1""#));
        let decoded: TtsEpisodeAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, action);
    }

    #[test]
    fn play_action_round_trips() {
        let action = TtsEpisodeAction::Play {
            episode_id: "tts-1".into(),
        };
        let json = serde_json::to_string(&action).expect("encode");
        assert!(json.contains(r#""op":"play""#));
        assert!(json.contains(r#""episode_id":"tts-1""#));
        let decoded: TtsEpisodeAction = serde_json::from_str(&json).expect("decode");
        assert_eq!(decoded, action);
    }

    #[test]
    fn execute_emits_dispatch_host_op() {
        let action = TtsEpisodeAction::Generate {
            topic: "Test".into(),
            length_minutes: None,
        };
        let commands = std::sync::Mutex::new(Vec::<ActorCommand>::new());
        TtsEpisodeModule::execute(action, "corr-tts-1", &|cmd| {
            commands.lock().unwrap().push(cmd);
        })
        .expect("execute ok");
        let commands = commands.into_inner().unwrap();
        assert_eq!(commands.len(), 1);
        let ActorCommand::DispatchHostOp {
            action_json,
            correlation_id,
        } = &commands[0]
        else {
            panic!("expected DispatchHostOp");
        };
        assert_eq!(correlation_id, "corr-tts-1");
        let v: serde_json::Value = serde_json::from_str(action_json).expect("json");
        assert_eq!(v["op"], "generate");
        assert_eq!(v["topic"], "Test");
    }
}
