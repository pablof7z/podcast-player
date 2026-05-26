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
#[path = "tts_module_tests.rs"]
mod tests;
