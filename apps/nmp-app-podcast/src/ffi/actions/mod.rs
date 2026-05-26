//! Podcast-specific action-registration helpers invoked from
//! [`super::register::nmp_app_podcast_register`].
//!
//! `nmp_app_podcast_register` calls `nmp_app_template::register_defaults` for
//! the canonical NMP action modules (NIP-02 / NIP-17 / NIP-57 / NIP-65) and
//! the production routing substrate. This file is the hook point for
//! **Podcast-specific** registrations that the template intentionally does not
//! ship — NIP-74 podcast feed actions, episode playback intents, chapter
//! navigation, etc.
//!
//! For M3.A the action *types* are defined here so the iOS shell has a
//! stable contract to encode. The kernel-side `ActionModule` registration
//! (which routes a dispatched action into a [`crate::player::PlayerActor`]
//! mutation and a follow-up [`crate::capability::AudioCommand`]) lands in
//! M3.B alongside the player projection's snapshot wiring.
//!
//! ## Wire shape
//!
//! Every action carries a stable string id Swift can match on:
//!
//! ```text
//! podcast.player.play                  — PlayAction              { episode_id: String }
//! podcast.player.pause                 — PauseAction
//! podcast.player.seek                  — SeekAction              { position_secs: f64 }
//! podcast.player.set_speed             — SetSpeedAction          { speed: f32 }
//! podcast.player.set_volume            — SetVolumeAction         { volume: f32 }
//! podcast.player.set_sleep_timer       — SetSleepTimerAction     { secs: Option<u64> }
//! podcast.player.stop                  — StopAction
//! podcast.player.download              — DownloadEpisodeAction   { episode_id, url }
//! podcast.player.cancel_download       — CancelDownloadAction    { episode_id }
//! podcast.player.pause_download        — PauseDownloadAction     { episode_id }
//! podcast.player.resume_download       — ResumeDownloadAction    { episode_id }
//! podcast.player.cancel_all_downloads  — CancelAllDownloadsAction
//! podcast.voice.speak                  — SpeakAction             { text, voice_id? }
//! podcast.voice.stop                   — StopVoiceAction
//! podcast.voice.set_voice              — SetVoiceAction          { voice_id }
//! podcast.briefing.request             — RequestBriefingAction
//! podcast.briefing.schedule            — ScheduleBriefingAction  { schedule }
//! podcast.briefing.cancel              — CancelBriefingAction
//! podcast.agent.send                   — SendAgentMessageAction  { conversation_id?, message }
//! podcast.agent.approve                — ApproveAction           { approval_id }
//! podcast.agent.deny                   — DenyAction              { approval_id, reason? }
//! podcast.agent.clear                  — ClearConversationAction { conversation_id }
//! podcast.siri.play_latest             — SiriPlayLatestAction    { podcast_id? }
//! podcast.siri.resume                  — SiriResumeAction
//! podcast.wiki.generate                — WikiAction::Generate     { podcast_id, topic }
//! podcast.wiki.delete                  — WikiAction::Delete       { article_id }
//! podcast.wiki.search                  — WikiAction::Search       { query }
//! ```
//!
//! Each id is exposed as a `pub const` so the iOS shell, the lint gate,
//! and the future `ActionModule::action_id` impls reference one string.
//!
//! ## Module layout
//!
//! Player actions live in this `mod.rs`. Voice actions live in
//! [`voice`]. Briefing actions are re-exported from `podcast-briefings`;
//! agent actions are re-exported from `podcast-agent-core`. Each domain
//! owns its wire format; this module is the single import path the
//! iOS shell links against.

pub mod chapters_module;
pub mod picks_module;
pub mod knowledge_module;
pub mod memory_module;
pub mod clip_module;
pub mod inbox_module;
pub mod agent_module;
pub(crate) mod categorization_keywords;
pub mod categorization_module;
pub mod player_module;
pub mod podcast_module;
pub mod queue_module;
pub mod tasks_module;
pub mod tts_module;
pub mod publish_module;
pub mod settings_module;
pub mod voice;
pub mod wiki_module;
pub mod siri_module;
pub mod voice_module;

pub use chapters_module::{ChaptersAction, ChaptersActionModule};
pub use picks_module::{AgentPicksModule, PicksAction, PICKS_LIMIT, PICKS_PER_SHOW_CAP};
pub use knowledge_module::{
    KnowledgeAction, KnowledgeActionModule, ACTION_KNOWLEDGE_CLEAR_RESULTS,
    ACTION_KNOWLEDGE_INDEX_EPISODE, ACTION_KNOWLEDGE_SEARCH,
};
pub use memory_module::{MemoryAction, MemoryActionModule};
pub use clip_module::{
    ClipAction, ClipActionModule, ACTION_CLIP_AUTO_SNIP, ACTION_CLIP_CREATE, ACTION_CLIP_DELETE,
};
pub use inbox_module::{
    InboxAction, InboxActionModule, ACTION_INBOX_DISMISS, ACTION_INBOX_MARK_LISTENED,
    ACTION_INBOX_TRIAGE,
};
pub use agent_module::{AgentActionModule, AgentChatAction};
pub use categorization_module::{
    categorize_text, CategorizationAction, CategorizationModule, ACTION_CATEGORIZE_EPISODE,
    ACTION_CATEGORIZE_RUN, CATEGORY_KEYWORDS, MAX_CATEGORIES_PER_EPISODE,
};
pub use player_module::{
    PlayerAction, PlayerActionModule,
    ACTION_PLAYER_CANCEL_ALL_DOWNLOADS, ACTION_PLAYER_CANCEL_DOWNLOAD,
    ACTION_PLAYER_DOWNLOAD, ACTION_PLAYER_PAUSE, ACTION_PLAYER_PAUSE_DOWNLOAD,
    ACTION_PLAYER_PLAY, ACTION_PLAYER_RESUME_DOWNLOAD, ACTION_PLAYER_SEEK,
    ACTION_PLAYER_SET_SLEEP_TIMER, ACTION_PLAYER_SET_SPEED, ACTION_PLAYER_SET_VOLUME,
    ACTION_PLAYER_SKIP_BACKWARD, ACTION_PLAYER_SKIP_FORWARD, ACTION_PLAYER_STOP,
    CancelAllDownloadsAction, CancelDownloadAction, DownloadEpisodeAction, PauseAction,
    PauseDownloadAction, PlayAction, ResumeDownloadAction, SeekAction, SetSleepTimerAction,
    SetSpeedAction, SetVolumeAction, StopAction,
};
pub use podcast_module::{PodcastAction, PodcastActionModule};
pub use queue_module::{QueueAction, QueueActionModule};
pub use wiki_module::{WikiAction, WikiActionModule};
pub use tasks_module::{AgentTasksAction, AgentTasksModule};
pub use tts_module::{
    TtsEpisodeAction, TtsEpisodeModule, ACTION_TTS_DELETE, ACTION_TTS_GENERATE, ACTION_TTS_PLAY,
    TTS_NAMESPACE,
};
pub use publish_module::{
    NipF4PublishModule, PublishAction, ACTION_PUBLISH_CREATE_OWNED,
    ACTION_PUBLISH_PUBLISH_AUTHOR_CLAIM, ACTION_PUBLISH_PUBLISH_EPISODE,
    ACTION_PUBLISH_PUBLISH_SHOW, ACTION_PUBLISH_REMOVE_OWNED,
};
pub use voice_module::{VoiceAction, VoiceActionModule};
pub use settings_module::{SettingsAction, SettingsActionModule};
pub use siri_module::{
    SiriAction, SiriActionModule, ACTION_SIRI_PLAY_LATEST, ACTION_SIRI_RESUME,
    SiriPlayLatestAction, SiriResumeAction,
};

pub use voice::{
    SetVoiceAction, SpeakAction, StopVoiceAction, ACTION_VOICE_SET_VOICE, ACTION_VOICE_SPEAK,
    ACTION_VOICE_STOP,
};

/// `podcast.voice.activate` — enter voice mode (begin STT).
pub const ACTION_VOICE_ACTIVATE: &str = "podcast.voice.activate";
/// `podcast.voice.deactivate` — exit voice mode (stop STT).
pub const ACTION_VOICE_DEACTIVATE: &str = "podcast.voice.deactivate";

// ---------------------------------------------------------------------------
// Briefing actions (re-exported from `podcast-briefings` for M9.A)
// ---------------------------------------------------------------------------
//
// The briefing action ids + payloads live in `podcast-briefings` so the
// crate that owns the briefing/scheduler domain also owns its wire
// format. Re-exported through this module so the iOS shell links against
// `nmp_app_podcast::ffi::actions::ACTION_BRIEFING_*` exactly like the
// player / agent / voice actions — one import path for every action
// contract.
pub use podcast_briefings::{
    CancelBriefingAction, RequestBriefingAction, ScheduleBriefingAction, ACTION_BRIEFING_CANCEL,
    ACTION_BRIEFING_REQUEST, ACTION_BRIEFING_SCHEDULE,
};

// ---------------------------------------------------------------------------
// Agent actions (re-exported from `podcast-agent-core` for M7.A)
// ---------------------------------------------------------------------------
//
// The agent-chat action ids + payloads live in `podcast-agent-core` so the
// crate that owns the conversation/approval domain also owns its wire
// format. Re-exported through this module so the iOS shell links against
// `nmp_app_podcast::ffi::actions::ACTION_AGENT_*` exactly like the player
// actions above — one import path for every action contract.
pub use podcast_agent_core::{
    ApproveAction as AgentApproveAction, ClearConversationAction as AgentClearConversationAction,
    DenyAction as AgentDenyAction, SendAgentMessageAction, ACTION_AGENT_APPROVE,
    ACTION_AGENT_CLEAR, ACTION_AGENT_DENY, ACTION_AGENT_SEND,
};

// Wire-contract tests live in `actions_tests.rs` to keep this file under
// the 500-line hard limit (AGENTS.md).
#[cfg(test)]
#[path = "actions_tests.rs"]
mod tests;

